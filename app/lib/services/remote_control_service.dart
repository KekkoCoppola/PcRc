import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/remote_snapshot.dart';
import 'pc_remote.dart';

/// Firebase Realtime Database (REST) per l'agent sul PC, Home Assistant (REST) per la presa.
class RemoteControlService implements PcRemote {
  RemoteControlService(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;
  final Random _random = Random();

  String get _dbUrl => _withoutTrailingSlash(config.firebaseDbUrl);
  String get _haUrl => _withoutTrailingSlash(config.haBaseUrl);

  Map<String, String> get _haHeaders => {
        'Authorization': 'Bearer ${config.haToken}',
        'Content-Type': 'application/json',
      };

  @override
  Future<RemoteSnapshot?> fetchSnapshot() async {
    try {
      final response =
          await _client.get(Uri.parse('$_dbUrl/.json')).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      return RemoteSnapshot.fromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> sendAppCommand(String appKey, String action) =>
      _sendCommand('apps/$appKey', action);

  @override
  Future<String?> sendPcCommand(String action) => _sendCommand('pc', action);

  /// Scrive `<node>/command` con un id nuovo: l'agent lo esegue una volta sola e
  /// pubblica l'esito in `<node>/result` con lo stesso id.
  Future<String?> _sendCommand(String node, String action) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';
    try {
      final response = await _client
          .put(
            Uri.parse('$_dbUrl/$node/command.json'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'action': action,
              // Timestamp del server: l'agent scarta i comandi troppo vecchi
              'ts': {'.sv': 'timestamp'},
            }),
          )
          .timeout(const Duration(seconds: 8));
      return _isSuccess(response) ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Scrive `devices/<token>`: il token FCM contiene solo caratteri ammessi nelle chiavi.
  @override
  Future<bool> registerDevice(String token) async {
    try {
      final response = await _client
          .put(
            Uri.parse('$_dbUrl/devices/$token.json'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'platform': 'android',
              'ts': {'.sv': 'timestamp'},
            }),
          )
          .timeout(const Duration(seconds: 8));
      return _isSuccess(response);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool?> fetchPlugOn() async {
    try {
      final response = await _client
          .get(Uri.parse('$_haUrl/api/states/${config.haSwitchEntity}'), headers: _haHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      final state = decoded is Map ? decoded['state'] : null;
      return switch (state) {
        'on' => true,
        'off' => false,
        _ => null, // es. "unavailable": presa scollegata dal Wi-Fi
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> setPlug(bool on) async {
    final service = on ? 'turn_on' : 'turn_off';
    try {
      final response = await _client
          .post(
            Uri.parse('$_haUrl/api/services/switch/$service'),
            headers: _haHeaders,
            body: jsonEncode({'entity_id': config.haSwitchEntity}),
          )
          .timeout(const Duration(seconds: 10));
      return _isSuccess(response);
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() => _client.close();

  static bool _isSuccess(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

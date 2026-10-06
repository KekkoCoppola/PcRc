import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/app_info.dart';
import '../models/pc_status.dart';

class RemoteControlService {
  static const String _firebaseBaseUrl =
      'https://rcpc-3ed45-default-rtdb.europe-west1.firebasedatabase.app';
  static const String _homeAssistantTurnOnUrl =
      'https://casacoppola.top/api/services/switch/turn_on';
  static const String _homeAssistantTurnOffUrl =
      'https://casacoppola.top/api/services/switch/turn_off';
  static const String _homeAssistantToken =
      '<HA_TOKEN: vedi secrets.json>';
  static const String _switchEntityId = 'switch.computer_presa_1';

  final http.Client _client;
  final Random _random = Random();

  RemoteControlService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches PC heartbeat status from Firebase Realtime Database
  Future<PcStatus> fetchPcStatus() async {
    final uri = Uri.parse('$_firebaseBaseUrl/pc_status.json');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return PcStatus.fromJson(decoded);
        }
      }
      return PcStatus(fetchTime: DateTime.now());
    } catch (_) {
      return PcStatus(fetchTime: DateTime.now());
    }
  }

  /// Fetches apps state from Firebase Realtime Database
  Future<Map<String, AppInfo>> fetchAppsStatus() async {
    final uri = Uri.parse('$_firebaseBaseUrl/apps.json');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final Map<String, AppInfo> results = {};

          // Claude
          final claudeData = decoded['claude'] is Map<String, dynamic>
              ? decoded['claude'] as Map<String, dynamic>
              : null;
          results['claude'] = AppInfo.fromJson('claude', 'Claude', claudeData);

          // Antigravity
          final antigravityData = decoded['antigravity'] is Map<String, dynamic>
              ? decoded['antigravity'] as Map<String, dynamic>
              : null;
          results['antigravity'] =
              AppInfo.fromJson('antigravity', 'Antigravity 2.0', antigravityData);

          return results;
        }
      }
    } catch (_) {
      // fallback
    }

    return {
      'claude': AppInfo(key: 'claude', displayName: 'Claude', actualState: 'STOPPED'),
      'antigravity':
          AppInfo(key: 'antigravity', displayName: 'Antigravity 2.0', actualState: 'STOPPED'),
    };
  }

  /// Sends a command ("START" or "STOP") to the PC agent.
  /// Writes `apps/<appKey>/command` with a fresh id: the agent runs it once and
  /// publishes the outcome in `apps/<appKey>/result` with the same id.
  /// Returns the command id, or null if the write failed.
  Future<String?> sendAppCommand(String appKey, String action) async {
    final uri = Uri.parse('$_firebaseBaseUrl/apps/$appKey/command.json');
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';
    try {
      final response = await _client
          .put(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'action': action,
              // Server-assigned timestamp: the agent drops commands that are too old
              'ts': {'.sv': 'timestamp'},
            }),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode >= 200 && response.statusCode < 300 ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Turns on the PC via Home Assistant REST API
  Future<bool> turnOnPc() async {
    final uri = Uri.parse(_homeAssistantTurnOnUrl);
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $_homeAssistantToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'entity_id': _switchEntityId}),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Turns off the PC via Home Assistant REST API
  Future<bool> turnOffPc() async {
    final uri = Uri.parse(_homeAssistantTurnOffUrl);
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $_homeAssistantToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'entity_id': _switchEntityId}),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}

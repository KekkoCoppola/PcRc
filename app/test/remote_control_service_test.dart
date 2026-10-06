import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pcrc/config/app_config.dart';
import 'package:pcrc/services/remote_control_service.dart';

const config = AppConfig(
  firebaseDbUrl: 'https://db.example/',
  haBaseUrl: 'https://ha.example',
  haToken: 'tok',
  haSwitchEntity: 'switch.pc',
);

RemoteControlService serviceReplying(Future<http.Response> Function(http.Request) handler) =>
    RemoteControlService(config, client: MockClient(handler));

void main() {
  group('comandi su Firebase', () {
    test('app command is written where the agent reads it, with id and server timestamp',
        () async {
      late http.Request sent;
      final service = serviceReplying((request) async {
        sent = request;
        return http.Response(request.body, 200);
      });

      final id = await service.sendAppCommand('antigravity', 'STOP');

      expect(sent.method, 'PUT');
      expect(sent.url.toString(), 'https://db.example/apps/antigravity/command.json');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['action'], 'STOP');
      expect(id, isNotEmpty);
      expect(body['id'], id);
      expect(body['ts'], {'.sv': 'timestamp'});
    });

    test('PC command goes to pc/command', () async {
      late http.Request sent;
      final service = serviceReplying((request) async {
        sent = request;
        return http.Response(request.body, 200);
      });

      await service.sendPcCommand('SHUTDOWN');

      expect(sent.url.toString(), 'https://db.example/pc/command.json');
      expect((jsonDecode(sent.body) as Map)['action'], 'SHUTDOWN');
    });

    test('repeating the same command still gets a new id', () async {
      // Con lo stesso id l'agent lo considererebbe già eseguito.
      final service = serviceReplying((request) async => http.Response(request.body, 200));

      final first = await service.sendAppCommand('claude', 'START');
      final second = await service.sendAppCommand('claude', 'START');

      expect(first, isNot(second));
    });

    test('rejected write returns null', () async {
      final service = serviceReplying((request) async => http.Response('Permission denied', 401));

      expect(await service.sendAppCommand('claude', 'START'), isNull);
    });
  });

  group('lettura di Firebase', () {
    test('reads heartbeat, app states and command results in one request', () async {
      late Uri asked;
      final service = serviceReplying((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({
            'pc_status': {'online': true, 'last_seen': 1790000000},
            'pc': {
              'result': {'id': 's1', 'status': 'OK', 'message': 'spegnimento tra 10s'},
            },
            'apps': {
              'claude': {'actual_state': 'RUNNING'},
              'antigravity': {
                'actual_state': 'STOPPED',
                'result': {'id': 'c1', 'status': 'ERRORE', 'message': 'avvio fallito'},
              },
            },
          }),
          200,
        );
      });

      final snapshot = await service.fetchSnapshot();

      expect(asked.toString(), 'https://db.example/.json');
      expect(snapshot!.pcStatus.lastSeen, 1790000000);
      expect(snapshot.pcResult!.id, 's1');
      expect(snapshot.apps['claude']!.isRunning, isTrue);
      expect(snapshot.apps['antigravity']!.result!.message, 'avvio fallito');
    });

    test('empty database reads as a PC that never spoke', () async {
      final service = serviceReplying((request) async => http.Response('null', 200));

      final snapshot = await service.fetchSnapshot();

      expect(snapshot!.pcStatus.lastSeen, isNull);
      expect(snapshot.apps.keys, containsAll(['claude', 'antigravity']));
    });

    test('server error means unreachable', () async {
      final service = serviceReplying((request) async => http.Response('boom', 500));

      expect(await service.fetchSnapshot(), isNull);
    });
  });

  group('presa Home Assistant', () {
    test('reads the switch state with the bearer token', () async {
      late http.Request sent;
      final service = serviceReplying((request) async {
        sent = request;
        return http.Response(jsonEncode({'entity_id': 'switch.pc', 'state': 'on'}), 200);
      });

      expect(await service.fetchPlugOn(), isTrue);
      expect(sent.url.toString(), 'https://ha.example/api/states/switch.pc');
      expect(sent.headers['Authorization'], 'Bearer tok');
    });

    test('unavailable plug or rejected token reads as unknown', () async {
      final unavailable = serviceReplying(
          (request) async => http.Response(jsonEncode({'state': 'unavailable'}), 200));
      final unauthorized = serviceReplying((request) async => http.Response('', 401));

      expect(await unavailable.fetchPlugOn(), isNull);
      expect(await unauthorized.fetchPlugOn(), isNull);
    });

    test('turning the plug off calls switch.turn_off on the configured entity', () async {
      late http.Request sent;
      final service = serviceReplying((request) async {
        sent = request;
        return http.Response('[]', 200);
      });

      expect(await service.setPlug(false), isTrue);
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://ha.example/api/services/switch/turn_off');
      expect(jsonDecode(sent.body), {'entity_id': 'switch.pc'});
    });
  });
}

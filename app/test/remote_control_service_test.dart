import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pcrc/services/remote_control_service.dart';

void main() {
  test('command is written where the PC agent reads it, with id and server timestamp', () async {
    late http.Request sent;
    final service = RemoteControlService(
      client: MockClient((request) async {
        sent = request;
        return http.Response(request.body, 200);
      }),
    );

    final id = await service.sendAppCommand('antigravity', 'STOP');

    expect(sent.method, 'PUT');
    expect(
      sent.url.toString(),
      'https://rcpc-3ed45-default-rtdb.europe-west1.firebasedatabase.app/apps/antigravity/command.json',
    );
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['action'], 'STOP');
    expect(id, isNotEmpty);
    expect(body['id'], id);
    expect(body['ts'], {'.sv': 'timestamp'});
  });

  test('repeating the same command still gets a new id', () async {
    // Con lo stesso id l'agent lo considererebbe già eseguito.
    final service = RemoteControlService(
      client: MockClient((request) async => http.Response(request.body, 200)),
    );

    final first = await service.sendAppCommand('claude', 'START');
    final second = await service.sendAppCommand('claude', 'START');

    expect(first, isNot(second));
  });

  test('rejected write returns null', () async {
    final service = RemoteControlService(
      client: MockClient((request) async => http.Response('Permission denied', 401)),
    );

    expect(await service.sendAppCommand('claude', 'START'), isNull);
  });
}

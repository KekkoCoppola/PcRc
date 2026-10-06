import 'package:flutter_test/flutter_test.dart';
import 'package:pcrc/models/app_info.dart';

void main() {
  test('reads the result the PC published for the last command', () {
    final app = AppInfo.fromJson('antigravity', {
      'actual_state': 'RUNNING',
      'command': {'id': 'c1', 'action': 'START', 'ts': 1790000000000},
      'result': {
        'id': 'c1',
        'action': 'START',
        'status': 'OK',
        'message': 'avviato',
        'ts': 1790000001000,
      },
    });

    expect(app.isRunning, isTrue);
    expect(app.result!.id, 'c1');
    expect(app.result!.status, 'OK');
    expect(app.result!.message, 'avviato');
  });

  test('app that never received a command has no result', () {
    final app = AppInfo.fromJson('claude', {'actual_state': 'STOPPED'});

    expect(app.isRunning, isFalse);
    expect(app.result, isNull);
  });

  test('elapsed time counts from the last state change published by the agent', () {
    final app = AppInfo.fromJson('claude', {'actual_state': 'RUNNING', 'since': 1790000000});
    final now = DateTime.fromMillisecondsSinceEpoch((1790000000 + 125) * 1000);

    expect(app.elapsedAt(now), const Duration(seconds: 125));
    expect(AppInfo.fromJson('claude', {'actual_state': 'RUNNING'}).elapsedAt(now), isNull);
  });

  test('missing node reads as stopped', () {
    expect(AppInfo.fromJson('claude', null).isRunning, isFalse);
  });
}

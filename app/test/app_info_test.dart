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

  test('missing node reads as stopped', () {
    expect(AppInfo.fromJson('claude', null).isRunning, isFalse);
  });
}

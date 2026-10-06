import 'package:flutter_test/flutter_test.dart';
import 'package:pcrc/models/app_info.dart';

void main() {
  test('reads the result the PC published for the last command', () {
    final app = AppInfo.fromJson('antigravity', 'Antigravity 2.0', {
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
    expect(app.resultId, 'c1');
    expect(app.resultStatus, 'OK');
    expect(app.resultMessage, 'avviato');
  });

  test('app that never received a command has no result', () {
    final app = AppInfo.fromJson('claude', 'Claude', {'actual_state': 'STOPPED'});

    expect(app.resultId, isNull);
    expect(app.resultStatus, isNull);
  });
}

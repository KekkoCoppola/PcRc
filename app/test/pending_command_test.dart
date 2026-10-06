import 'package:flutter_test/flutter_test.dart';
import 'package:pcrc/models/command_result.dart';
import 'package:pcrc/models/pending_command.dart';

CommandResult result(String id, String status) => CommandResult(id: id, status: status);

void main() {
  final sentAt = DateTime(2026, 9, 26, 14, 0, 0);
  final pending = PendingCommand(id: 'c2', action: 'STOP', sentAt: sentAt);
  final soon = sentAt.add(const Duration(seconds: 5));

  test('result of an older command is not taken as the answer', () {
    expect(pending.outcome(result('c1', 'OK'), soon), CommandOutcome.waiting);
  });

  test('no result at all keeps waiting', () {
    expect(pending.outcome(null, soon), CommandOutcome.waiting);
  });

  test('command still running on the PC keeps waiting', () {
    expect(pending.outcome(result('c2', 'IN_CORSO'), soon), CommandOutcome.waiting);
  });

  test('OK from the PC means succeeded', () {
    expect(pending.outcome(result('c2', 'OK'), soon), CommandOutcome.succeeded);
  });

  test('ERRORE and SCARTATO from the PC mean failed', () {
    expect(pending.outcome(result('c2', 'ERRORE'), soon), CommandOutcome.failed);
    expect(pending.outcome(result('c2', 'SCARTATO'), soon), CommandOutcome.failed);
  });

  test('a slow start on the PC (40 s) is still awaited', () {
    final slow = sentAt.add(const Duration(seconds: 40));
    expect(pending.outcome(result('c2', 'IN_CORSO'), slow), CommandOutcome.waiting);
  });

  test('no final answer after 61 s is a timeout', () {
    final late = sentAt.add(const Duration(seconds: 61));
    expect(pending.outcome(result('c2', 'IN_CORSO'), late), CommandOutcome.timedOut);
  });
}

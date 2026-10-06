import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcrc/models/app_info.dart';
import 'package:pcrc/models/managed_app.dart';
import 'package:pcrc/widgets/app_card.dart';
import 'package:pcrc/widgets/mono_switch.dart';

void main() {
  final now = DateTime(2026, 10, 7, 12);
  final fiveMinutesAgo = now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;

  Future<void> pumpCard(
    WidgetTester tester, {
    required String state,
    bool online = true,
    bool busy = false,
    VoidCallback? onToggle,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: AppCard(
            app: managedApp('claude'),
            info: AppInfo(key: 'claude', actualState: state, since: fiveMinutesAgo),
            online: online,
            busy: busy,
            onToggle: onToggle ?? () {},
            now: now,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('formatElapsed', () {
    test('picks the largest useful units', () {
      expect(formatElapsed(const Duration(seconds: 12)), '12s');
      expect(formatElapsed(const Duration(minutes: 52, seconds: 40)), '52m');
      expect(formatElapsed(const Duration(hours: 3, minutes: 5)), '3h 05m');
      expect(formatElapsed(const Duration(days: 2, hours: 4, minutes: 30)), '2g 4h');
    });
  });

  testWidgets('running app: Attivo, time since it started, switch on', (tester) async {
    var toggles = 0;
    await pumpCard(tester, state: 'RUNNING', onToggle: () => toggles++);

    expect(find.text('Attivo'), findsOneWidget);
    expect(find.text('da 5m'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(tester.widget<MonoSwitch>(find.byType(MonoSwitch)).value, isTrue);

    await tester.tap(find.byType(MonoSwitch));
    expect(toggles, 1);
  });

  testWidgets('stopped app: Inattivo, switch off', (tester) async {
    await pumpCard(tester, state: 'STOPPED');

    expect(find.text('Inattivo'), findsOneWidget);
    expect(tester.widget<MonoSwitch>(find.byType(MonoSwitch)).value, isFalse);
  });

  testWidgets('command in flight: switch ignores taps', (tester) async {
    var toggles = 0;
    await pumpCard(tester, state: 'STOPPED', busy: true, onToggle: () => toggles++);

    await tester.tap(find.byType(MonoSwitch));

    expect(toggles, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PC not reachable: no elapsed time, switch disabled', (tester) async {
    var toggles = 0;
    await pumpCard(tester, state: 'RUNNING', online: false, onToggle: () => toggles++);

    await tester.tap(find.byType(MonoSwitch));

    expect(find.textContaining('da '), findsNothing);
    expect(toggles, 0);
  });
}

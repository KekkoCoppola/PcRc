import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcrc/controllers/pc_controller.dart';
import 'package:pcrc/main.dart';
import 'package:pcrc/widgets/mono_switch.dart';
import 'package:pcrc/widgets/pc_case_hero.dart';
import 'package:pcrc/widgets/power_button_widget.dart';

import 'support/fake_remote.dart';

void main() {
  late FakeRemote remote;

  setUp(() => remote = FakeRemote());

  Future<void> pumpApp(WidgetTester tester, {bool configured = true, Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final controller = PcController(remote, configured: configured, pollInterval: null);
    await tester.pumpWidget(PcRcApp(controller: controller));
    await tester.pump(); // prima lettura di Firebase
  }

  testWidgets('PC off: photo on top, power button below, no dashboard', (tester) async {
    await pumpApp(tester);

    expect(find.text('PC SPENTO'), findsOneWidget);
    expect(find.byType(PcCaseHero), findsOneWidget);
    expect(find.bySemanticsLabel('PC spento'), findsOneWidget);
    expect(find.byType(PowerButtonWidget), findsOneWidget);
    expect(find.text('Applicazioni & Processi'), findsNothing);
  });

  testWidgets('PC already on: opens on the dashboard, no prototype leftovers', (tester) async {
    final now = DateTime.now();
    remote.heartbeat(now);
    remote.pcSince = now.subtract(const Duration(hours: 2, minutes: 15)).millisecondsSinceEpoch ~/ 1000;

    // Tablet orizzontale: il font di test ha glifi quadrati, servono colonne larghe.
    await pumpApp(tester, size: const Size(1180, 820));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Applicazioni & Processi'), findsOneWidget);
    expect(find.text('Acceso da 2h 15m'), findsOneWidget);
    expect(find.text('Alimentazione PC'), findsNothing);
    expect(find.textContaining('Aggiornamento ogni'), findsNothing);
    expect(find.bySemanticsLabel('PC acceso'), findsOneWidget);
    expect(find.byType(PowerButtonWidget), findsNothing);
    expect(find.textContaining('PROTOTIPO'), findsNothing);
    expect(find.image(const AssetImage('assets/icons/claude.png')), findsOneWidget);
    expect(find.image(const AssetImage('assets/icons/antigravity.png')), findsOneWidget);
    expect(find.text('Inattivo'), findsNWidgets(2));
    expect(find.byType(MonoSwitch), findsNWidgets(2));
  });

  testWidgets('app switch sends START to the PC', (tester) async {
    remote.heartbeat(DateTime.now());
    await pumpApp(tester, size: const Size(1180, 820));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byType(MonoSwitch).first);
    await tester.pump();

    expect(remote.calls, ['app:claude:START']);
  });

  testWidgets('power button turns the plug on and waits for the PC', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(PowerButtonWidget));
    await tester.pump();

    expect(remote.calls, ['plug?', 'plug:on']);
    expect(find.text('AVVIO IN CORSO...'), findsOneWidget);
    expect(find.bySemanticsLabel('PC acceso'), findsOneWidget);
  });

  testWidgets('plug already on: asks before cycling it', (tester) async {
    remote.plugOn = true;
    await pumpApp(tester);

    await tester.tap(find.byType(PowerButtonWidget));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Presa già accesa'), findsOneWidget);
    expect(remote.calls, ['plug?']);

    await tester.tap(find.text('ANNULLA'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(remote.calls, ['plug?']);
    expect(find.text('PC SPENTO'), findsOneWidget);
  });

  group('tap on the PC', () {
    Future<void> openShutdownDialog(WidgetTester tester) async {
      remote.heartbeat(DateTime.now());
      await pumpApp(tester, size: const Size(1180, 820));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byType(PcCaseHero));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('PC on: asks "Vuoi spegnere il PC?", SPEGNI sends SHUTDOWN', (tester) async {
      await openShutdownDialog(tester);
      expect(find.text('Vuoi spegnere il PC?'), findsOneWidget);

      await tester.tap(find.text('SPEGNI'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(remote.calls, ['pc:SHUTDOWN']);
      expect(find.text('Vuoi spegnere il PC?'), findsNothing);
    });

    testWidgets('ANNULLA closes the dialog without sending anything', (tester) async {
      await openShutdownDialog(tester);

      await tester.tap(find.text('ANNULLA'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(remote.calls, isEmpty);
      expect(find.text('Vuoi spegnere il PC?'), findsNothing);
    });

    testWidgets('PC off: tapping the photo does nothing', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byType(PcCaseHero));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Vuoi spegnere il PC?'), findsNothing);
      expect(remote.calls, isEmpty);
    });
  });

  testWidgets('build without secrets.json says so instead of failing silently', (tester) async {
    await pumpApp(tester, configured: false);

    expect(find.text('CONFIGURAZIONE MANCANTE'), findsOneWidget);
    expect(remote.calls, isEmpty);
  });

  testWidgets('Tablet landscape places PC and controls side by side', (tester) async {
    await pumpApp(tester, size: const Size(1180, 820));

    final hero = tester.getRect(find.byType(PcCaseHero));
    final button = tester.getRect(find.byType(PowerButtonWidget));
    expect(hero.right, lessThanOrEqualTo(button.left));
  });

  testWidgets('Phone and tablet portrait stack PC above controls', (tester) async {
    for (final size in const [Size(390, 844), Size(820, 1180)]) {
      await pumpApp(tester, size: size);

      final hero = tester.getRect(find.byType(PcCaseHero));
      final button = tester.getRect(find.byType(PowerButtonWidget));
      expect(hero.bottom, lessThanOrEqualTo(button.top), reason: '$size');
      expect(hero.center.dx, closeTo(size.width / 2, 1), reason: '$size');
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pcrc/main.dart';
import 'package:pcrc/widgets/pc_case_hero.dart';
import 'package:pcrc/widgets/power_button_widget.dart';
import 'package:pcrc/widgets/sleek_outline_button.dart';

void main() {
  testWidgets('Smoke test: shows PC Spento view with centered PowerButtonWidget initially', (WidgetTester tester) async {
    await tester.pumpWidget(const PcRcApp());
    await tester.pump();

    // Verify PC Spento state: PC photo on top, power button below
    expect(find.text('PC SPENTO'), findsOneWidget);
    expect(find.byType(PcCaseHero), findsOneWidget);
    expect(find.bySemanticsLabel('PC spento'), findsOneWidget);
    expect(find.byType(PowerButtonWidget), findsOneWidget);
  });

  testWidgets('Interactive test: tapping power button initiates startup and transitions to dashboard', (WidgetTester tester) async {
    // Tablet landscape: the test font has square glyphs, so labels are much
    // wider than with real fonts; the wide layout gives the dashboard room.
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PcRcApp());
    await tester.pump();

    // Tap the power button
    await tester.tap(find.byType(PowerButtonWidget));
    await tester.pump();

    // Shows booting text and the PC LEDs light up immediately
    expect(find.text('AVVIO IN CORSO...'), findsOneWidget);
    expect(find.bySemanticsLabel('PC acceso'), findsOneWidget);

    // Advance time for LED ignition and transition
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 800));

    // Should now show dashboard under the (still visible) PC
    expect(find.byType(PcCaseHero), findsOneWidget);
    expect(find.byType(SleekOutlineButton), findsWidgets);
    expect(find.text('Applicazioni & Processi'), findsOneWidget);
    expect(find.byType(PowerButtonWidget), findsNothing);

    // No header (title/reload/SPEGNI) and no status banner: refresh is pull-down
    expect(find.text('PC REMOTE'), findsNothing);
    expect(find.text('SPEGNI'), findsNothing);
    expect(find.text('PC Online'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    // Monitored apps use their brand icons
    expect(find.image(const AssetImage('assets/icons/claude.png')), findsOneWidget);
    expect(find.image(const AssetImage('assets/icons/antigravity.png')), findsOneWidget);
  });

  testWidgets('Tablet landscape places PC and controls side by side', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PcRcApp());
    await tester.pump();

    final hero = tester.getRect(find.byType(PcCaseHero));
    final button = tester.getRect(find.byType(PowerButtonWidget));
    expect(hero.right, lessThanOrEqualTo(button.left));
  });

  testWidgets('Phone and tablet portrait stack PC above controls', (WidgetTester tester) async {
    for (final size in const [Size(390, 844), Size(820, 1180)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const PcRcApp());
      await tester.pump();

      final hero = tester.getRect(find.byType(PcCaseHero));
      final button = tester.getRect(find.byType(PowerButtonWidget));
      expect(hero.bottom, lessThanOrEqualTo(button.top), reason: '$size');
      expect(hero.center.dx, closeTo(size.width / 2, 1), reason: '$size');
    }
  });
}

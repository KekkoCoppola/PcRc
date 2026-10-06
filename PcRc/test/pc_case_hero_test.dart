import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcrc/widgets/pc_case_hero.dart';
import 'package:pcrc/widgets/pc_led_painter.dart';

void main() {
  group('PcLedGeometry', () {
    test('imageRectFor keeps aspect ratio and fits inside the box', () {
      for (final size in const [Size(200, 300), Size(400, 300), Size(120, 600)]) {
        final rect = PcLedGeometry.imageRectFor(size);
        expect(rect.width / rect.height, closeTo(PcLedGeometry.aspectRatio, 1e-6));
        expect(rect.left, greaterThanOrEqualTo(-1e-6));
        expect(rect.right, lessThanOrEqualTo(size.width + 1e-6));
        expect(rect.top, 0);
        // Spazio sotto l'immagine riservato all'alone a terra.
        expect(rect.bottom, lessThan(size.height));
      }
    });

    test('imageRectFor centres the image horizontally', () {
      final rect = PcLedGeometry.imageRectFor(const Size(400, 300));
      expect(rect.center.dx, closeTo(200, 1e-6));
    });

    test('strip points map into the image rect as an L going down-left', () {
      const imageRect = Rect.fromLTWH(10, 20, 300, 300 / PcLedGeometry.aspectRatio);
      final points = PcLedGeometry.stripPoints(imageRect);
      expect(points, hasLength(3));
      for (final p in points) {
        expect(imageRect.contains(p), isTrue, reason: '$p outside $imageRect');
      }
      final [top, bend, end] = points;
      // Tratto verticale sul lato destro del fronte...
      expect((top.dx - bend.dx).abs(), lessThan(imageRect.width * 0.02));
      expect(bend.dy, greaterThan(top.dy));
      // ...poi obliquo verso il basso a sinistra.
      expect(end.dx, lessThan(bend.dx));
      expect(end.dy, greaterThan(bend.dy));
    });

    test('floor glow sits in front of the oblique front panel', () {
      const left = PcLedGeometry.floorFrontLeft;
      const right = PcLedGeometry.floorFrontRight;
      // Il bordo inferiore del fronte sale verso destra (case in obliquo)...
      expect(right.dx, greaterThan(left.dx));
      expect(right.dy, lessThan(left.dy));
      // ...e il pavimento "davanti" e' verso il basso a destra, lontano dal fianco.
      expect(PcLedGeometry.floorDepth.dx, greaterThan(0));
      expect(PcLedGeometry.floorDepth.dy, greaterThan(0));
      // Lo spigolo frontale sinistro e' a destra della meta' foto: l'alone
      // non finisce sotto il fianco/retro.
      expect(left.dx, greaterThan(0.5));
    });
  });

  group('PcLedPainter', () {
    late ui.Image image;

    setUp(() async {
      image = await createTestImage(width: 94, height: 145);
    });

    void paintFrame(PcLedPainter painter) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(240, 330));
      recorder.endRecording().dispose();
    }

    test('paints off, igniting and lit frames without errors', () {
      const frames = [
        (reveal: 0.0, intensity: 0.0, ambient: 0.0, spark: 0.0), // spento
        (reveal: 0.0, intensity: 1.0, ambient: 0.0, spark: 1.0), // inizio accensione
        (reveal: 0.3, intensity: 1.0, ambient: 0.0, spark: 1.0), // tratto verticale
        (reveal: 0.7, intensity: 1.0, ambient: 0.4, spark: 1.0), // tratto obliquo
        (reveal: 1.0, intensity: 1.0, ambient: 1.0, spark: 0.0), // acceso
        (reveal: 1.0, intensity: 0.3, ambient: 0.3, spark: 0.0), // spegnimento
      ];
      for (final f in frames) {
        paintFrame(PcLedPainter(
          image: image,
          reveal: f.reveal,
          intensity: f.intensity,
          ambient: f.ambient,
          spark: f.spark,
          hueShift: 0.37,
        ));
      }
    });

    test('shouldRepaint only when a frame value changes', () {
      PcLedPainter make({double hueShift = 0}) => PcLedPainter(
            image: image,
            reveal: 1,
            intensity: 1,
            ambient: 1,
            spark: 0,
            hueShift: hueShift,
          );
      expect(make().shouldRepaint(make()), isFalse);
      expect(make(hueShift: 0.5).shouldRepaint(make()), isTrue);
    });
  });

  group('PcCaseHero', () {
    Widget host({required bool poweredOn, bool disableAnimations = false}) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Center(child: PcCaseHero(poweredOn: poweredOn, height: 320)),
        ),
      );
    }

    testWidgets('switches semantics label between off and on', (tester) async {
      await tester.pumpWidget(host(poweredOn: false));
      expect(find.bySemanticsLabel('PC spento'), findsOneWidget);

      await tester.pumpWidget(host(poweredOn: true));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.bySemanticsLabel('PC acceso'), findsOneWidget);

      await tester.pumpWidget(host(poweredOn: false));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.bySemanticsLabel('PC spento'), findsOneWidget);
    });

    testWidgets('loops the RGB flow while on and stops once off', (tester) async {
      await tester.pumpWidget(host(poweredOn: false));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(host(poweredOn: true));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(host(poweredOn: false));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion lights the strip without looping', (tester) async {
      await tester.pumpWidget(host(poweredOn: false, disableAnimations: true));
      await tester.pumpWidget(host(poweredOn: true, disableAnimations: true));
      await tester.pump();
      expect(find.bySemanticsLabel('PC acceso'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('mounting already on skips the ignition', (tester) async {
      await tester.pumpWidget(host(poweredOn: true));
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<PcLedPainter>();
      // Finche' l'immagine non e' decodificata il painter puo' mancare:
      // se c'e', deve essere gia' a piena accensione.
      for (final p in painters) {
        expect(p.reveal, 1.0);
        expect(p.intensity, 1.0);
      }
      expect(find.bySemanticsLabel('PC acceso'), findsOneWidget);
    });
  });
}

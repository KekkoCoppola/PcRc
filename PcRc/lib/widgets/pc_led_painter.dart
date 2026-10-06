import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Geometria della striscia LED a "L" del case (tratto verticale sul lato
/// destro del fronte + tratto obliquo), normalizzata 0–1 sull'immagine
/// `assets/images/pc_case.webp`.
///
/// Valori generati da `tools/prepare_pc_asset.py`: se l'asset cambia,
/// rigenerarli insieme.
abstract final class PcLedGeometry {
  static const double aspectRatio = 944 / 1446;

  static const Offset top = Offset(0.9434, 0.0685);
  static const Offset bend = Offset(0.9400, 0.3575);
  static const Offset end = Offset(0.5510, 0.7898);

  /// Spessore della striscia come frazione della larghezza dell'immagine.
  static const double stripWidth = 0.0064;

  /// Spigoli inferiori del pannello frontale: la luce della striscia tocca
  /// terra davanti a questo bordo.
  static const Offset floorFrontLeft = Offset(0.5445, 0.9890);
  static const Offset floorFrontRight = Offset(0.9810, 0.9046);

  /// Direzione retro -> fronte sul pavimento, lunga quanto la profondita' del
  /// case (bordo inferiore del fianco): da' la prospettiva all'alone.
  static const Offset floorDepth = Offset(0.5191, 0.1929);

  /// Quota dell'altezza del box occupata dalla foto: il resto ospita l'alone a terra.
  static const double imageHeightFraction = 0.94;

  /// Rettangolo della foto dentro [size]: in alto, centrata, proporzioni intatte.
  static Rect imageRectFor(Size size) {
    var height = size.height * imageHeightFraction;
    var width = height * aspectRatio;
    if (width > size.width) {
      width = size.width;
      height = width / aspectRatio;
    }
    return Rect.fromLTWH((size.width - width) / 2, 0, width, height);
  }

  /// Estremi della striscia (alto, piega, fine) in coordinate di [imageRect].
  static List<Offset> stripPoints(Rect imageRect) => [
        for (final p in const [top, bend, end])
          Offset(
            imageRect.left + p.dx * imageRect.width,
            imageRect.top + p.dy * imageRect.height,
          ),
      ];
}

/// Disegna la foto del case e sopra la striscia LED RGB:
/// alone a terra, riverbero colorato sul case, striscia con glow e la
/// "scintilla" che la percorre durante l'accensione.
class PcLedPainter extends CustomPainter {
  PcLedPainter({
    required this.image,
    required this.reveal,
    required this.intensity,
    required this.ambient,
    required this.spark,
    required this.hueShift,
  });

  final ui.Image image;

  /// Porzione di striscia accesa, dall'estremo alto (0) alla fine dell'obliquo (1).
  final double reveal;

  /// Luminosità della striscia: 0 spenta, 1 piena.
  final double intensity;

  /// Riverbero sul case e alone a terra: 0–1.
  final double ambient;

  /// Forza della scintilla bianca in testa alla striscia durante l'accensione.
  final double spark;

  /// Scorrimento dell'arcobaleno lungo la striscia (0–1, ciclico).
  final double hueShift;

  static const int _gradientStops = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final imageRect = PcLedGeometry.imageRectFor(size);
    final [top, bend, end] = PcLedGeometry.stripPoints(imageRect);
    final stroke = math.max(PcLedGeometry.stripWidth * imageRect.width, 1.2);
    final verticalLength = (bend - top).distance;
    final bendAt = verticalLength / (verticalLength + (end - bend).distance);
    final glow = ambient * intensity;

    // Riflessi e alone restano dentro il box del widget.
    canvas.clipRect(Offset.zero & size);
    if (glow > 0.001) _paintFloorGlow(canvas, imageRect, bendAt, glow);
    _paintCase(canvas, imageRect);
    if (intensity <= 0.001) return;

    final segments = [
      _Segment(top, bend, 0, bendAt).clipTo(reveal),
      _Segment(bend, end, bendAt, 1).clipTo(reveal),
    ].nonNulls.toList();
    if (segments.isEmpty) return;

    if (glow > 0.001) _paintSpill(canvas, imageRect, segments, stroke, glow);
    for (final segment in segments) {
      _paintStrip(canvas, segment, stroke);
    }
    if (spark > 0.001) _paintSpark(canvas, segments.last, stroke);
  }

  Color _hue(double s, {double saturation = 1, double alpha = 1}) {
    return HSVColor.fromAHSV(
      alpha.clamp(0.0, 1.0),
      ((s - hueShift) % 1.0) * 360,
      saturation,
      1,
    ).toColor();
  }

  /// Gradiente lineare sul segmento: su un tratto retto equivale al
  /// gradiente lungo il percorso, quindi i colori combaciano alla piega.
  Shader _stripShader(_Segment segment, {double saturation = 1, required double alpha}) {
    return ui.Gradient.linear(
      segment.a,
      segment.b,
      [
        for (var i = 0; i < _gradientStops; i++)
          _hue(
            segment.s0 + (segment.s1 - segment.s0) * i / (_gradientStops - 1),
            saturation: saturation,
            alpha: alpha,
          ),
      ],
      [for (var i = 0; i < _gradientStops; i++) i / (_gradientStops - 1)],
    );
  }

  void _paintCase(Canvas canvas, Rect imageRect) {
    // Da spento la foto e' leggermente piu' cupa; il riverbero la "riaccende".
    final level = (0.82 + 0.18 * ambient * intensity).clamp(0.0, 1.0);
    final grey = (255 * level).round();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = level < 1
            ? ColorFilter.mode(Color.fromARGB(255, grey, grey, grey), BlendMode.modulate)
            : null,
    );
  }

  /// Alone a terra davanti al pannello frontale, in prospettiva: un cerchio
  /// unitario deformato sugli assi "bordo frontale" e "profondita'" del
  /// pavimento, cosi' segue l'obliquo del case e non finisce dietro al fianco.
  void _paintFloorGlow(Canvas canvas, Rect imageRect, double bendAt, double glow) {
    Offset map(Offset p) => Offset(
          imageRect.left + p.dx * imageRect.width,
          imageRect.top + p.dy * imageRect.height,
        );
    final frontLeft = map(PcLedGeometry.floorFrontLeft);
    final frontRight = map(PcLedGeometry.floorFrontRight);
    final depth = Offset(
      PcLedGeometry.floorDepth.dx * imageRect.width,
      PcLedGeometry.floorDepth.dy * imageRect.height,
    );
    final alongFront = (frontRight - frontLeft) / 2;
    final forward = depth * 0.35;
    final center = (frontLeft + frontRight) / 2 + forward * 0.3;
    final color = _hue((bendAt + 1) / 2, saturation: 0.9);

    canvas.save();
    canvas.transform(Float64List.fromList([
      alongFront.dx, alongFront.dy, 0, 0, //
      forward.dx, forward.dy, 0, 0,
      0, 0, 1, 0,
      center.dx, center.dy, 0, 1,
    ]));
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 1, [
          color.withValues(alpha: 0.5 * glow),
          color.withValues(alpha: 0.14 * glow),
          color.withValues(alpha: 0),
        ], const [0.0, 0.5, 1.0]),
    );
    canvas.restore();
  }

  /// Luce colorata che "bagna" il case vicino alla striscia: disegnata in un
  /// layer, ritagliata sulla sagoma della foto (dstIn) e sommata in screen.
  void _paintSpill(
    Canvas canvas,
    Rect imageRect,
    List<_Segment> segments,
    double stroke,
    double glow,
  ) {
    canvas.save();
    canvas.clipRect(imageRect);
    canvas.saveLayer(imageRect, Paint()..blendMode = BlendMode.screen);
    for (final segment in segments) {
      canvas.drawLine(
        segment.a,
        segment.b,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke * 22
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 11)
          ..shader = _stripShader(segment, alpha: 0.32 * glow),
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    canvas.restore();
  }

  void _paintStrip(Canvas canvas, _Segment segment, double stroke) {
    if ((segment.b - segment.a).distance < 0.5) return;
    // Alone largo, glow medio, nucleo quasi bianco: aspetto da LED diffuso.
    const layers = [
      (width: 6.5, blur: 3.2, saturation: 1.0, alpha: 0.55),
      (width: 2.4, blur: 1.0, saturation: 0.95, alpha: 0.9),
      (width: 0.9, blur: 0.0, saturation: 0.3, alpha: 1.0),
    ];
    for (final layer in layers) {
      canvas.drawLine(
        segment.a,
        segment.b,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke * layer.width
          ..maskFilter = layer.blur > 0
              ? MaskFilter.blur(BlurStyle.normal, stroke * layer.blur)
              : null
          ..shader = _stripShader(
            segment,
            saturation: layer.saturation,
            alpha: layer.alpha * intensity,
          ),
      );
    }
  }

  void _paintSpark(Canvas canvas, _Segment head, double stroke) {
    final alpha = spark * intensity;
    canvas.drawCircle(
      head.b,
      stroke * 6,
      Paint()
        ..color = _hue(head.s1, alpha: 0.55 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 5),
    );
    canvas.drawCircle(
      head.b,
      stroke * 1.8,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.2),
    );
  }

  @override
  bool shouldRepaint(PcLedPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.reveal != reveal ||
        oldDelegate.intensity != intensity ||
        oldDelegate.ambient != ambient ||
        oldDelegate.spark != spark ||
        oldDelegate.hueShift != hueShift;
  }
}

/// Tratto retto di striscia da [a] a [b], che copre la frazione [s0]–[s1]
/// della lunghezza totale.
class _Segment {
  const _Segment(this.a, this.b, this.s0, this.s1);

  final Offset a;
  final Offset b;
  final double s0;
  final double s1;

  /// Parte del tratto accesa quando la striscia e' rivelata fino a [reveal].
  _Segment? clipTo(double reveal) {
    if (reveal <= s0) return null;
    if (reveal >= s1) return this;
    final t = (reveal - s0) / (s1 - s0);
    return _Segment(a, Offset.lerp(a, b, t)!, s0, reveal);
  }
}

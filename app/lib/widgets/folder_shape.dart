import 'package:flutter/material.dart';

/// Sagoma a cartella nera con bordo bianco: linguetta in alto a sinistra che scende
/// con una curva a S nel corpo. Usata dalle card dei processi e dai modali.
class FolderPainter extends CustomPainter {
  FolderPainter({required this.glow, required this.borderAlpha, this.tabWidth = defaultTabWidth});

  static const double defaultTabWidth = 122;
  static const double tabHeight = 34;
  static const double _radius = 18;
  static const double _slope = 22;

  /// 0 = spenta, 1 = in evidenza (alone bianco e fondo leggermente più chiaro).
  final double glow;
  final double borderAlpha;
  final double tabWidth;

  Path _shape(Size size) {
    final w = size.width, h = size.height, tw = tabWidth;
    const r = _radius, t = tabHeight, s = _slope;
    const corner = Radius.circular(r);
    return Path()
      ..moveTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: corner)
      ..lineTo(tw - s, 0)
      ..cubicTo(tw, 0, tw, t, tw + s, t)
      ..lineTo(w - r, t)
      ..arcToPoint(Offset(w, t + r), radius: corner)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: corner)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: corner)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _shape(size);
    final bounds = Offset.zero & size;

    canvas.drawShadow(path, Colors.black, 10, false);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = Colors.white.withValues(alpha: 0.10 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(const Color(0xFF101116), const Color(0xFF16171D), glow)!,
            const Color(0xFF06070A),
          ],
        ).createShader(bounds),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: borderAlpha),
    );
  }

  @override
  bool shouldRepaint(covariant FolderPainter old) =>
      old.glow != glow || old.borderAlpha != borderAlpha || old.tabWidth != tabWidth;
}

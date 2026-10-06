import 'package:flutter/material.dart';

/// A sleek, modern ambient dark background with:
/// 1. Deep rich black base (#08090C)
/// 2. Soft, subtle white ambient spotlight at the top/center
/// 3. Ultra-fine brushed texture / subtle grey shading
class PcRcAmbientBackground extends StatelessWidget {
  final Widget child;

  const PcRcAmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Solid deep black foundation
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0xFF08090C),
          ),
        ),

        // Subtle brushed texture & horizontal metal sheen
        Positioned.fill(
          child: CustomPaint(
            painter: _BrushedMetalPainter(),
          ),
        ),

        // Soft white ambient light vignette centered towards the upper-middle
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.35),
                radius: 1.15,
                colors: [
                  Colors.white.withValues(alpha: 0.048),
                  Colors.white.withValues(alpha: 0.018),
                  Colors.white.withValues(alpha: 0.005),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4, 0.7, 1.0],
              ),
            ),
          ),
        ),

        // Secondary subtle cool bottom fill to create natural contrast
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.35),
                ],
                stops: const [0.7, 1.0],
              ),
            ),
          ),
        ),

        // Foreground content
        child,
      ],
    );
  }
}

/// Custom painter for horizontal brushed metal micro-lines and subtle depth
class _BrushedMetalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.008)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw sparse, ultra-subtle horizontal micro-streaks for realistic brushed dark aluminum feel
    const step = 4.0;
    for (double y = 0; y < size.height; y += step) {
      final alpha = ((y * 13) % 7) == 0 ? 0.012 : 0.004;
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

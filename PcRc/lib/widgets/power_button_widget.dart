import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive Photorealistic Power Button matching the user's reference image:
/// - Left state: dark recessed bezel, dormant metallic power symbol
/// - Right state: illuminated neon cyan ring, glowing cyan power symbol, expanding ripple shockwaves
class PowerButtonWidget extends StatefulWidget {
  final bool isOnline;
  final bool isBooting;
  final VoidCallback onTap;
  final double size;

  const PowerButtonWidget({
    super.key,
    required this.isOnline,
    required this.isBooting,
    required this.onTap,
    this.size = 220,
  });

  @override
  State<PowerButtonWidget> createState() => _PowerButtonWidgetState();
}

class _PowerButtonWidgetState extends State<PowerButtonWidget>
    with TickerProviderStateMixin {
  late AnimationController _idleBreathingController;
  late Animation<double> _idleBreathingAnimation;

  late AnimationController _ignitionController;
  late Animation<double> _ignitionProgress;

  late AnimationController _rippleController;

  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();

    // 1. Idle breathing pulse for dormant/off state
    _idleBreathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _idleBreathingAnimation = Tween<double>(begin: 0.985, end: 1.015).animate(
      CurvedAnimation(
        parent: _idleBreathingController,
        curve: Curves.easeInOutSine,
      ),
    );

    // 2. Ignition animation when powered on / booting
    _ignitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _ignitionProgress = CurvedAnimation(
      parent: _ignitionController,
      curve: Curves.easeOutBack,
    );

    // 3. Shockwave ripple controller
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    if (widget.isOnline || widget.isBooting) {
      _ignitionController.value = 1.0;
      _rippleController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant PowerButtonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.isOnline || widget.isBooting) && !oldWidget.isOnline && !oldWidget.isBooting) {
      _ignitionController.forward(from: 0.0);
      _rippleController.forward(from: 0.0);
    } else if (!widget.isOnline && !widget.isBooting && (oldWidget.isOnline || oldWidget.isBooting)) {
      _ignitionController.reverse();
      _rippleController.stop();
    }
  }

  @override
  void dispose() {
    _idleBreathingController.dispose();
    _ignitionController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.isBooting || widget.isOnline) return;
    _ignitionController.forward(from: 0.0);
    _rippleController.forward(from: 0.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final double buttonSize = widget.size;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: (widget.isBooting || widget.isOnline)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) {
          if (!widget.isBooting && !widget.isOnline) {
            setState(() => _isPressed = true);
          }
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _idleBreathingAnimation,
            _ignitionProgress,
            _rippleController,
          ]),
          builder: (context, child) {
            final double ignition = _ignitionProgress.value;
            final double idleScale = (widget.isOnline || widget.isBooting)
                ? 1.0
                : _idleBreathingAnimation.value;
            final double pressScale = _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0);

            return SizedBox(
              width: buttonSize + 60,
              height: buttonSize + 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. Expanding shockwave ring on ignition/booting
                  if (ignition > 0.05) ...[
                    CustomPaint(
                      size: Size(buttonSize + 60, buttonSize + 60),
                      painter: _ShockwavePainter(
                        progress: _rippleController.value,
                        ignition: ignition,
                      ),
                    ),
                  ],

                  // 2. The Power Button Container with Bevel & Glow
                  Transform.scale(
                    scale: idleScale * pressScale,
                    child: Container(
                      width: buttonSize,
                      height: buttonSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Concentric Bevel Shadow
                        boxShadow: [
                          // Recessed outer drop shadow
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.85),
                            blurRadius: 28,
                            spreadRadius: 4,
                            offset: const Offset(0, 14),
                          ),
                          // Electric cyan neon halo glow when lit
                          if (ignition > 0.01) ...[
                            BoxShadow(
                              color: const Color(0xFF00E5FF)
                                  .withValues(alpha: 0.55 * ignition),
                              blurRadius: 36 * ignition,
                              spreadRadius: 3 * ignition,
                            ),
                            BoxShadow(
                              color: const Color(0xFF00B0FF)
                                  .withValues(alpha: 0.35 * ignition),
                              blurRadius: 60 * ignition,
                              spreadRadius: 10 * ignition,
                            ),
                          ],
                        ],
                        // Outer metallic bevel rim gradient
                        gradient: RadialGradient(
                          center: const Alignment(-0.2, -0.3),
                          radius: 1.0,
                          colors: [
                            const Color(0xFF2E313A),
                            const Color(0xFF1B1C22),
                            const Color(0xFF101115),
                            const Color(0xFF08090C),
                          ],
                          stops: const [0.0, 0.45, 0.85, 1.0],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(7.0),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Inner groove ring gradient
                            gradient: RadialGradient(
                              center: const Alignment(0.2, 0.3),
                              radius: 0.95,
                              colors: [
                                const Color(0xFF0A0B0E),
                                const Color(0xFF14151B),
                                const Color(0xFF1B1D24),
                                const Color(0xFF0D0E12),
                              ],
                              stops: const [0.0, 0.6, 0.9, 1.0],
                            ),
                            border: Border.all(
                              color: Color.lerp(
                                const Color(0xFF282A33),
                                const Color(0xFF00E5FF),
                                ignition,
                              )!,
                              width: 2.2,
                            ),
                          ),
                          child: Center(
                            child: CustomPaint(
                              size: Size(buttonSize * 0.75, buttonSize * 0.75),
                              painter: _IecPowerSymbolPainter(
                                ignition: ignition,
                                isHovered: _isHovered,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Custom painter for the expanding electric ripple rings
class _ShockwavePainter extends CustomPainter {
  final double progress;
  final double ignition;

  _ShockwavePainter({required this.progress, required this.ignition});

  @override
  void paint(Canvas canvas, Size size) {
    if (ignition <= 0.05) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    final minRadius = (size.width / 2) * 0.65;

    final currentRadius = minRadius + (maxRadius - minRadius) * progress;
    final alpha = (1.0 - progress) * 0.45 * ignition;

    if (alpha <= 0.01) return;

    final paint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * (1.0 - progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(center, currentRadius, paint);
  }

  @override
  bool shouldRepaint(covariant _ShockwavePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.ignition != ignition;
  }
}

/// Precise IEC 60417-5009 Power Symbol Painter:
/// Arc with top gap + vertical bar inside gap.
/// Renders authentic metallic dark state or glowing electric cyan neon with bloom.
class _IecPowerSymbolPainter extends CustomPainter {
  final double ignition;
  final bool isHovered;

  _IecPowerSymbolPainter({
    required this.ignition,
    required this.isHovered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.38;
    final strokeWidth = size.width * 0.082;

    // Off state color: dark metallic charcoal
    final offColor = isHovered ? const Color(0xFF3F4452) : const Color(0xFF282B34);
    // On state color: bright neon cyan
    const onColor = Color(0xFF00F5FF);

    final activeColor = Color.lerp(offColor, onColor, ignition)!;

    // 1. Neon Bloom Shadow Pass (when lit)
    if (ignition > 0.05) {
      final glowPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.65 * ignition)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 6
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      _drawPowerSymbol(canvas, center, radius, glowPaint);
    }

    // 2. Main Stroke Pass
    final mainPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    _drawPowerSymbol(canvas, center, radius, mainPaint);

    // 3. Specular highlight core (when lit)
    if (ignition > 0.3) {
      final corePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85 * ignition)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.38
        ..strokeCap = StrokeCap.round;

      _drawPowerSymbol(canvas, center, radius, corePaint);
    }
  }

  void _drawPowerSymbol(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    // Gap angle at the top is ~64 degrees (1.12 rad)
    // 0 rad is at 3 o'clock. Top is -pi / 2 (-1.5708 rad).
    const gapHalf = 0.58; // radians
    const startAngle = -math.pi / 2 + gapHalf;
    const sweepAngle = 2 * math.pi - (gapHalf * 2);

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);

    // Vertical top bar extending from top gap into circle
    final topY = center.dy - radius * 1.15;
    final bottomY = center.dy + radius * 0.08;
    canvas.drawLine(Offset(center.dx, topY), Offset(center.dx, bottomY), paint);
  }

  @override
  bool shouldRepaint(covariant _IecPowerSymbolPainter oldDelegate) {
    return oldDelegate.ignition != ignition || oldDelegate.isHovered != isHovered;
  }
}

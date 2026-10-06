import 'package:flutter/material.dart';

/// A sleek, slender button with a colored outline and transparent background
/// matching the app/container background, as requested by the user.
class SleekOutlineButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;
  final Widget? icon;
  final Color borderColor;
  final Color? textColor;
  final bool isLoading;
  final double height;
  final double? width;
  final double borderWidth;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double fontSize;
  final bool showGlow;

  const SleekOutlineButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.borderColor = const Color(0xFF00E5FF),
    this.textColor,
    this.isLoading = false,
    this.height = 48,
    this.width,
    this.borderWidth = 1.3,
    this.borderRadius,
    this.padding,
    this.fontSize = 13.5,
    this.showGlow = true,
  });

  @override
  State<SleekOutlineButton> createState() => _SleekOutlineButtonState();
}

class _SleekOutlineButtonState extends State<SleekOutlineButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;
    final radius = widget.borderRadius ?? BorderRadius.circular(12);

    final activeColor = isEnabled ? widget.borderColor : const Color(0xFF374151);
    final textCol = widget.textColor ?? (isEnabled ? widget.borderColor : const Color(0xFF6B7280));

    return MouseRegion(
      onEnter: (_) {
        if (isEnabled) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (isEnabled) setState(() => _isHovered = false);
      },
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) {
          if (isEnabled) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (isEnabled) setState(() => _isPressed = false);
        },
        onTapCancel: () {
          if (isEnabled) setState(() => _isPressed = false);
        },
        onTap: isEnabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.97 : (_isHovered ? 1.015 : 1.0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: widget.height,
            width: widget.width,
            padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              // Strict rule: button background is transparent/matches the app background
              color: _isHovered
                  ? activeColor.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: radius,
              border: Border.all(
                color: _isHovered
                    ? activeColor
                    : activeColor.withValues(alpha: isEnabled ? 0.9 : 0.4),
                width: widget.borderWidth,
              ),
              boxShadow: widget.showGlow && isEnabled
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: _isHovered ? 0.28 : 0.12),
                        blurRadius: _isHovered ? 14 : 8,
                        spreadRadius: _isHovered ? 0.5 : -1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: widget.width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isLoading) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (widget.icon != null) ...[
                  IconTheme(
                    data: IconThemeData(
                      color: textCol,
                      size: widget.fontSize + 4,
                    ),
                    child: widget.icon!,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: textCol,
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

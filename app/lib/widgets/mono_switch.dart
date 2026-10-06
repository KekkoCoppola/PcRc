import 'package:flutter/material.dart';

/// Interruttore on/off bianco e nero: acceso = pista bianca e pomello nero a destra,
/// spento = pista solo bordata e pomello bianco a sinistra. Con [busy] il pomello
/// si ferma al centro con una rotellina, in attesa della risposta del PC.
class MonoSwitch extends StatelessWidget {
  const MonoSwitch({
    super.key,
    required this.value,
    required this.onTap,
    this.busy = false,
    this.semanticLabel,
  });

  final bool value;
  final bool busy;

  /// null = disabilitato.
  final VoidCallback? onTap;
  final String? semanticLabel;

  static const double width = 66;
  static const double height = 34;
  static const double _knob = 26;
  static const _duration = Duration(milliseconds: 260);
  static const _curve = Curves.easeOutCubic;
  static const _black = Color(0xFF08090C);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final knobAlignment =
        busy ? Alignment.center : (value ? Alignment.centerRight : Alignment.centerLeft);

    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: _duration,
          opacity: onTap == null ? 0.35 : 1,
          child: AnimatedContainer(
            duration: _duration,
            curve: _curve,
            width: width,
            height: height,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(color: Colors.white.withValues(alpha: value ? 1 : 0.55), width: 1.4),
              boxShadow: value
                  ? [BoxShadow(color: Colors.white.withValues(alpha: 0.28), blurRadius: 14)]
                  : const [],
            ),
            child: Stack(
              children: [
                if (!busy)
                  Align(
                    alignment: value ? const Alignment(-0.55, 0) : const Alignment(0.6, 0),
                    child: Text(
                      value ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: value ? _black : Colors.white.withValues(alpha: 0.6),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                AnimatedAlign(
                  alignment: knobAlignment,
                  duration: _duration,
                  curve: _curve,
                  child: AnimatedContainer(
                    duration: _duration,
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? _black : Colors.white,
                    ),
                    child: busy
                        ? Padding(
                            padding: const EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: value ? Colors.white : _black,
                            ),
                          )
                        : null,
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

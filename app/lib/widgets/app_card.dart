import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/app_info.dart';
import '../models/managed_app.dart';
import '../utils/format_elapsed.dart';
import 'folder_shape.dart';
import 'mono_switch.dart';

/// Card a cartella di un'app del PC: linguetta con lo stato, tempo dall'ultimo
/// cambio di stato, logo, nome e interruttore on/off. Nera con bordo bianco,
/// più luminosa quando l'app è attiva.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.app,
    required this.info,
    required this.online,
    required this.busy,
    required this.onToggle,
    this.now,
  });

  final ManagedApp app;
  final AppInfo info;

  /// PC acceso e in grado di ricevere comandi.
  final bool online;

  /// Comando già inviato, in attesa dell'esito dal PC.
  final bool busy;
  final VoidCallback onToggle;

  /// Orologio per il tempo trascorso (test); di default l'ora attuale.
  final DateTime? now;

  static const double _bodyHeight = 92;

  @override
  Widget build(BuildContext context) {
    final active = info.isRunning;
    final elapsed = online ? info.elapsedAt(now ?? DateTime.now()) : null;

    return TweenAnimationBuilder<double>(
      tween: Tween(end: active ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => CustomPaint(
        painter: FolderPainter(glow: t, borderAlpha: lerpDouble(0.28, 0.92, t)!),
        child: SizedBox(
          height: FolderPainter.tabHeight + _bodyHeight,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: FolderPainter.defaultTabWidth,
                height: FolderPainter.tabHeight,
                child: _StateTab(active: active, t: t),
              ),
              if (elapsed != null)
                Positioned(
                  right: 6,
                  top: 0,
                  height: FolderPainter.tabHeight,
                  child: _Elapsed(text: 'da ${formatElapsed(elapsed)}', t: t),
                ),
              Positioned.fill(
                top: FolderPainter.tabHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _LogoDiamond(app: app, t: t),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          app.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color.lerp(const Color(0xFFA3A8B4), Colors.white, t),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      MonoSwitch(
                        value: active,
                        busy: busy,
                        semanticLabel: '${app.displayName} on/off',
                        onTap: online ? onToggle : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateTab extends StatelessWidget {
  const _StateTab({required this.active, required this.t});

  final bool active;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 22),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: t),
              border: Border.all(color: Colors.white.withValues(alpha: lerpDouble(0.45, 1, t)!), width: 1.2),
              boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.6 * t), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                active ? 'Attivo' : 'Inattivo',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: lerpDouble(0.55, 1, t)!),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Elapsed extends StatelessWidget {
  const _Elapsed({required this.text, required this.t});

  final String text;
  final double t;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: lerpDouble(0.5, 0.95, t)!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Logo dell'app dentro un rombo nero bordato di bianco, come l'icona dello spunto.
class _LogoDiamond extends StatelessWidget {
  const _LogoDiamond({required this.app, required this.t});

  final ManagedApp app;
  final double t;

  static const double _side = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _side * math.sqrt2,
      height: _side * math.sqrt2,
      child: Center(
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: _side,
            height: _side,
            decoration: BoxDecoration(
              color: const Color(0xFF0B0C10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: lerpDouble(0.3, 0.85, t)!), width: 1.2),
              boxShadow: [
                // Unico tocco di colore: il marchio dell'app, solo quando è attiva
                BoxShadow(color: app.accent.withValues(alpha: 0.35 * t), blurRadius: 18),
              ],
            ),
            child: Transform.rotate(
              angle: -math.pi / 4,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Opacity(
                  opacity: lerpDouble(0.6, 1, t)!,
                  child: Image.asset(app.iconAsset, filterQuality: FilterQuality.medium),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/app_info.dart';
import '../models/managed_app.dart';
import 'sleek_outline_button.dart';

/// Card di un'app del PC: stato pubblicato dall'agent e pulsante AVVIA/ARRESTA.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.app,
    required this.info,
    required this.online,
    required this.busy,
    required this.onToggle,
  });

  final ManagedApp app;
  final AppInfo info;

  /// PC acceso e in grado di ricevere comandi.
  final bool online;

  /// Comando già inviato, in attesa dell'esito dal PC.
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isRunning = online && info.isRunning;
    final stateColor = !online
        ? const Color(0xFF475569)
        : (isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444));
    final actionColor = isRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final name = app.displayName.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1015),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning ? const Color(0xFF10B981).withValues(alpha: 0.35) : const Color(0xFF1F232E),
          width: 1.1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: app.accent.withValues(alpha: 0.5), width: 1.2),
                ),
                child: Center(
                  child: Image.asset(
                    app.iconAsset,
                    width: 22,
                    height: 22,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.subtitle,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: stateColor, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      online ? info.actualState : 'N/D',
                      style: TextStyle(
                        color: online ? stateColor : const Color(0xFF94A3B8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF1A1E29), height: 1),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SleekOutlineButton(
              height: 44,
              borderWidth: 1.3,
              borderColor: actionColor,
              textColor: actionColor,
              isLoading: busy,
              label: busy ? 'ATTENDI PC...' : (isRunning ? 'ARRESTA $name' : 'AVVIA $name'),
              icon: busy ? null : Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
              onPressed: online && !busy ? onToggle : null,
            ),
          ),
        ],
      ),
    );
  }
}

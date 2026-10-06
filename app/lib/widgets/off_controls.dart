import 'package:flutter/material.dart';

import '../controllers/pc_controller.dart';
import 'power_button_widget.dart';

/// Controlli sotto il PC quando è spento: power button, stato e ultimo heartbeat.
class OffControls extends StatelessWidget {
  const OffControls({
    super.key,
    required this.controller,
    required this.width,
    required this.onPowerTap,
  });

  final PcController controller;
  final double width;
  final VoidCallback onPowerTap;

  @override
  Widget build(BuildContext context) {
    final phase = controller.phase;
    final starting = controller.plugBusy || phase == PcPhase.booting;
    final (title, subtitle) = _texts(phase);
    final titleColor = switch (phase) {
      PcPhase.unconfigured => const Color(0xFFEF4444),
      _ when starting => const Color(0xFF00E5FF),
      _ => const Color(0xFFE2E8F0),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IgnorePointer(
            ignoring: phase != PcPhase.off,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: phase == PcPhase.unconfigured || phase == PcPhase.checking ? 0.45 : 1,
              child: PowerButtonWidget(
                size: (width * 0.32).clamp(120.0, 170.0),
                isOnline: controller.dashboardVisible,
                isBooting: starting,
                onTap: onPowerTap,
              ),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              title,
              key: ValueKey<String>(title),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: titleColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 3.5,
                shadows: starting ? const [Shadow(color: Color(0xFF00E5FF), blurRadius: 16)] : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 18),
          _LastSignalChip(
            text: controller.reachable
                ? 'Ultimo segnale: ${controller.pcStatus.describeAt(DateTime.now())}'
                : 'Firebase non raggiungibile',
          ),
          const SizedBox(height: 28),
          const Text(
            'Smart PC Controller • Powered by Home Assistant',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF475569), fontSize: 11, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  (String, String) _texts(PcPhase phase) {
    if (controller.plugBusy) return ('ACCENSIONE...', 'Comando alla presa via Home Assistant');
    return switch (phase) {
      PcPhase.unconfigured => (
          'CONFIGURAZIONE MANCANTE',
          'App compilata senza secrets.json: ricompila con scripts/build_apk.ps1'
        ),
      PcPhase.checking => ('CONTROLLO STATO...', 'Leggo lo stato del PC'),
      PcPhase.booting => (
          'AVVIO IN CORSO...',
          'Presa accesa • attendo il PC (${controller.bootElapsed?.inSeconds ?? 0}s)'
        ),
      PcPhase.off => ('PC SPENTO', 'Tocca il pulsante per accendere il PC'),
      PcPhase.online || PcPhase.shuttingDown => ('PC ACCESO', ''),
    };
  }
}

class _LastSignalChip extends StatelessWidget {
  const _LastSignalChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1015),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E232E), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_rounded, size: 13, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

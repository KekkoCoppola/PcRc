import 'package:flutter/material.dart';

import '../controllers/pc_controller.dart';
import 'sleek_outline_button.dart';

/// Card Alimentazione della dashboard: SPEGNI PC (shutdown + stacco presa) e AGGIORNA.
class PowerCard extends StatelessWidget {
  const PowerCard({
    super.key,
    required this.controller,
    required this.onShutdown,
    required this.onRefresh,
    required this.refreshing,
  });

  final PcController controller;
  final VoidCallback onShutdown;
  final VoidCallback onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final shuttingDown = controller.phase == PcPhase.shuttingDown;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1015),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: shuttingDown ? const Color(0xFFEF4444).withValues(alpha: 0.4) : const Color(0xFF1F232E),
          width: 1.1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    width: 1.1,
                  ),
                ),
                child: const Icon(Icons.power_settings_new_rounded, color: Color(0xFF00E5FF), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alimentazione PC',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      shuttingDown ? controller.shutdownStatus : 'Spegne Windows, poi stacca la presa',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: shuttingDown ? const Color(0xFFFCA5A5) : const Color(0xFF64748B),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SleekOutlineButton(
                  height: 46,
                  borderWidth: 1.3,
                  borderColor: const Color(0xFFEF4444),
                  textColor: const Color(0xFFEF4444),
                  label: 'SPEGNI PC',
                  icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                  isLoading: shuttingDown,
                  onPressed: shuttingDown ? null : onShutdown,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SleekOutlineButton(
                  height: 46,
                  borderWidth: 1.3,
                  borderColor: const Color(0xFF00E5FF),
                  textColor: const Color(0xFF00E5FF),
                  label: 'AGGIORNA',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  isLoading: refreshing,
                  onPressed: onRefresh,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

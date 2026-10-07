import 'package:flutter/material.dart';

import 'folder_shape.dart';

/// Modale a cartella nello stile delle card dei processi. Ritorna true se confermato.
Future<bool> showFolderDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? body,
  IconData icon = Icons.power_settings_new_rounded,
}) async {
  final confirmed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Chiudi',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => FolderDialog(
      title: title,
      body: body,
      icon: icon,
      confirmLabel: confirmLabel,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
      );
    },
  );
  return confirmed ?? false;
}

class FolderDialog extends StatelessWidget {
  const FolderDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.icon,
    this.body,
  });

  final String title;
  final String? body;
  final IconData icon;
  final String confirmLabel;

  static const double _tabWidth = 76;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            type: MaterialType.transparency,
            child: CustomPaint(
              painter: FolderPainter(glow: 1, borderAlpha: 0.92, tabWidth: _tabWidth),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: _tabWidth,
                    height: FolderPainter.tabHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 22),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(icon, size: 17, color: Colors.white),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, FolderPainter.tabHeight + 22, 22, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (body != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            body!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _MonoButton(
                                label: 'ANNULLA',
                                filled: false,
                                onTap: () => Navigator.of(context).pop(false),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MonoButton(
                                label: confirmLabel,
                                filled: true,
                                onTap: () => Navigator.of(context).pop(true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulsante a pillola bianco e nero: pieno (bianco, testo nero) o solo bordato.
class _MonoButton extends StatelessWidget {
  const _MonoButton({required this.label, required this.filled, required this.onTap});

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: Colors.white.withValues(alpha: filled ? 1 : 0.55), width: 1.4),
            boxShadow: filled
                ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 14)]
                : const [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? const Color(0xFF08090C) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

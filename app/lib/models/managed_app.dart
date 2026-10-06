import 'dart:ui';

/// Applicazione del PC che l'app può avviare e chiudere.
/// [key] è il nodo Firebase `apps/<key>`, lo stesso di APPS_CONFIG in agent/agent.pyw.
class ManagedApp {
  const ManagedApp({
    required this.key,
    required this.displayName,
    required this.accent,
    required this.iconAsset,
  });

  final String key;
  final String displayName;
  final Color accent;
  final String iconAsset;
}

const managedApps = [
  ManagedApp(
    key: 'claude',
    displayName: 'Claude',
    accent: Color(0xFFD27354),
    iconAsset: 'assets/icons/claude.png',
  ),
  ManagedApp(
    key: 'antigravity',
    displayName: 'Antigravity 2.0',
    accent: Color(0xFFA855F7),
    iconAsset: 'assets/icons/antigravity.png',
  ),
];

ManagedApp managedApp(String key) => managedApps.firstWhere((app) => app.key == key);

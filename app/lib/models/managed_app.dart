import 'dart:ui';

/// Applicazione del PC che l'app può avviare e chiudere.
/// [key] è il nodo Firebase `apps/<key>`, lo stesso di APPS_CONFIG in agent/agent.pyw.
class ManagedApp {
  const ManagedApp({
    required this.key,
    required this.displayName,
    required this.subtitle,
    required this.accent,
    required this.iconAsset,
  });

  final String key;
  final String displayName;
  final String subtitle;
  final Color accent;
  final String iconAsset;
}

const managedApps = [
  ManagedApp(
    key: 'claude',
    displayName: 'Claude',
    subtitle: 'Claude AI Desktop & Sessioni Code',
    accent: Color(0xFFD27354),
    iconAsset: 'assets/icons/claude.png',
  ),
  ManagedApp(
    key: 'antigravity',
    displayName: 'Antigravity 2.0',
    subtitle: 'Antigravity Coding Agent Daemon',
    accent: Color(0xFFA855F7),
    iconAsset: 'assets/icons/antigravity.png',
  ),
];

ManagedApp managedApp(String key) => managedApps.firstWhere((app) => app.key == key);

import 'app_info.dart';
import 'command_result.dart';
import 'managed_app.dart';
import 'pc_status.dart';

/// Lettura completa del Realtime Database:
/// `{apps: {<key>: {actual_state, command, result}}, pc: {command, result}, pc_status: {last_seen}}`.
class RemoteSnapshot {
  const RemoteSnapshot({required this.pcStatus, required this.apps, this.pcResult});

  final PcStatus pcStatus;
  final Map<String, AppInfo> apps;

  /// Esito dell'ultimo comando al PC (SHUTDOWN).
  final CommandResult? pcResult;

  factory RemoteSnapshot.fromJson(Object? json) {
    final root = json is Map ? json : const {};
    final apps = root['apps'] is Map ? root['apps'] as Map : const {};
    final pc = root['pc'] is Map ? root['pc'] as Map : const {};
    return RemoteSnapshot(
      pcStatus: PcStatus.fromJson(root['pc_status']),
      apps: {for (final app in managedApps) app.key: AppInfo.fromJson(app.key, apps[app.key])},
      pcResult: CommandResult.fromJson(pc['result']),
    );
  }
}

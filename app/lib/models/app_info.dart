import 'command_result.dart';

/// Stato di un'app sul PC come lo pubblica l'agent in `apps/<key>`.
class AppInfo {
  const AppInfo({required this.key, this.actualState = 'STOPPED', this.result});

  final String key;
  final String actualState;

  /// Esito dell'ultimo comando eseguito dall'agent per questa app.
  final CommandResult? result;

  bool get isRunning => actualState.toUpperCase() == 'RUNNING';

  factory AppInfo.fromJson(String key, Object? json) {
    if (json is! Map) return AppInfo(key: key);
    return AppInfo(
      key: key,
      actualState: (json['actual_state'] ?? 'STOPPED').toString().toUpperCase(),
      result: CommandResult.fromJson(json['result']),
    );
  }
}

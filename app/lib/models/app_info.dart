import 'command_result.dart';

/// Stato di un'app sul PC come lo pubblica l'agent in `apps/<key>`.
class AppInfo {
  const AppInfo({required this.key, this.actualState = 'STOPPED', this.since, this.result});

  final String key;
  final String actualState;

  /// Secondi epoch dell'ultimo cambio di stato (aperta/chiusa), null se l'agent non lo ha pubblicato.
  final int? since;

  /// Esito dell'ultimo comando eseguito dall'agent per questa app.
  final CommandResult? result;

  bool get isRunning => actualState.toUpperCase() == 'RUNNING';

  /// Da quanto l'app è nello stato attuale.
  Duration? elapsedAt(DateTime now) {
    if (since == null) return null;
    final seconds = now.millisecondsSinceEpoch ~/ 1000 - since!;
    return Duration(seconds: seconds < 0 ? 0 : seconds);
  }

  factory AppInfo.fromJson(String key, Object? json) {
    if (json is! Map) return AppInfo(key: key);
    final since = json['since'];
    return AppInfo(
      key: key,
      actualState: (json['actual_state'] ?? 'STOPPED').toString().toUpperCase(),
      since: since is num ? since.toInt() : null,
      result: CommandResult.fromJson(json['result']),
    );
  }
}

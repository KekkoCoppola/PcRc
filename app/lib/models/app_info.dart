import 'command_result.dart';

/// Cosa sta facendo l'agente AI dell'app (Claude Code, Antigravity), dagli hook sul PC.
enum AgentActivity {
  /// Nessuna sessione in corso.
  idle,
  working,

  /// Aspetta l'utente: un permesso, una risposta (per Antigravity è una stima).
  waiting,

  /// Turno finito, pronto per il prossimo messaggio.
  done;

  static AgentActivity fromJson(Object? json) => switch (json.toString().toUpperCase()) {
        'WORKING' => working,
        'WAITING' => waiting,
        'DONE' => done,
        _ => idle,
      };
}

/// Stato di un'app sul PC come lo pubblica l'agent in `apps/<key>`.
class AppInfo {
  const AppInfo({
    required this.key,
    this.actualState = 'STOPPED',
    this.since,
    this.result,
    this.activity = AgentActivity.idle,
    this.activitySince,
    this.activityProject,
  });

  final String key;
  final String actualState;

  /// Secondi epoch dell'ultimo cambio di stato (aperta/chiusa), null se l'agent non lo ha pubblicato.
  final int? since;

  /// Esito dell'ultimo comando eseguito dall'agent per questa app.
  final CommandResult? result;

  /// Stato riassuntivo delle sessioni dell'agente AI.
  final AgentActivity activity;

  /// Secondi epoch dall'ultimo cambio di [activity].
  final int? activitySince;

  /// Cartella del progetto della sessione che decide [activity] (es. "PcRc").
  final String? activityProject;

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
    final activitySince = json['activity_since'];
    final project = json['activity_project'];
    return AppInfo(
      key: key,
      actualState: (json['actual_state'] ?? 'STOPPED').toString().toUpperCase(),
      since: since is num ? since.toInt() : null,
      result: CommandResult.fromJson(json['result']),
      activity: AgentActivity.fromJson(json['activity']),
      activitySince: activitySince is num ? activitySince.toInt() : null,
      activityProject: project is String && project.isNotEmpty ? project : null,
    );
  }
}

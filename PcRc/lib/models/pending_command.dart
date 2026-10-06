import 'app_info.dart';

enum CommandOutcome { waiting, succeeded, failed, timedOut }

/// Comando inviato al PC di cui l'app aspetta l'esito.
class PendingCommand {
  /// Oltre questo tempo senza esito finale il PC viene considerato non raggiungibile.
  /// Supera il caso peggiore dell'agent: avvio app fino a 30 s più i giri di lettura.
  static const timeout = Duration(seconds: 60);

  final String id;
  final String action;
  final DateTime sentAt;

  PendingCommand({required this.id, required this.action, required this.sentAt});

  /// Stato del comando in base all'esito pubblicato dall'agent per [app].
  CommandOutcome outcome(AppInfo app, DateTime now) {
    if (app.resultId == id) {
      switch (app.resultStatus) {
        case 'OK':
          return CommandOutcome.succeeded;
        case 'ERRORE':
        case 'SCARTATO':
          return CommandOutcome.failed;
      }
    }
    return now.difference(sentAt) > timeout ? CommandOutcome.timedOut : CommandOutcome.waiting;
  }
}

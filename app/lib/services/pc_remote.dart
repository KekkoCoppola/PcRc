import '../models/remote_snapshot.dart';

/// Tutto quello che l'app chiede all'esterno: Firebase (agent sul PC) e Home Assistant (presa).
/// Implementata da RemoteControlService; nei test da un finto in memoria.
abstract interface class PcRemote {
  /// Stato completo letto da Firebase, null se non raggiungibile.
  Future<RemoteSnapshot?> fetchSnapshot();

  /// START/STOP per un'app: id del comando, null se la scrittura fallisce.
  Future<String?> sendAppCommand(String appKey, String action);

  /// SHUTDOWN per il PC: id del comando, null se la scrittura fallisce.
  Future<String?> sendPcCommand(String action);

  /// Presa del PC accesa? null se Home Assistant non risponde.
  Future<bool?> fetchPlugOn();

  /// Accende o spegne la presa: true se Home Assistant ha eseguito.
  Future<bool> setPlug(bool on);

  void dispose();
}

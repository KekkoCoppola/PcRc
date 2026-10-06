/// Indirizzi e token letti a compile time da `secrets.json` nella root del progetto:
/// `flutter build apk --dart-define-from-file=../secrets.json` (vedi scripts/build_apk.ps1).
class AppConfig {
  const AppConfig({
    required this.firebaseDbUrl,
    required this.haBaseUrl,
    required this.haToken,
    required this.haSwitchEntity,
  });

  static const fromEnvironment = AppConfig(
    firebaseDbUrl: String.fromEnvironment('FIREBASE_DB_URL'),
    haBaseUrl: String.fromEnvironment('HA_BASE_URL'),
    haToken: String.fromEnvironment('HA_TOKEN'),
    haSwitchEntity: String.fromEnvironment('HA_SWITCH_ENTITY'),
  );

  /// Realtime Database dove l'agent sul PC legge i comandi e pubblica lo stato.
  final String firebaseDbUrl;

  /// Home Assistant che comanda la presa smart del PC.
  final String haBaseUrl;
  final String haToken;
  final String haSwitchEntity;

  /// False se l'app è stata compilata senza secrets.json: niente può funzionare.
  bool get isComplete => [firebaseDbUrl, haBaseUrl, haToken, haSwitchEntity]
      .every((value) => value.isNotEmpty);
}

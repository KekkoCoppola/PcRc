import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'pc_remote.dart';

/// Notifiche push dell'agent sul PC (Claude o Antigravity che finiscono o aspettano):
/// chiede il permesso, registra il token FCM in `devices/<token>` e lo aggiorna quando cambia.
/// Le mostra Android stesso con l'app in background; con l'app aperta basta la card.
/// Solo Android: è l'unica piattaforma con google-services.json.
Future<void> startPushNotifications(PcRemote remote) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    messaging.onTokenRefresh.listen(remote.registerDevice);
    final token = await messaging.getToken();
    if (token != null) await remote.registerDevice(token);
  } catch (e) {
    debugPrint('Notifiche push non disponibili: $e');
  }
}

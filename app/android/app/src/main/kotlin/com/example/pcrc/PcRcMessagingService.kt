package com.example.pcrc

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Riceve i messaggi FCM anche ad app chiusa, senza avviare Flutter: gli stati degli agenti AI
 * diventano Live Update native. Estende il servizio del plugin (che il manifest sostituisce)
 * così il rinnovo del token continua ad arrivare a firebase_messaging.
 */
class PcRcMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        if (remoteMessage.data["type"] == "activity") {
            AgentLiveUpdates.handle(this, remoteMessage.data)
        } else {
            super.onMessageReceived(remoteMessage)
        }
    }
}

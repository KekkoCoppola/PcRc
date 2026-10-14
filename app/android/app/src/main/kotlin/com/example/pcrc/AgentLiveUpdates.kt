package com.example.pcrc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread
import kotlin.random.Random

/**
 * Live Update (notifica promossa di Android 16+) con lo stato dell'agente AI di un'app del PC:
 * nella barra di stato una pillola con il logo dell'app e un pallino colorato
 * (giallo al lavoro, blu aspetta te, verde ha finito). Una notifica per app.
 *
 * I dati arrivano dall'agent sul PC con FCM, vedi activity_message in agent/agent.pyw.
 */
object AgentLiveUpdates {
    /** Aggiornamenti senza suono: inizio lavoro, rinfreschi periodici. */
    private const val CHANNEL_STATUS = "agent_status"

    /** Aspetta te / ha finito: suona e compare in alto. */
    private const val CHANNEL_ALERT = "agent_alert"

    private const val EXTRA_TS = "pcrc_ts"
    private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    /** I PendingIntent dei tasti non devono sovrascriversi tra loro né quello di chiusura (stesso id). */
    private val COMMAND_REQUEST_OFFSETS = mapOf("STOP" to 10_000, "INTERRUPT" to 20_000)
    internal const val PREFS = "agent_live_updates"

    /** Il PC la rinfresca ogni 10 minuti: se smette (PC spento, rete persa) sparisce da sola. */
    private const val TIMEOUT_MS = 25 * 60 * 1000L

    /** Pallino della pillola: un'emoji, perché Android disegna l'icona sempre in un solo colore. */
    private class Look(val dot: String, val color: Int)

    private val looks = mapOf(
        "WORKING" to Look("🟡", 0xFFFACC15.toInt()), // 🟡
        "WAITING" to Look("🔵", 0xFF3B82F6.toInt()), // 🔵
        "DONE" to Look("🟢", 0xFF22C55E.toInt()), // 🟢
    )

    fun handle(context: Context, data: Map<String, String>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val app = data["app"] ?: return
        val state = data["state"] ?: return
        val ts = data["ts"]?.toLongOrNull() ?: 0L
        val manager = context.getSystemService(NotificationManager::class.java)
        val id = notificationId(app)

        // Messaggio partito prima di quello già mostrato: arrivato in ritardo
        val shown = manager.activeNotifications.firstOrNull { it.id == id }
        if (shown != null && shown.notification.extras.getLong(EXTRA_TS) > ts) return

        val look = looks[state]
        if (look == null) { // IDLE: nessuna sessione, app chiusa
            manager.cancel(id)
            return
        }

        val since = data["since"]?.toLongOrNull()
        val alert = data["alert"] == "1"
        val key = "$state:$since"
        // Chiusa dall'utente: i rinfreschi dello stesso stato non la ripropongono
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!alert && prefs.getString(app, null) == key) return

        createChannels(manager)
        val name = data["name"] ?: app
        val project = data["project"].orEmpty()
        val guess = data["guess"] == "1"
        // Card aperta: pallino e stato nel titolo, progetto sotto, logo a colori a destra,
        // cronometro dall'inizio dello stato nell'intestazione (tranne a turno finito), accanto
        // a icona e nome di PcRc, che Android mette da sé e non si possono togliere
        val title = "${look.dot} " + when (state) {
            "WORKING" -> "$name sta lavorando"
            "WAITING" -> if (guess) "$name è fermo" else "$name aspetta te"
            else -> if (data["note"] == "interrupted") "$name interrotto" else "$name ha finito"
        }
        val where = if (project.isNotEmpty()) "Progetto $project" else ""
        val text = when {
            state == "WAITING" && guess && where.isNotEmpty() -> "Forse aspetta un'approvazione · $where"
            state == "WAITING" && guess -> "Forse aspetta un'approvazione"
            else -> where
        }

        val builder = Notification.Builder(context, if (alert) CHANNEL_ALERT else CHANNEL_STATUS)
            .setSmallIcon(icon(app))
            .setLargeIcon(logo(context, app))
            .setContentTitle(title)
            .setContentText(text)
            .setColor(look.color)
            .setOngoing(true)
            .setOnlyAlertOnce(!alert)
            // Il cronometro corre solo mentre lavora o aspetta: a turno finito non conta più niente
            .setShowWhen(state != "DONE")
            .setUsesChronometer(state != "DONE" && since != null)
            .setWhen(since?.times(1000) ?: System.currentTimeMillis())
            .setTimeoutAfter(TIMEOUT_MS)
            .setCategory(Notification.CATEGORY_STATUS)
            .setContentIntent(openApp(context, id))
            .setDeleteIntent(onDismiss(context, id, app, key))
            .addExtras(Bundle().apply { putLong(EXTRA_TS, ts) })
        when (state) {
            // Solo a turno finito: il riassunto è DONE quando nessuna sessione lavora o aspetta
            "DONE" -> builder.addAction(action(context, id, app, name, "STOP", "Chiudi $name"))
            // Ferma il turno al passo successivo, tramite gli hook (activity.py)
            "WORKING" -> builder.addAction(action(context, id, app, name, "INTERRUPT", "Interrompi"))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            // Live Update: pillola in barra di stato, card in cima alla tendina e sul blocco schermo.
            // Richiesta di promozione: nell'SDK 36.0 né il setter né la costante sono pubblici,
            // il valore è quello di Notification/NotificationCompat.EXTRA_REQUEST_PROMOTED_ONGOING
            builder.addExtras(Bundle().apply { putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true) })
            builder.setShortCriticalText(look.dot)
        }
        manager.notify(id, builder.build())
        if (alert) prefs.edit().remove(app).apply()
    }

    private fun notificationId(app: String) = when (app) {
        "claude" -> 1001
        "antigravity" -> 1002
        else -> 1100 + Math.floorMod(app.hashCode(), 800)
    }

    private fun icon(app: String) = when (app) {
        "antigravity" -> R.drawable.ic_stat_antigravity
        else -> R.drawable.ic_stat_claude
    }

    /** Logo a colori dell'app del PC, lo stesso delle card di Flutter (assets/icons/<app>.png). */
    private fun logo(context: Context, app: String): Icon? = try {
        context.assets.open("flutter_assets/assets/icons/$app.png").use { stream ->
            BitmapFactory.decodeStream(stream)?.let { Icon.createWithBitmap(it) }
        }
    } catch (e: IOException) {
        null // app sconosciuta: solo l'icona piccola
    }

    private fun createChannels(manager: NotificationManager) {
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_STATUS, "Agenti AI · stato", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Cosa stanno facendo Claude e Antigravity, senza suoni"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ALERT, "Agenti AI · avvisi", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Claude o Antigravity aspettano te o hanno finito"
            },
        )
    }

    private fun openApp(context: Context, requestCode: Int): PendingIntent? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        return PendingIntent.getActivity(
            context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** Tasto che manda un comando dell'app all'agent sul PC (STOP, INTERRUPT). */
    private fun action(
        context: Context, id: Int, app: String, name: String, command: String, label: String,
    ): Notification.Action {
        val intent = Intent(context, AgentCommandReceiver::class.java)
            .putExtra("app", app)
            .putExtra("name", name)
            .putExtra("action", command)
        val pending = PendingIntent.getBroadcast(
            context, id + (COMMAND_REQUEST_OFFSETS[command] ?: 0), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_close_clear_cancel), label, pending,
        ).build()
    }

    private fun onDismiss(context: Context, requestCode: Int, app: String, key: String): PendingIntent {
        val intent = Intent(context, LiveUpdateDismissedReceiver::class.java)
            .putExtra("app", app)
            .putExtra("key", key)
        return PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}

/**
 * Tasti della Live Update: scrivono il comando in apps/<app>/command come fa l'app Flutter
 * (RemoteControlService._sendCommand).
 *   STOP      "Chiudi <app>": l'agent chiude l'app, lo stato diventa IDLE e la notifica sparisce.
 *   INTERRUPT "Interrompi": gli hook fermano il turno al passo successivo, arriva il 🟢 "interrotto".
 */
class AgentCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = intent.getStringExtra("app") ?: return
        val action = intent.getStringExtra("action") ?: return
        val name = intent.getStringExtra("name") ?: app
        val pending = goAsync()
        thread {
            val sent = try {
                sendCommand(context.getString(R.string.firebase_database_url).trimEnd('/'), app, action)
            } catch (e: Exception) {
                false
            }
            Handler(Looper.getMainLooper()).post {
                val done = if (action == "INTERRUPT") "interruzione richiesta" else "chiusura richiesta"
                val text = if (sent) "$name: $done" else "$name: comando non inviato, controlla la rete"
                Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
                pending.finish()
            }
        }
    }

    private fun sendCommand(dbUrl: String, app: String, action: String): Boolean {
        // Id nuovo a ogni tocco: l'agent esegue una volta sola ogni id
        val id = "${System.currentTimeMillis() * 1000}-${Random.nextInt(1 shl 30)}"
        val body = JSONObject()
            .put("id", id)
            .put("action", action)
            .put("ts", JSONObject().put(".sv", "timestamp")) // timestamp del server Firebase
            .toString()
        val connection = URL("$dbUrl/apps/$app/command.json").openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "PUT"
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(body.toByteArray()) }
            connection.responseCode in 200..299
        } finally {
            connection.disconnect()
        }
    }
}

/** L'utente ha chiuso la Live Update: si ricorda quale stato, per non riproporlo ai rinfreschi. */
class LiveUpdateDismissedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = intent.getStringExtra("app") ?: return
        context.getSharedPreferences(AgentLiveUpdates.PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(app, intent.getStringExtra("key"))
            .apply()
    }
}

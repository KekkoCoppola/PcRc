# PcRc

Controllo remoto del PC dal telefono: accensione tramite la presa smart di Home Assistant, avvio e chiusura di Claude e Antigravity, spegnimento sicuro.

## Come funziona

```
 App Flutter (telefono)
   │                      │
   │ REST                 │ REST (token)
   ▼                      ▼
 Firebase Realtime DB   Home Assistant ── presa smart ── alimentazione PC
   ▲
   │ ogni 2 s: legge i comandi, scrive stato e heartbeat
 agent.pyw (sul PC, avviato all'accesso)
```

- **Accensione.** L'app accende la presa via Home Assistant e il PC parte al ritorno della corrente. L'app aspetta il primo heartbeat dell'agent, fino a 3 minuti. Se la presa era già accesa (dopo uno spegnimento da Windows), chiede conferma e poi la spegne e la riaccende.
- **App.** L'app scrive `apps/<app>/command`; l'agent esegue START o STOP e pubblica l'esito in `apps/<app>/result`.
- **Spegnimento.** L'app scrive `pc/command` con SHUTDOWN e l'agent esegue `shutdown /s /t 10`. Quando l'heartbeat sparisce l'app aspetta altri 60 s, poi stacca la presa.
- **Cosa fanno Claude e Antigravity.** Gli hook dei due programmi lanciano `agent/activity.py` a ogni evento, che scrive lo stato della sessione in `~/.pcrc/activity`. Non in AppData: Claude desktop è un'app MSIX e Windows dirotta in una cartella del pacchetto le scritture in AppData dei processi che lancia, che l'agent non vedrebbe. L'agent pubblica un solo stato per app (WAITING prevale su WORKING, che prevale su DONE) e lo manda ai telefoni registrati con un messaggio FCM di soli dati, a ogni cambio e ogni 10 minuti.
  - Sul telefono `PcRcMessagingService` (Kotlin, funziona ad app chiusa) ne fa una Live Update per app (Android 16+): pillola in barra di stato con il logo e un pallino 🟡 al lavoro, 🔵 aspetta te, 🟢 ha finito. Suona solo per "aspetta te" e "ha finito"; senza rinfreschi sparisce dopo 25 minuti.
  - Claude Code: l'attesa è certa (permesso, domanda, piano da approvare).
  - Antigravity non ha un hook per l'approvazione: una sessione al lavoro senza eventi da 30 s viene segnalata come "probabilmente in attesa".
  - Una sessione al lavoro senza eventi da 15 minuti non conta più (Esc in Claude Code interrompe senza avvisare).

### Nodi Firebase

| Nodo | Chi scrive | Contenuto |
|---|---|---|
| `pc_status` | agent | `online`, `last_seen` (secondi epoch) |
| `apps/<app>/command` | app | `{id, action: START\|STOP\|INTERRUPT, ts}`; INTERRUPT (tasto della Live Update) ferma il turno dell'agente AI al passo successivo tramite gli hook |
| `apps/<app>/result` | agent | `{id, action, status: IN_CORSO\|OK\|ERRORE\|SCARTATO, message, ts}` |
| `apps/<app>/actual_state` | agent | `RUNNING` / `STOPPED` |
| `pc/command`, `pc/result` | app / agent | come sopra, con `action: SHUTDOWN` |
| `apps/<app>/activity` | agent | `WORKING` / `WAITING` / `DONE` / `IDLE`, con `activity_since` e `activity_project` |
| `devices/<token>` | app | `{token, platform, ts}`: telefoni che ricevono le notifiche (l'agent toglie i token scaduti) |

L'agent scarta i comandi più vecchi di 120 s: un comando rimasto in sospeso a PC spento non viene eseguito al boot successivo.

## Struttura

```
app/        App Flutter (Android, iOS, web, desktop)
agent/      agent.pyw, test, requirements.txt, firebase_key.json (non nel repo)
scripts/    build_apk.ps1, install_agent.ps1, presa.ps1, accendiPC.bat, spegniPC.bat
tools/      sorgenti grafici (logo in tools/logo, foto del case, icone), script per gli asset e Sysinternals Autologon
dist/       APK pronti da installare (non nel repo)
secrets.json  indirizzi e token (non nel repo, modello: secrets.example.json)
```

## Setup

1. Copia `secrets.example.json` in `secrets.json` e inserisci il token a lunga durata di Home Assistant.
2. Metti la chiave dell'account di servizio Firebase in `agent/firebase_key.json`.
3. Per le notifiche push registra l'app Android su Firebase e genera `app/android/app/google-services.json` (non nel repo):

   ```bash
   python tools/firebase_android_app.py
   ```

4. Sul PC installa l'agent. Lo script installa le dipendenze, registra gli hook di Claude Code (`~/.claude/settings.json`) e Antigravity (`~/.gemini/config/hooks.json`, voce `pcrc-activity`), crea il collegamento "PcRc agent" in Esecuzione automatica e lo avvia:

   ```bash
   powershell -ExecutionPolicy Bypass -File scripts/install_agent.ps1
   ```

   Va rilanciato se sposti o rinomini la cartella del progetto. Il log è in `agent/agent.log`.

Perché l'agent parta anche dopo un'accensione da remoto serve l'accesso automatico a Windows (`tools/autologon`, Sysinternals Autologon).

## Build dell'APK

```bash
powershell -ExecutionPolicy Bypass -File scripts/build_apk.ps1
```

L'APK per i telefoni a 64 bit finisce in `dist/PcRc-<versione>-arm64-v8a.apk`. Una build fatta senza `--dart-define-from-file=../secrets.json` mostra "CONFIGURAZIONE MANCANTE" e non comanda niente.

## Test

```bash
cd agent && python -m unittest discover -s tests -v
```

```bash
cd app && flutter analyze && flutter test
```

I test non spengono mai il PC e non toccano la presa: SHUTDOWN e Home Assistant sono simulati.

## Sicurezza: limiti noti

- Il Realtime Database non ha autenticazione: chi conosce l'URL può leggere lo stato e mandare comandi, e anche registrare un suo telefono in `devices` per ricevere le notifiche (che contengono il nome del progetto).
- Il token di Home Assistant è compilato dentro l'APK: chi ha l'APK può estrarlo. Non condividere l'APK.
- `secrets.json` e `firebase_key.json` sono esclusi dal repo tramite `.gitignore`.

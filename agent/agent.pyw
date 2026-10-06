import ctypes
import logging
import logging.handlers
import os
import queue
import subprocess
import threading
import time
import warnings
import psutil
import firebase_admin
from firebase_admin import credentials, db

# ================= CONFIGURAZIONE =================
# Percorso del file JSON scaricato da Firebase
CRED_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "firebase_key.json")

# Inserisci l'URL del tuo Realtime Database copiato allo Step 2
DATABASE_URL = "https://rcpc-3ed45-default-rtdb.europe-west1.firebasedatabase.app/"

# Configurazione delle due applicazioni
#   process_names:         STOP chiude tutti i processi con questi nomi
#   running_path_contains: RUNNING solo se l'exe sta in un percorso che contiene
#                          questo testo (None = basta il nome)
#   launch:                comando di avvio
APPS_CONFIG = {
    "claude": {
        # claude.exe = app desktop + sessioni Claude Code: STOP le chiude entrambe
        "process_names": ["claude.exe"],
        # RUNNING solo per l'app desktop (pacchetto MSIX), non per Claude Code
        "running_path_contains": r"\WindowsApps\Claude_",
        # Avvio tramite AppID del pacchetto: non dipende dalla versione installata
        "launch": ["explorer.exe", r"shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"],
    },
    "antigravity": {
        "process_names": ["Antigravity.exe"],
        "running_path_contains": None,
        "launch": [r"C:\Users\franc\AppData\Local\Programs\antigravity\Antigravity.exe"],
    },
}

# Ogni quanti secondi leggere i comandi e inviare l'heartbeat
LOOP_INTERVAL_S = 2
# Comandi più vecchi di così vengono scartati (es. inviati mentre il PC era spento)
COMMAND_TTL_S = 120
# Secondi di attesa per la chiusura gentile prima di forzare
CLOSE_TIMEOUT_S = 15
# Secondi entro cui un'app avviata deve comparire tra i processi
START_TIMEOUT_S = 30
# Secondi tra il comando SHUTDOWN e lo spegnimento di Windows: bastano all'agent
# per pubblicare l'esito prima di essere chiuso
SHUTDOWN_DELAY_S = 10
# Azioni ammesse per le app (apps/<app>/command) e per il PC (pc/command)
APP_ACTIONS = ("START", "STOP")
PC_ACTIONS = ("SHUTDOWN",)
# Nome del mutex che impedisce di avere due agent attivi insieme
MUTEX_NAME = r"Local\PcRc_agent"
# File di log (pythonw non mostra errori a schermo)
LOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "agent.log")
# ==================================================

log = logging.getLogger("pcrc")
log.addHandler(logging.NullHandler())

_kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
_kernel32.CreateMutexW.argtypes = [ctypes.c_void_p, ctypes.c_bool, ctypes.c_wchar_p]
_kernel32.CreateMutexW.restype = ctypes.c_void_p
_kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
ERROR_ALREADY_EXISTS = 183

def acquire_single_instance(name=MUTEX_NAME):
    """Mutex di sistema con nome: None se un altro agent lo possiede già"""
    ctypes.set_last_error(0)
    handle = _kernel32.CreateMutexW(None, False, name)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    if ctypes.get_last_error() == ERROR_ALREADY_EXISTS:
        _kernel32.CloseHandle(handle)
        return None
    return handle

def release_single_instance(handle):
    if handle:
        _kernel32.CloseHandle(handle)

def new_command(node, now_ms, ttl_s, actions=APP_ACTIONS):
    """Comando del nodo (app o PC) non ancora gestito, oppure None.

    Il comando è "gestito" quando result.id coincide con command.id.
    Ritorna {"id", "action", "error"}: error è None se va eseguito,
    altrimenti il motivo per cui viene scartato.
    """
    if not isinstance(node, dict):
        return None
    cmd = node.get("command")
    if not isinstance(cmd, dict) or not cmd.get("id"):
        return None
    result = node.get("result")
    if isinstance(result, dict) and result.get("id") == cmd["id"]:
        return None

    action = cmd.get("action")
    ts = cmd.get("ts")
    error = None
    if action not in actions:
        error = f"azione non valida: {action}"
    elif not isinstance(ts, (int, float)):
        error = "comando senza timestamp"
    elif now_ms - ts > ttl_s * 1000:
        error = "comando scaduto"
    return {"id": cmd["id"], "action": action, "error": error}

def find_processes(names, path_contains=None):
    """Processi attivi con nome in names (e percorso exe contenente path_contains).

    Confronti senza distinzione tra maiuscole e minuscole.
    """
    wanted = {name.lower() for name in names}
    needle = path_contains.lower() if path_contains else None
    found = []
    for proc in psutil.process_iter(['name', 'exe']):
        if (proc.info['name'] or "").lower() not in wanted:
            continue
        if needle and needle not in (proc.info['exe'] or "").lower():
            continue
        found.append(proc)
    return found

def is_running(cfg):
    """Controlla se l'applicazione configurata è attiva"""
    return bool(find_processes(cfg["process_names"], cfg["running_path_contains"]))

def launch_detached(args):
    """Avvia un programma senza attenderne la fine.

    Su Windows non esistono processi zombie: l'handle si chiude quando l'oggetto
    Popen viene distrutto, quindi il ResourceWarning "still running" è solo rumore.
    """
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", ResourceWarning)
        subprocess.Popen(args, creationflags=subprocess.CREATE_NO_WINDOW)

def start_app(cfg, timeout_s=START_TIMEOUT_S):
    """Avvia l'app se non è già attiva e aspetta che il suo processo compaia.

    Ritorna (status, messaggio).
    """
    if is_running(cfg):
        return "OK", "era già in esecuzione"
    try:
        launch_detached(cfg["launch"])
    except OSError as e:
        return "ERRORE", f"avvio fallito: {e}"

    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if is_running(cfg):
            return "OK", "avviato"
        time.sleep(0.5)
    return "ERRORE", f"non risulta avviato dopo {timeout_s}s"

def stop_processes(procs, timeout_s=CLOSE_TIMEOUT_S):
    """Chiusura gentile (WM_CLOSE alle finestre), forzata se dopo timeout_s è ancora vivo.

    Ritorna (status, messaggio).
    """
    if not procs:
        return "OK", "era già chiuso"
    # taskkill senza /F chiede la chiusura delle finestre, come premere la X
    pid_args = [arg for proc in procs for arg in ("/PID", str(proc.pid))]
    subprocess.run(["taskkill", *pid_args], capture_output=True,
                   creationflags=subprocess.CREATE_NO_WINDOW)
    _, alive = psutil.wait_procs(procs, timeout=timeout_s)
    if not alive:
        return "OK", "chiuso"

    for proc in alive:
        try:
            proc.kill()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    _, alive = psutil.wait_procs(alive, timeout=5)
    if alive:
        return "ERRORE", f"{len(alive)} processi non si chiudono"
    return "OK", f"chiuso forzatamente dopo {timeout_s}s"

def execute_command(action, cfg):
    """Esegue START o STOP sull'app configurata. Ritorna (status, messaggio)."""
    if action == "START":
        return start_app(cfg, START_TIMEOUT_S)
    if action == "STOP":
        # Tutti i processi con quei nomi, anche fuori dal percorso usato per RUNNING
        return stop_processes(find_processes(cfg["process_names"]), CLOSE_TIMEOUT_S)
    raise ValueError(f"azione sconosciuta: {action}")

def shutdown_pc(delay_s=SHUTDOWN_DELAY_S):
    """Programma lo spegnimento di Windows tra delay_s secondi. Ritorna (status, messaggio)."""
    proc = subprocess.run(
        ["shutdown", "/s", "/t", str(delay_s), "/c", "PcRc: spegnimento remoto"],
        capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip() or f"codice {proc.returncode}"
        return "ERRORE", f"shutdown rifiutato: {detail}"
    return "OK", f"spegnimento tra {delay_s}s"

def command_result(cmd, status, message):
    """Esito da pubblicare in <nodo>/result (ts assegnato dal server Firebase)"""
    return {"id": cmd["id"], "action": cmd["action"], "status": status,
            "message": message, "ts": {".sv": "timestamp"}}

class Agent:
    """Un giro ogni LOOP_INTERVAL_S: legge i comandi, li esegue in background e
    pubblica esiti, stato delle app e heartbeat con una sola scrittura.

    I comandi arrivano in apps/<app>/command (START/STOP) e in pc/command
    (SHUTDOWN); l'esito va nel result accanto, con lo stesso id."""

    def __init__(self, apps, read_root, write, execute, shutdown=shutdown_pc,
                 is_running=is_running, now=time.time):
        self.apps = apps
        self.read_root = read_root      # () -> contenuto della radice del database
        self.write = write              # {percorso: valore} -> update multi-percorso
        self.execute = execute          # (azione, cfg) -> (status, messaggio)
        self.shutdown = shutdown        # () -> (status, messaggio)
        self.is_running = is_running
        self.now = now
        self.pending = {}               # scritture non ancora riuscite
        self.dispatched = {}            # nodo -> id dell'ultimo comando preso in carico
        self.jobs = {}                  # nodo -> thread del comando in esecuzione
        self.finished = queue.Queue()   # (nodo, esito) prodotti dai thread
        self.online = None              # esito dell'ultimo giro, per loggare solo i cambi

    def tick(self):
        """Un giro di lavoro. Non solleva mai: se Firebase non risponde riprova al giro dopo."""
        try:
            root = self.read_root()
            root = root if isinstance(root, dict) else {}
            apps_node = root.get("apps")
            apps_node = apps_node if isinstance(apps_node, dict) else {}
            while not self.finished.empty():
                path, result = self.finished.get_nowait()
                self.pending[f"{path}/result"] = result
            for key, cfg in self.apps.items():
                self._dispatch(f"apps/{key}", apps_node.get(key), APP_ACTIONS,
                               lambda action, cfg=cfg: self.execute(action, cfg))
                running = self.is_running(cfg)
                self.pending[f"apps/{key}/actual_state"] = "RUNNING" if running else "STOPPED"
            self._dispatch("pc", root.get("pc"), PC_ACTIONS, lambda action: self.shutdown())
            self.pending["pc_status/online"] = True
            self.pending["pc_status/last_seen"] = int(self.now())
            self.write(dict(self.pending))
            self.pending.clear()
        except Exception:
            if self.online is not False:
                log.exception("Firebase non raggiungibile, riprovo")
            self.online = False
        else:
            if self.online is False:
                log.info("Connessione a Firebase ripristinata")
            self.online = True

    def _dispatch(self, path, node, actions, run):
        """Prende in carico il comando nuovo del nodo `path`; run(azione) lo esegue."""
        cmd = new_command(node, self.now() * 1000, COMMAND_TTL_S, actions)
        if cmd is None or self.dispatched.get(path) == cmd["id"]:
            return
        job = self.jobs.get(path)
        if job is not None and job.is_alive():
            return  # resta in attesa: parte quando finisce il comando in corso
        self.dispatched[path] = cmd["id"]
        if cmd["error"]:
            log.info("%s: comando %s scartato (%s)", path, cmd["id"], cmd["error"])
            self.pending[f"{path}/result"] = command_result(cmd, "SCARTATO", cmd["error"])
            return
        log.info("%s: eseguo %s (comando %s)", path, cmd["action"], cmd["id"])
        self.pending[f"{path}/result"] = command_result(cmd, "IN_CORSO", "")
        job = threading.Thread(target=self._run, args=(path, run, cmd), daemon=True)
        self.jobs[path] = job
        job.start()

    def _run(self, path, run, cmd):
        try:
            status, message = run(cmd["action"])
        except Exception as e:
            log.exception("%s: errore eseguendo %s", path, cmd["action"])
            status, message = "ERRORE", f"errore interno: {e}"
        log.info("%s: %s -> %s (%s)", path, cmd["action"], status, message)
        self.finished.put((path, command_result(cmd, status, message)))

def setup_logging():
    """pythonw non ha console: il log va in agent.log, accanto allo script"""
    handler = logging.handlers.RotatingFileHandler(
        LOG_PATH, maxBytes=1_000_000, backupCount=2, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(handler)
    log.setLevel(logging.INFO)

def main():
    setup_logging()
    mutex = acquire_single_instance()
    if mutex is None:
        log.info("Un altro agent è già attivo, esco (pid %s)", os.getpid())
        return
    log.info("Agent avviato (pid %s)", os.getpid())

    # Inizializzazione Firebase: non usa la rete, quindi non fallisce se al boot
    # la connessione non è ancora pronta (i giri dell'agent ritentano da soli)
    cred = credentials.Certificate(CRED_PATH)
    firebase_admin.initialize_app(cred, {
        'databaseURL': DATABASE_URL,
        'httpTimeout': 10,
    })

    # Loop principale: comandi, stato delle app e heartbeat ogni LOOP_INTERVAL_S.
    # Legge i comandi a ogni giro invece di usare listen(): il listener in streaming
    # può morire in silenzio (rete che cade, sospensione) lasciando il PC sordo.
    agent = Agent(
        apps=APPS_CONFIG,
        read_root=lambda: db.reference().get(),
        write=lambda updates: db.reference().update(updates),
        execute=execute_command,
    )
    while True:
        agent.tick()
        time.sleep(LOOP_INTERVAL_S)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log.exception("Agent terminato per errore")
        raise
"""Stato di lavoro di Claude Code e Antigravity, ricavato dai loro hook.

A ogni evento dell'agente AI i due programmi lanciano
    python activity.py <app> <evento>      (dati dell'evento in JSON su stdin)
e questo script scrive lo stato della sessione in ACTIVITY_DIR/<app>/<sessione>.json.
agent.pyw legge i file e pubblica un solo stato riassuntivo per app.

    python activity.py --install           registra gli hook (lo fa install_agent.ps1)

Importa solo la libreria standard: gli hook bloccano l'agente AI finché non escono.
"""
import json
import os
import re
import sys
import time
from pathlib import Path

WORKING, WAITING, DONE, IDLE = "WORKING", "WAITING", "DONE", "IDLE"
# Sessione chiusa (SessionEnd di Claude Code): il suo file viene cancellato
ENDED = "ENDED"
# Precedenza nel riassunto: basta una sessione che aspetta l'utente per segnalarlo
PRIORITY = {WAITING: 3, WORKING: 2, DONE: 1}

# Strumenti di Claude Code che fermano il turno finché l'utente non risponde
CLAUDE_ASKING_TOOLS = {"AskUserQuestion", "ExitPlanMode"}
# Notifiche di Claude Code che non chiedono niente all'utente
CLAUDE_QUIET_NOTIFICATIONS = {"idle_prompt", "auth_success"}

# Sessione al lavoro senza eventi da così tanto: turno interrotto (Esc in Claude Code
# non lancia Stop) o programma chiuso di colpo, non conta più
WORKING_EXPIRY_S = 15 * 60
# File di sessione più vecchi di così vengono cancellati
PRUNE_AFTER_S = 24 * 3600

# Tasto Interrompi del telefono: agent.pyw scrive il segnale, gli hook lo leggono
INTERRUPT_FILE = "interrupt.flag"
# Oltre questo tempo il segnale non vale più (una sessione ferma da tanto è già scaduta)
INTERRUPT_TTL_S = WORKING_EXPIRY_S
INTERRUPT_REASON = "Interrotto dal telefono (PcRc)"
# Eventi in cui l'hook può fermare l'agente AI: Claude Code a ogni tool,
# Antigravity solo dopo la chiamata al modello (terminationBehavior)
STOP_EVENTS = {"claude": {"PreToolUse", "PostToolUse"}, "antigravity": {"PostInvocation"}}

ANTIGRAVITY_HOOK_NAME = "pcrc-activity"
# Eventi di Claude Code registrati, con il matcher (None = evento senza matcher)
CLAUDE_EVENTS = {
    "UserPromptSubmit": None,
    "PreToolUse": "*",
    "PostToolUse": "*",
    "PermissionRequest": "*",
    "Notification": "permission_prompt|elicitation_dialog",
    "Stop": None,
    "SessionEnd": None,
}
# Eventi di Antigravity registrati. Niente PreToolUse: la sua risposta decide se il
# tool può partire, quindi un hook di sola lettura non deve rispondere lì.
ANTIGRAVITY_EVENTS = {
    "PreInvocation": None,
    "PostInvocation": None,
    "PostToolUse": "*",
    "Stop": None,
}
HOOK_TIMEOUT_S = 10


def activity_dir():
    """Cartella condivisa tra hook e agent (PCRC_ACTIVITY_DIR la sostituisce nei test).

    Fuori da AppData: Claude desktop è un'app MSIX e Windows dirotta in una cartella del
    pacchetto le scritture in AppData dei processi che lancia (gli hook), che l'agent,
    avviato fuori dal pacchetto, non vedrebbe. Come ~/.claude, ~/.pcrc non viene dirottata.
    """
    custom = os.environ.get("PCRC_ACTIVITY_DIR")
    if custom:
        return Path(custom)
    return Path.home() / ".pcrc" / "activity"


def state_for(app, event, payload):
    """Stato della sessione dopo l'evento; None se l'evento non lo cambia."""
    if app == "claude":
        if event in ("UserPromptSubmit", "PostToolUse"):
            return WORKING
        if event == "PreToolUse":
            return WAITING if payload.get("tool_name") in CLAUDE_ASKING_TOOLS else WORKING
        if event == "PermissionRequest":
            return WAITING
        if event == "Notification":
            return None if payload.get("notification_type") in CLAUDE_QUIET_NOTIFICATIONS else WAITING
        if event == "Stop":
            return DONE
        if event == "SessionEnd":
            return ENDED
    elif app == "antigravity":
        if event in ("PreInvocation", "PostInvocation", "PostToolUse"):
            return WORKING
        if event == "Stop":
            return DONE
    return None


def _session_of(app, payload):
    """(id della sessione, cartella del progetto) dai dati dell'evento."""
    if app == "claude":
        return payload.get("session_id"), payload.get("cwd")
    folders = payload.get("workspacePaths")
    folder = folders[0] if isinstance(folders, list) and folders else None
    return payload.get("conversationId"), folder


def _file_name(session):
    """Nome di file sicuro: l'id arriva da fuori e non deve uscire dalla cartella."""
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", str(session or ""))
    return f"{safe or 'default'}.json"


def _project_name(folder):
    """Nome del repository git che contiene la cartella, altrimenti della cartella stessa."""
    if not isinstance(folder, str) or not folder.strip():
        return None
    path = Path(folder.rstrip("\\/"))
    for candidate in (path, *path.parents):
        if (candidate / ".git").exists():
            return candidate.name or None
    return path.name or None


def _read_session(path):
    try:
        data = json.loads(path.read_text("utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _interrupt_requested(folder, turn, now):
    """Il telefono ha chiesto di interrompere dopo l'inizio di questo turno, e da poco."""
    signal = _read_session(folder / INTERRUPT_FILE)
    requested = signal.get("ts") if signal else None
    return (isinstance(requested, (int, float)) and isinstance(turn, (int, float))
            and requested >= turn and 0 <= now - requested <= INTERRUPT_TTL_S)


def record(app, event, payload, now=None, root=None):
    """Aggiorna il file della sessione in base all'evento.

    Ritorna True se l'hook deve fermare l'agente AI (tasto Interrompi del telefono):
    la sessione risulta già finita.
    """
    state = state_for(app, event, payload)
    if state is None:
        return False
    session, folder = _session_of(app, payload)
    path = (root or activity_dir()) / app / _file_name(session)
    if state == ENDED:
        path.unlink(missing_ok=True)
        return False
    now = int(time.time() if now is None else now)
    previous = _read_session(path)
    # Inizio del turno: il prompt (Claude Code) o il primo lavoro dopo la fine del precedente
    new_turn = (previous is None or event == "UserPromptSubmit"
                or (state == WORKING and previous.get("state") == DONE))
    turn = now if new_turn else previous.get("turn", now)
    stop = (event in STOP_EVENTS.get(app, ()) and state == WORKING
            and _interrupt_requested(path.parent, turn, now))
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {"state": DONE if stop else state, "ts": now, "project": _project_name(folder), "turn": turn}
    # File temporaneo per processo: due hook della stessa sessione possono girare insieme
    tmp = path.with_name(f"{path.stem}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    os.replace(tmp, path)
    return stop


def request_interrupt(app, now=None, root=None):
    """Segnale per gli hook: fermare i turni dell'app iniziati prima di adesso."""
    folder = (root or activity_dir()) / app
    folder.mkdir(parents=True, exist_ok=True)
    (folder / INTERRUPT_FILE).write_text(
        json.dumps({"ts": int(time.time() if now is None else now)}), encoding="utf-8")


def summarize(app, now, root=None, stall_s=None):
    """Stato riassuntivo delle sessioni dell'app: (stato, progetto della sessione che lo decide).

    Vince lo stato con più precedenza; a pari stato la sessione con l'evento più recente.
    stall_s: per le app senza un evento "approvazione richiesta" (Antigravity), una
    sessione al lavoro ferma da più di stall_s secondi conta come in attesa dell'utente.
    """
    best, best_key = (IDLE, None), None
    folder = (root or activity_dir()) / app
    for path in folder.glob("*.json"):
        try:
            data = json.loads(path.read_text("utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(data, dict):
            continue
        state, ts = data.get("state"), data.get("ts")
        if state not in PRIORITY or not isinstance(ts, (int, float)):
            continue
        age = now - ts
        if age > PRUNE_AFTER_S:
            path.unlink(missing_ok=True)
            continue
        if state == WORKING:
            if age > WORKING_EXPIRY_S:
                continue
            if stall_s is not None and age > stall_s:
                state = WAITING
        key = (PRIORITY[state], ts)
        if best_key is None or key > best_key:
            best, best_key = (state, data.get("project")), key
    return best


def hook_command(python_exe=None, script=None):
    """Comando che gli hook lanciano. Barre in avanti: vanno bene sia per cmd
    (Antigravity) sia per bash (Claude Code su Windows)."""
    parts = [str(python_exe or sys.executable), str(script or Path(__file__).resolve())]
    parts = [p.replace("\\", "/") for p in parts]
    return " ".join(f'"{p}"' if " " in p else p for p in parts)


def _read_json(path):
    try:
        data = json.loads(Path(path).read_text("utf-8"))
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"{path} non contiene un oggetto JSON")
    return data


def _write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup = path.with_name(path.name + ".pcrc.bak")
        backup.write_bytes(path.read_bytes())
    tmp = path.with_name(path.name + ".pcrc.tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def _is_ours(group, app):
    hooks = group.get("hooks") if isinstance(group, dict) else None
    return isinstance(hooks, list) and any(
        f"activity.py {app} " in str(h.get("command", "")) for h in hooks if isinstance(h, dict))


def install_hooks(command, claude_settings, antigravity_hooks):
    """Registra gli hook in Claude Code e Antigravity, lasciando intatti gli altri.

    Rilanciarlo sostituisce le voci precedenti di PcRc (anche con un percorso vecchio).
    """
    settings = _read_json(claude_settings)
    hooks = settings.setdefault("hooks", {})
    for event, matcher in CLAUDE_EVENTS.items():
        groups = [g for g in hooks.get(event, []) if not _is_ours(g, "claude")]
        group = {"hooks": [{"type": "command", "command": f"{command} claude {event}",
                            "timeout": HOOK_TIMEOUT_S}]}
        if matcher is not None:
            group = {"matcher": matcher, **group}
        hooks[event] = groups + [group]
    _write_json(claude_settings, settings)

    named = _read_json(antigravity_hooks)
    ours = {}
    for event, matcher in ANTIGRAVITY_EVENTS.items():
        handler = {"type": "command", "command": f"{command} antigravity {event}",
                   "timeout": HOOK_TIMEOUT_S}
        ours[event] = [{"matcher": matcher, "hooks": [handler]}] if matcher else [handler]
    named[ANTIGRAVITY_HOOK_NAME] = ours
    _write_json(antigravity_hooks, named)


def main(argv=None, stdin=None, stdout=None, root=None, now=None):
    """Punto d'ingresso degli hook. Esce sempre con 0: un hook fallito potrebbe
    bloccare Claude o Antigravity, mentre uno stato perso costa poco."""
    argv = sys.argv[1:] if argv is None else argv
    stdout = stdout or sys.stdout
    if argv[:1] == ["--install"]:
        home = Path.home()
        install_hooks(hook_command(), home / ".claude" / "settings.json",
                      home / ".gemini" / "config" / "hooks.json")
        print("Hook di attività registrati per Claude Code e Antigravity", file=stdout)
        return 0
    app = argv[0] if argv else ""
    stop = False
    try:
        raw = (stdin or sys.stdin).read()
        payload = json.loads(raw) if raw.strip() else {}
        if isinstance(payload, dict) and len(argv) >= 2:
            stop = record(app, argv[1], payload, now=now, root=root)
    except Exception:
        pass
    if app == "antigravity":
        # Antigravity vuole sempre un oggetto JSON; {} lascia tutto com'è
        stdout.write(json.dumps({"terminationBehavior": "terminate"} if stop else {}))
    elif stop:
        # Claude Code: continue false chiude il turno dopo questo hook
        stdout.write(json.dumps({"continue": False, "stopReason": INTERRUPT_REASON}))
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Test dell'agent PC (python -m unittest discover -s tests -v, dalla cartella agent/)."""
import copy
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

import psutil

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agent  # noqa: E402  (agent.pyw: su Windows .pyw è importabile)

NOW_MS = 1_790_000_000_000
TTL_S = 120

# Finestra vera: si chiude da sola quando riceve WM_CLOSE (come premere la X).
TK_WINDOW = (
    "import tkinter as tk\n"
    "root = tk.Tk(); root.title('PcRc test'); root.update()\n"
    "print('ready', flush=True)\n"
    "root.mainloop()\n"
)
NO_WINDOW = "import time; print('ready', flush=True); time.sleep(60)"


def spawn_python(test, code):
    """Avvia `python -c code`, aspetta che stampi 'ready' e lo uccide a fine test."""
    popen = subprocess.Popen(
        [sys.executable, "-c", code], stdout=subprocess.PIPE, text=True,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    test.addCleanup(kill_quietly, popen)
    test.assertEqual(popen.stdout.readline().strip(), "ready")
    return popen


def kill_quietly(popen):
    if popen.poll() is None:
        popen.kill()
    popen.wait(timeout=5)
    if popen.stdout:
        popen.stdout.close()


def kill_by_name(name):
    for proc in psutil.process_iter(['name']):
        if (proc.info['name'] or "").lower() == name.lower():
            try:
                proc.kill()
            except psutil.NoSuchProcess:
                pass


def temp_dir(test):
    path = Path(tempfile.mkdtemp(prefix="pcrc_test_"))
    test.addCleanup(shutil.rmtree, path, ignore_errors=True)
    return path


def dummy_exe(test, name):
    """Copia di ping.exe con nome unico: processo vero, riconoscibile dal nome."""
    path = temp_dir(test) / name
    shutil.copy(Path(os.environ["SystemRoot"]) / "System32" / "PING.EXE", path)
    test.addCleanup(kill_by_name, name)
    return path


DUMMY_ARGS = ["-n", "30", "127.0.0.1"]


def app_cfg(launch, name):
    return {"process_names": [name], "running_path_contains": None, "launch": launch}


class FakeDb:
    """Radice del Realtime Database in memoria: legge tutto, applica update multi-percorso."""

    def __init__(self, apps, pc=None):
        self.root = {"apps": apps}
        if pc is not None:
            self.root["pc"] = pc
        self.fail_reads = 0
        self.fail_writes = 0

    def read_root(self):
        if self.fail_reads:
            self.fail_reads -= 1
            raise ConnectionError("rete assente")
        return copy.deepcopy(self.root)

    def write(self, updates):
        if self.fail_writes:
            self.fail_writes -= 1
            raise ConnectionError("rete assente")
        for path, value in updates.items():
            node = self.root
            *parents, leaf = path.split("/")
            for part in parents:
                node = node.setdefault(part, {})
            node[leaf] = value

    def get(self, path):
        node = self.root
        for part in path.split("/"):
            node = node.get(part) if isinstance(node, dict) else None
        return node


class FakeExecutor:
    """Registra i comandi eseguiti; con release.clear() il comando resta "in corso"."""

    def __init__(self, result=("OK", "fatto")):
        self.calls = []
        self.result = result
        self.release = threading.Event()
        self.release.set()

    def __call__(self, action, cfg):
        self.calls.append((action, cfg["name"]))
        self.release.wait(5)
        return self.result


class FakeShutdown:
    """Al posto di shutdown_pc: nei test il PC non si spegne mai davvero."""

    def __init__(self, result=("OK", "spegnimento tra 10s")):
        self.calls = 0
        self.result = result

    def __call__(self):
        self.calls += 1
        return self.result


FAKE_APPS = {"claude": {"name": "claude"}, "antigravity": {"name": "antigravity"}}


FIRST_SINCE = 1_789_990_000  # inizio dello stato visto alla prima occhiata (finto)


def make_agent(db, execute, running=(), shutdown=None, now=lambda: NOW_MS / 1000):
    return agent.Agent(
        apps=FAKE_APPS, read_root=db.read_root, write=db.write, execute=execute,
        shutdown=shutdown or FakeShutdown(),
        is_running=lambda cfg: cfg["name"] in running,
        first_since=lambda cfg, running: FIRST_SINCE, now=now,
    )


def command(cmd_id, action, age_s=0):
    return {"id": cmd_id, "action": action, "ts": NOW_MS - age_s * 1000}


def tick_until_result(test, a, db, node, predicate, timeout_s=5):
    """Esegue giri dell'agent finché l'esito pubblicato in `node` soddisfa predicate."""
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        a.tick()
        result = db.get(f"{node}/result")
        if result and predicate(result):
            return result
        time.sleep(0.02)
    test.fail(f"esito atteso mai pubblicato, ultimo: {db.get(f'{node}/result')}")


def is_final(result):
    return result["status"] != "IN_CORSO"


class NewCommandTest(unittest.TestCase):
    def test_node_without_command_has_nothing_to_do(self):
        self.assertIsNone(agent.new_command({"actual_state": "RUNNING"}, NOW_MS, TTL_S))

    def test_fresh_command_not_yet_answered_is_executable(self):
        node = {
            "command": {"id": "c1", "action": "START", "ts": NOW_MS - 5_000},
            "result": {"id": "c0", "status": "OK"},
        }
        self.assertEqual(
            agent.new_command(node, NOW_MS, TTL_S),
            {"id": "c1", "action": "START", "error": None},
        )

    def test_command_already_answered_is_ignored(self):
        node = {
            "command": {"id": "c1", "action": "STOP", "ts": NOW_MS},
            "result": {"id": "c1", "status": "OK"},
        }
        self.assertIsNone(agent.new_command(node, NOW_MS, TTL_S))

    def test_command_older_than_ttl_is_rejected(self):
        node = {"command": {"id": "c1", "action": "STOP", "ts": NOW_MS - (TTL_S + 1) * 1000}}
        cmd = agent.new_command(node, NOW_MS, TTL_S)
        self.assertEqual((cmd["id"], cmd["action"]), ("c1", "STOP"))
        self.assertIsNotNone(cmd["error"])

    def test_command_without_timestamp_is_rejected(self):
        cmd = agent.new_command({"command": {"id": "c1", "action": "STOP"}}, NOW_MS, TTL_S)
        self.assertIsNotNone(cmd["error"])

    def test_unknown_action_is_rejected(self):
        node = {"command": {"id": "c1", "action": "REBOOT", "ts": NOW_MS}}
        self.assertIsNotNone(agent.new_command(node, NOW_MS, TTL_S)["error"])

    def test_timestamp_slightly_in_future_is_executable(self):
        # Orologio del PC indietro rispetto al server Firebase.
        node = {"command": {"id": "c1", "action": "START", "ts": NOW_MS + 30_000}}
        self.assertIsNone(agent.new_command(node, NOW_MS, TTL_S)["error"])


class FindProcessesTest(unittest.TestCase):
    """Usa il processo python che esegue i test come processo reale da cercare."""

    exe = Path(sys.executable)

    def pids(self, *args):
        return [p.pid for p in agent.find_processes(*args)]

    def test_name_match_ignores_case(self):
        self.assertIn(os.getpid(), self.pids([self.exe.name.upper()]))

    def test_path_filter_excludes_processes_elsewhere(self):
        self.assertNotIn(os.getpid(), self.pids([self.exe.name], r"\WindowsApps\Nessuna_"))

    def test_path_filter_ignores_case(self):
        self.assertIn(os.getpid(), self.pids([self.exe.name], str(self.exe.parent).upper()))

    def test_is_running_applies_the_app_path_filter(self):
        # Come Claude desktop vs Claude Code: stesso nome, cartelle diverse.
        here = {"process_names": [self.exe.name], "running_path_contains": str(self.exe.parent)}
        elsewhere = {"process_names": [self.exe.name], "running_path_contains": r"\WindowsApps\Nessuna_"}
        self.assertTrue(agent.is_running(here))
        self.assertFalse(agent.is_running(elsewhere))


class StopProcessesTest(unittest.TestCase):
    def test_window_is_closed_gracefully(self):
        popen = spawn_python(self, TK_WINDOW)
        status, _ = agent.stop_processes([psutil.Process(popen.pid)], timeout_s=10)
        self.assertEqual(status, "OK")
        # Codice 0 = uscita normale dopo WM_CLOSE; se ucciso sarebbe diverso da 0.
        self.assertEqual(popen.wait(timeout=5), 0)

    def test_process_ignoring_close_is_forced_after_timeout(self):
        popen = spawn_python(self, NO_WINDOW)
        status, _ = agent.stop_processes([psutil.Process(popen.pid)], timeout_s=1)
        self.assertEqual(status, "OK")
        self.assertIsNotNone(popen.poll())

    def test_nothing_to_stop_is_ok(self):
        self.assertEqual(agent.stop_processes([], timeout_s=1)[0], "OK")


class StartAppTest(unittest.TestCase):
    def test_launches_app_and_waits_until_it_runs(self):
        dummy = dummy_exe(self, "pcrc_dummy.exe")

        cfg = app_cfg([str(dummy), *DUMMY_ARGS], dummy.name)
        status, _ = agent.start_app(cfg, timeout_s=10)

        self.assertEqual(status, "OK")
        self.assertTrue(agent.find_processes([dummy.name]))

    def test_missing_executable_is_an_error(self):
        cfg = app_cfg([r"C:\Nessuna\Cartella\app.exe"], "app.exe")
        self.assertEqual(agent.start_app(cfg, timeout_s=1)[0], "ERRORE")

    def test_process_that_never_appears_is_an_error(self):
        # Il comando parte ma il processo atteso non compare (es. AppID sbagliato).
        cfg = app_cfg([sys.executable, "-c", "pass"], "pcrc_mai_visto.exe")
        self.assertEqual(agent.start_app(cfg, timeout_s=1)[0], "ERRORE")

    def test_app_already_running_is_not_launched_again(self):
        marker = temp_dir(self) / "lanciato"
        # Il processo che esegue i test è già attivo con questo nome.
        cfg = app_cfg([sys.executable, "-c", f"open(r'{marker}', 'w')"], Path(sys.executable).name)

        status, _ = agent.start_app(cfg, timeout_s=1)
        time.sleep(1)  # tempo per un eventuale lancio sbagliato di creare il file

        self.assertEqual(status, "OK")
        self.assertFalse(marker.exists())


class ExecuteCommandTest(unittest.TestCase):
    @mock.patch.object(agent, "START_TIMEOUT_S", 1)
    @mock.patch.object(agent, "CLOSE_TIMEOUT_S", 1)
    def test_stop_also_closes_same_named_processes_outside_the_running_path(self):
        # Scelta utente: STOP Claude chiude app desktop *e* Claude Code,
        # che hanno lo stesso nome exe ma cartelle diverse.
        dummy = dummy_exe(self, "pcrc_dummy_stop.exe")
        popen = subprocess.Popen([str(dummy), *DUMMY_ARGS], creationflags=subprocess.CREATE_NO_WINDOW)
        self.addCleanup(kill_quietly, popen)
        cfg = {
            "process_names": [dummy.name],
            "running_path_contains": r"\WindowsApps\Nessuna_",
            "launch": [str(dummy), *DUMMY_ARGS],
        }

        status, _ = agent.execute_command("STOP", cfg)

        self.assertEqual(status, "OK")
        self.assertFalse(agent.find_processes([dummy.name]))

    def test_unknown_action_is_refused(self):
        with self.assertRaises(ValueError):
            agent.execute_command("REBOOT", app_cfg(["x.exe"], "x.exe"))


class SingleInstanceTest(unittest.TestCase):
    def test_second_agent_is_refused_while_the_first_runs(self):
        name = f"Local\\PcRc_test_{os.getpid()}"
        first = agent.acquire_single_instance(name)
        self.addCleanup(agent.release_single_instance, first)

        second = agent.acquire_single_instance(name)

        self.assertIsNotNone(first)
        self.assertIsNone(second)

    def test_name_is_free_again_after_release(self):
        name = f"Local\\PcRc_test_rel_{os.getpid()}"
        agent.release_single_instance(agent.acquire_single_instance(name))

        again = agent.acquire_single_instance(name)
        self.addCleanup(agent.release_single_instance, again)

        self.assertIsNotNone(again)


class AgentTickTest(unittest.TestCase):
    def test_new_command_runs_once_and_its_result_is_published(self):
        db = FakeDb({"antigravity": {"command": command("c1", "START")}})
        executor = FakeExecutor(("OK", "avviato"))
        a = make_agent(db, executor)

        result = tick_until_result(self, a, db, "apps/antigravity", is_final)
        a.tick()
        a.tick()

        self.assertEqual((result["id"], result["status"], result["message"]), ("c1", "OK", "avviato"))
        self.assertEqual(executor.calls, [("START", "antigravity")])

    def test_progress_is_published_while_the_command_runs(self):
        db = FakeDb({"antigravity": {"command": command("c1", "STOP")}})
        executor = FakeExecutor()
        executor.release.clear()
        a = make_agent(db, executor)

        a.tick()
        in_progress = db.get("apps/antigravity/result")
        executor.release.set()
        final = tick_until_result(self, a, db, "apps/antigravity", is_final)

        self.assertEqual((in_progress["id"], in_progress["status"]), ("c1", "IN_CORSO"))
        self.assertEqual((final["id"], final["status"]), ("c1", "OK"))

    def test_expired_command_is_answered_without_running(self):
        db = FakeDb({"antigravity": {"command": command("c1", "STOP", age_s=600)}})
        executor = FakeExecutor()
        a = make_agent(db, executor)

        a.tick()

        result = db.get("apps/antigravity/result")
        self.assertEqual((result["id"], result["status"]), ("c1", "SCARTATO"))
        self.assertEqual(executor.calls, [])

    def test_app_states_and_heartbeat_are_published(self):
        db = FakeDb({})
        a = make_agent(db, FakeExecutor(), running={"claude"})

        a.tick()

        self.assertEqual(db.get("apps/claude/actual_state"), "RUNNING")
        self.assertEqual(db.get("apps/antigravity/actual_state"), "STOPPED")
        self.assertIs(db.get("pc_status/online"), True)
        self.assertEqual(db.get("pc_status/last_seen"), NOW_MS // 1000)

    def test_result_is_not_lost_when_writes_fail(self):
        db = FakeDb({"antigravity": {"command": command("c1", "START")}})
        a = make_agent(db, FakeExecutor(("OK", "avviato")))

        a.tick()
        db.fail_writes = 3
        for _ in range(3):  # l'esito diventa pronto mentre la rete è giù
            time.sleep(0.05)
            a.tick()
        a.tick()

        self.assertEqual(db.get("apps/antigravity/result")["status"], "OK")

    def test_database_errors_do_not_stop_the_agent(self):
        db = FakeDb({})
        a = make_agent(db, FakeExecutor())
        db.fail_reads = 1

        a.tick()  # es. rete non ancora pronta all'avvio del PC
        a.tick()

        self.assertIs(db.get("pc_status/online"), True)

    def test_command_sent_while_busy_runs_after_the_current_one(self):
        db = FakeDb({"antigravity": {"command": command("c1", "STOP")}})
        executor = FakeExecutor()
        executor.release.clear()
        a = make_agent(db, executor)

        a.tick()
        db.root["apps"]["antigravity"]["command"] = command("c2", "START")
        a.tick()
        calls_while_busy = list(executor.calls)
        executor.release.set()
        tick_until_result(self, a, db, "apps/antigravity", lambda r: r["id"] == "c2" and is_final(r))

        self.assertEqual(calls_while_busy, [("STOP", "antigravity")])
        self.assertEqual(executor.calls, [("STOP", "antigravity"), ("START", "antigravity")])

    def test_crash_while_executing_is_reported_as_error(self):
        def crashing_executor(action, cfg):
            raise RuntimeError("guasto")

        db = FakeDb({"antigravity": {"command": command("c1", "START")}})
        a = make_agent(db, crashing_executor)

        result = tick_until_result(self, a, db, "apps/antigravity", is_final)

        self.assertEqual((result["id"], result["status"]), ("c1", "ERRORE"))


class PcCommandTest(unittest.TestCase):
    def test_shutdown_runs_once_and_its_result_is_published_under_pc(self):
        db = FakeDb({}, pc={"command": command("s1", "SHUTDOWN")})
        shutdown = FakeShutdown()
        a = make_agent(db, FakeExecutor(), shutdown=shutdown)

        result = tick_until_result(self, a, db, "pc", is_final)
        a.tick()
        a.tick()

        self.assertEqual((result["id"], result["status"]), ("s1", "OK"))
        self.assertEqual(shutdown.calls, 1)

    def test_app_action_on_pc_node_is_rejected(self):
        db = FakeDb({}, pc={"command": command("s1", "START")})
        shutdown = FakeShutdown()
        a = make_agent(db, FakeExecutor(), shutdown=shutdown)

        a.tick()

        self.assertEqual(db.get("pc/result")["status"], "SCARTATO")
        self.assertEqual(shutdown.calls, 0)

    def test_shutdown_on_app_node_is_rejected(self):
        db = FakeDb({"claude": {"command": command("c1", "SHUTDOWN")}})
        executor = FakeExecutor()
        shutdown = FakeShutdown()
        a = make_agent(db, executor, shutdown=shutdown)

        a.tick()

        self.assertEqual(db.get("apps/claude/result")["status"], "SCARTATO")
        self.assertEqual((executor.calls, shutdown.calls), ([], 0))

    def test_expired_shutdown_is_not_executed(self):
        # Es. comando rimasto su Firebase mentre il PC era spento: niente spegnimento al boot.
        db = FakeDb({}, pc={"command": command("s1", "SHUTDOWN", age_s=600)})
        shutdown = FakeShutdown()
        a = make_agent(db, FakeExecutor(), shutdown=shutdown)

        a.tick()

        self.assertEqual(db.get("pc/result")["status"], "SCARTATO")
        self.assertEqual(shutdown.calls, 0)


class StateSinceTest(unittest.TestCase):
    def test_first_look_publishes_the_real_start_of_the_state(self):
        db = FakeDb({})
        a = make_agent(db, FakeExecutor(), running={"claude"})

        a.tick()

        self.assertEqual(db.get("apps/claude/since"), FIRST_SINCE)
        self.assertEqual(db.get("apps/antigravity/since"), FIRST_SINCE)

    def test_state_change_restarts_the_count_and_then_holds(self):
        running = set()
        clock = [NOW_MS / 1000]
        db = FakeDb({})
        a = make_agent(db, FakeExecutor(), running=running, now=lambda: clock[0])

        a.tick()
        clock[0] += 30
        running.add("antigravity")  # aperta a mano o da un comando START
        a.tick()
        clock[0] += 30
        a.tick()

        self.assertEqual(db.get("apps/antigravity/since"), NOW_MS // 1000 + 30)
        self.assertEqual(db.get("apps/claude/since"), FIRST_SINCE)

    def test_agent_restart_keeps_the_published_start_of_a_closed_app(self):
        closed_at = NOW_MS // 1000 - 600
        db = FakeDb({"antigravity": {"actual_state": "STOPPED", "since": closed_at},
                     "claude": {"actual_state": "RUNNING", "since": closed_at}})
        a = make_agent(db, FakeExecutor())  # entrambe chiuse adesso

        a.tick()

        self.assertEqual(db.get("apps/antigravity/since"), closed_at)
        # Claude era aperta e ora è chiusa: il cambio è avvenuto ad agent spento
        self.assertEqual(db.get("apps/claude/since"), FIRST_SINCE)


class StateStartedAtTest(unittest.TestCase):
    def test_running_app_counts_from_its_process_start(self):
        dummy = dummy_exe(self, "pcrc_dummy_since.exe")
        before = time.time()
        popen = subprocess.Popen([str(dummy), *DUMMY_ARGS], creationflags=subprocess.CREATE_NO_WINDOW)
        self.addCleanup(kill_quietly, popen)

        since = agent.state_started_at(app_cfg([str(dummy)], dummy.name), True)

        self.assertGreaterEqual(since, int(before) - 1)
        self.assertLessEqual(since, time.time())

    def test_stopped_app_counts_from_pc_boot(self):
        cfg = app_cfg(["x.exe"], "pcrc_mai_visto.exe")

        self.assertEqual(agent.state_started_at(cfg, False), int(psutil.boot_time()))


class ShutdownPcTest(unittest.TestCase):
    @mock.patch.object(agent.subprocess, "run")
    def test_schedules_windows_shutdown_after_the_delay(self, run):
        run.return_value = subprocess.CompletedProcess([], 0, "", "")

        status, message = agent.shutdown_pc(10)

        self.assertEqual(run.call_args.args[0][:4], ["shutdown", "/s", "/t", "10"])
        self.assertEqual((status, message), ("OK", "spegnimento tra 10s"))

    @mock.patch.object(agent.subprocess, "run")
    def test_refused_shutdown_is_an_error(self, run):
        run.return_value = subprocess.CompletedProcess([], 1190, "", "Arresto già programmato.")

        status, message = agent.shutdown_pc(10)

        self.assertEqual(status, "ERRORE")
        self.assertIn("Arresto già programmato", message)


if __name__ == "__main__":
    unittest.main()

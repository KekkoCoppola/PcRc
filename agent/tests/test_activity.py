"""Test degli hook di attività (python -m unittest discover -s tests -v, dalla cartella agent/)."""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import activity  # noqa: E402

NOW = 1_790_000_000


def temp_root(test):
    path = Path(tempfile.mkdtemp(prefix="pcrc_activity_"))
    test.addCleanup(shutil.rmtree, path, ignore_errors=True)
    return path


class ActivityDirTest(unittest.TestCase):
    def test_shared_folder_is_outside_appdata(self):
        # Claude desktop è un'app MSIX: Windows dirotta in una cartella del pacchetto le
        # scritture in AppData dei suoi processi (gli hook), e l'agent non le vedrebbe
        with mock.patch.dict(os.environ):
            os.environ.pop("PCRC_ACTIVITY_DIR", None)
            path = activity.activity_dir()

        self.assertEqual(path, Path.home() / ".pcrc" / "activity")
        self.assertNotIn("appdata", str(path).lower())


class StateForTest(unittest.TestCase):
    def claude(self, event, **payload):
        return activity.state_for("claude", event, payload)

    def test_claude_prompt_and_tools_mean_working(self):
        self.assertEqual(self.claude("UserPromptSubmit"), activity.WORKING)
        self.assertEqual(self.claude("PreToolUse", tool_name="Bash"), activity.WORKING)
        self.assertEqual(self.claude("PostToolUse", tool_name="Bash"), activity.WORKING)

    def test_claude_question_and_plan_approval_mean_waiting(self):
        self.assertEqual(self.claude("PreToolUse", tool_name="AskUserQuestion"), activity.WAITING)
        self.assertEqual(self.claude("PreToolUse", tool_name="ExitPlanMode"), activity.WAITING)

    def test_claude_permission_request_means_waiting(self):
        self.assertEqual(self.claude("PermissionRequest", tool_name="Bash"), activity.WAITING)
        self.assertEqual(self.claude("Notification", notification_type="permission_prompt"),
                         activity.WAITING)

    def test_claude_idle_reminder_is_ignored(self):
        # "Claude aspetta il tuo input" dopo 60 s di inattività: il turno era già finito
        self.assertIsNone(self.claude("Notification", notification_type="idle_prompt"))

    def test_claude_stop_means_done_and_session_end_closes(self):
        self.assertEqual(self.claude("Stop"), activity.DONE)
        self.assertEqual(self.claude("SessionEnd"), activity.ENDED)

    def test_antigravity_events(self):
        for event in ("PreInvocation", "PostInvocation", "PostToolUse"):
            self.assertEqual(activity.state_for("antigravity", event, {}), activity.WORKING)
        self.assertEqual(activity.state_for("antigravity", "Stop", {}), activity.DONE)

    def test_unknown_app_or_event_is_ignored(self):
        self.assertIsNone(activity.state_for("claude", "PreCompact", {}))
        self.assertIsNone(activity.state_for("altro", "Stop", {}))


class RecordTest(unittest.TestCase):
    def test_writes_session_state_with_project_name(self):
        root = temp_root(self)
        payload = {"session_id": "abc-123", "cwd": r"D:\PROGETTI\PcRc"}

        activity.record("claude", "UserPromptSubmit", payload, now=NOW, root=root)

        data = json.loads((root / "claude" / "abc-123.json").read_text("utf-8"))
        self.assertEqual(data, {"state": "WORKING", "ts": NOW, "project": "PcRc", "turn": NOW})

    def test_turn_starts_with_the_prompt_and_lasts_until_the_next_one(self):
        root = temp_root(self)
        for event, at in (("UserPromptSubmit", NOW), ("PreToolUse", NOW + 5), ("Stop", NOW + 9)):
            activity.record("claude", event, {"session_id": "s1"}, now=at, root=root)
        turn_after_stop = json.loads((root / "claude" / "s1.json").read_text("utf-8"))["turn"]

        activity.record("claude", "UserPromptSubmit", {"session_id": "s1"}, now=NOW + 60, root=root)

        self.assertEqual(turn_after_stop, NOW)
        self.assertEqual(json.loads((root / "claude" / "s1.json").read_text("utf-8"))["turn"], NOW + 60)

    def test_antigravity_turn_starts_with_the_first_work_after_finishing(self):
        root = temp_root(self)
        for event, at in (("PreInvocation", NOW), ("Stop", NOW + 5), ("PreInvocation", NOW + 60),
                          ("PostToolUse", NOW + 61)):
            activity.record("antigravity", event, {"conversationId": "c1"}, now=at, root=root)

        self.assertEqual(json.loads((root / "antigravity" / "c1.json").read_text("utf-8"))["turn"], NOW + 60)

    def test_project_is_the_git_repository_even_from_a_subfolder(self):
        # La cwd di Claude Code segue i cd della sessione (es. PcRc\app)
        root, repo = temp_root(self), temp_root(self)
        (repo / ".git").mkdir()
        (repo / "app" / "lib").mkdir(parents=True)

        activity.record("claude", "Stop", {"session_id": "s1", "cwd": str(repo / "app" / "lib")},
                        now=NOW, root=root)

        data = json.loads((root / "claude" / "s1.json").read_text("utf-8"))
        self.assertEqual(data["project"], repo.name)

    def test_antigravity_uses_conversation_and_first_workspace(self):
        root = temp_root(self)
        payload = {"conversationId": "c1", "workspacePaths": [r"d:\PROGETTI\MetaRisk"]}

        activity.record("antigravity", "Stop", payload, now=NOW, root=root)

        data = json.loads((root / "antigravity" / "c1.json").read_text("utf-8"))
        self.assertEqual((data["state"], data["project"]), ("DONE", "MetaRisk"))

    def test_session_end_removes_the_file(self):
        root = temp_root(self)
        activity.record("claude", "Stop", {"session_id": "s1"}, now=NOW, root=root)

        activity.record("claude", "SessionEnd", {"session_id": "s1"}, now=NOW, root=root)

        self.assertFalse((root / "claude" / "s1.json").exists())

    def test_ignored_event_leaves_the_state_untouched(self):
        root = temp_root(self)
        activity.record("claude", "PermissionRequest", {"session_id": "s1"}, now=NOW, root=root)

        activity.record("claude", "Notification", {"session_id": "s1", "notification_type": "idle_prompt"},
                        now=NOW + 60, root=root)

        data = json.loads((root / "claude" / "s1.json").read_text("utf-8"))
        self.assertEqual((data["state"], data["ts"]), ("WAITING", NOW))

    def test_record_reports_whether_the_hook_must_stop_the_agent(self):
        root = temp_root(self)
        self.assertFalse(activity.record("claude", "UserPromptSubmit", {"session_id": "s1"}, now=NOW, root=root))
        self.assertFalse(activity.record("claude", "PreCompact", {"session_id": "s1"}, now=NOW, root=root))

    def test_session_id_cannot_escape_the_folder(self):
        root = temp_root(self)

        activity.record("claude", "Stop", {"session_id": r"..\..\evil"}, now=NOW, root=root)

        self.assertEqual([p.parent for p in root.rglob("*.json")], [root / "claude"])


class SummarizeTest(unittest.TestCase):
    def setUp(self):
        self.root = temp_root(self)

    def session(self, app, sid, state, age_s, project=None):
        folder = self.root / app
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{sid}.json").write_text(
            json.dumps({"state": state, "ts": NOW - age_s, "project": project}), "utf-8")

    def summary(self, app="claude", stall_s=None):
        return activity.summarize(app, NOW, root=self.root, stall_s=stall_s)

    def test_no_sessions_is_idle(self):
        self.assertEqual(self.summary(), (activity.IDLE, None))

    def test_waiting_beats_working_beats_done(self):
        self.session("claude", "a", "DONE", 5, "A")
        self.session("claude", "b", "WORKING", 5, "B")
        self.assertEqual(self.summary(), ("WORKING", "B"))

        self.session("claude", "c", "WAITING", 500, "C")
        self.assertEqual(self.summary(), ("WAITING", "C"))

    def test_most_recent_session_names_the_project(self):
        self.session("claude", "a", "DONE", 50, "Vecchio")
        self.session("claude", "b", "DONE", 5, "Nuovo")
        self.assertEqual(self.summary(), ("DONE", "Nuovo"))

    def test_working_without_events_for_too_long_no_longer_counts(self):
        # Esc in Claude Code interrompe il turno senza lanciare Stop
        self.session("claude", "a", "WORKING", activity.WORKING_EXPIRY_S + 1)
        self.assertEqual(self.summary(), (activity.IDLE, None))

    def test_stalled_work_counts_as_waiting_when_the_app_has_a_stall_limit(self):
        self.session("antigravity", "a", "WORKING", 31, "MetaRisk")
        self.assertEqual(self.summary("antigravity", stall_s=30), ("WAITING", "MetaRisk"))
        self.assertEqual(self.summary("antigravity", stall_s=60), ("WORKING", "MetaRisk"))

    def test_very_old_files_are_deleted(self):
        self.session("claude", "a", "DONE", activity.PRUNE_AFTER_S + 1)
        self.assertEqual(self.summary(), (activity.IDLE, None))
        self.assertFalse((self.root / "claude" / "a.json").exists())

    def test_broken_files_are_skipped(self):
        (self.root / "claude").mkdir()
        (self.root / "claude" / "rotto.json").write_text("{non json", "utf-8")
        self.session("claude", "b", "DONE", 5)
        self.assertEqual(self.summary()[0], "DONE")


class MainTest(unittest.TestCase):
    def run_hook(self, args, stdin_text, root):
        out = io.StringIO()
        code = activity.main(args, stdin=io.StringIO(stdin_text), stdout=out, root=root, now=NOW)
        return code, out.getvalue()

    def test_antigravity_hook_records_the_event_and_answers_an_empty_object(self):
        # Antigravity vuole sempre un oggetto JSON su stdout; {} non cambia nulla
        root = temp_root(self)

        code, out = self.run_hook(["antigravity", "Stop"], json.dumps({"conversationId": "c1"}), root)

        self.assertEqual((code, json.loads(out)), (0, {}))
        self.assertTrue((root / "antigravity" / "c1.json").exists())

    def test_claude_hook_prints_nothing(self):
        # Su UserPromptSubmit lo stdout di un hook finisce nel contesto di Claude
        root = temp_root(self)

        code, out = self.run_hook(["claude", "UserPromptSubmit"], json.dumps({"session_id": "s1"}), root)

        self.assertEqual((code, out), (0, ""))
        self.assertTrue((root / "claude" / "s1.json").exists())

    def test_hook_never_fails_the_caller(self):
        # Un hook che esce con errore potrebbe bloccare Claude o Antigravity
        root = temp_root(self)
        self.assertEqual(self.run_hook(["claude", "Stop"], "non è json", root)[0], 0)
        self.assertEqual(self.run_hook([], "", root)[0], 0)

    def test_real_process_round_trip(self):
        root = temp_root(self)
        env = {**os.environ, "PCRC_ACTIVITY_DIR": str(root)}
        proc = subprocess.run(
            [sys.executable, str(Path(activity.__file__)), "antigravity", "PreInvocation"],
            input=json.dumps({"conversationId": "c9"}), capture_output=True, text=True,
            env=env, timeout=20, creationflags=subprocess.CREATE_NO_WINDOW,
        )
        self.assertEqual((proc.returncode, proc.stdout.strip()), (0, "{}"))
        self.assertEqual(json.loads((root / "antigravity" / "c9.json").read_text("utf-8"))["state"],
                         "WORKING")


class InterruptTest(unittest.TestCase):
    """Tasto Interrompi del telefono: l'agent scrive il segnale, l'hook ferma l'agente AI."""

    def setUp(self):
        self.root = temp_root(self)

    def hook(self, app, event, payload, at):
        out = io.StringIO()
        activity.main([app, event], stdin=io.StringIO(json.dumps(payload)), stdout=out,
                      root=self.root, now=at)
        return out.getvalue()

    def state(self, app, sid):
        return json.loads((self.root / app / f"{sid}.json").read_text("utf-8"))["state"]

    def test_claude_turn_started_before_the_request_stops_at_the_next_tool(self):
        self.hook("claude", "UserPromptSubmit", {"session_id": "s1"}, NOW)
        activity.request_interrupt("claude", now=NOW + 10, root=self.root)

        out = self.hook("claude", "PreToolUse", {"session_id": "s1", "tool_name": "Bash"}, NOW + 20)

        self.assertEqual(json.loads(out)["continue"], False)
        self.assertEqual(self.state("claude", "s1"), "DONE")

    def test_turn_started_after_the_request_is_not_stopped(self):
        activity.request_interrupt("claude", now=NOW, root=self.root)
        self.hook("claude", "UserPromptSubmit", {"session_id": "s1"}, NOW + 10)

        out = self.hook("claude", "PostToolUse", {"session_id": "s1", "tool_name": "Bash"}, NOW + 20)

        self.assertEqual(out, "")
        self.assertEqual(self.state("claude", "s1"), "WORKING")

    def test_old_request_expires(self):
        self.hook("claude", "UserPromptSubmit", {"session_id": "s1"}, NOW)
        activity.request_interrupt("claude", now=NOW + 1, root=self.root)

        out = self.hook("claude", "PreToolUse", {"session_id": "s1"}, NOW + activity.INTERRUPT_TTL_S + 2)

        self.assertEqual(out, "")

    def test_request_for_antigravity_does_not_touch_claude(self):
        self.hook("claude", "UserPromptSubmit", {"session_id": "s1"}, NOW)
        activity.request_interrupt("antigravity", now=NOW + 10, root=self.root)

        self.assertEqual(self.hook("claude", "PreToolUse", {"session_id": "s1"}, NOW + 20), "")

    def test_antigravity_stops_after_the_model_call(self):
        # Solo PostInvocation può terminare il ciclo; PreInvocation risponde sempre {}
        self.hook("antigravity", "PreInvocation", {"conversationId": "c1"}, NOW)
        activity.request_interrupt("antigravity", now=NOW + 10, root=self.root)

        before = self.hook("antigravity", "PreInvocation", {"conversationId": "c1"}, NOW + 15)
        after = self.hook("antigravity", "PostInvocation", {"conversationId": "c1"}, NOW + 20)

        self.assertEqual(json.loads(before), {})
        self.assertEqual(json.loads(after), {"terminationBehavior": "terminate"})
        self.assertEqual(self.state("antigravity", "c1"), "DONE")

    def test_signal_file_is_not_a_session(self):
        activity.request_interrupt("claude", now=NOW, root=self.root)

        self.assertEqual(activity.summarize("claude", NOW, root=self.root), (activity.IDLE, None))


class InstallHooksTest(unittest.TestCase):
    def setUp(self):
        self.home = temp_root(self)
        self.claude_settings = self.home / ".claude" / "settings.json"
        self.gemini_hooks = self.home / ".gemini" / "config" / "hooks.json"
        self.command = "C:/Python/python.exe D:/PcRc/agent/activity.py"

    def install(self):
        activity.install_hooks(self.command, self.claude_settings, self.gemini_hooks)

    def test_keeps_existing_claude_settings_and_hooks(self):
        self.claude_settings.parent.mkdir(parents=True)
        other = {"matcher": "Bash", "hooks": [{"type": "command", "command": "altro.sh"}]}
        self.claude_settings.write_text(json.dumps({"theme": "dark", "hooks": {"PreToolUse": [other]}}),
                                        "utf-8")

        self.install()

        settings = json.loads(self.claude_settings.read_text("utf-8"))
        self.assertEqual(settings["theme"], "dark")
        self.assertIn(other, settings["hooks"]["PreToolUse"])
        commands = [h["command"] for group in settings["hooks"]["Stop"] for h in group["hooks"]]
        self.assertEqual(commands, [f"{self.command} claude Stop"])

    def test_installing_twice_does_not_duplicate(self):
        self.install()
        self.install()

        settings = json.loads(self.claude_settings.read_text("utf-8"))
        for event, groups in settings["hooks"].items():
            self.assertEqual(len(groups), 1, event)

    def test_antigravity_gets_its_own_named_hook(self):
        self.gemini_hooks.parent.mkdir(parents=True)
        self.gemini_hooks.write_text(json.dumps({"lint": {"Stop": []}}), "utf-8")

        self.install()

        hooks = json.loads(self.gemini_hooks.read_text("utf-8"))
        self.assertIn("lint", hooks)
        ours = hooks[activity.ANTIGRAVITY_HOOK_NAME]
        self.assertEqual(ours["Stop"][0]["command"], f"{self.command} antigravity Stop")
        self.assertEqual(ours["PostToolUse"][0]["matcher"], "*")
        # Mai PreToolUse: la sua risposta decide i permessi dei tool
        self.assertNotIn("PreToolUse", ours)


if __name__ == "__main__":
    unittest.main()

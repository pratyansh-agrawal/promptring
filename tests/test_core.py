#!/usr/bin/env python3
"""Cross-platform unit tests for promptring's OS-agnostic core.

These run on any OS with python3 (no banner is shown — only the shared
logic that composes banners, parses categories, summarises transcripts,
and merges hooks is exercised). Run:  python3 tests/test_core.py
"""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(REPO, "bin")


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(BIN, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


pr = _load("promptring", "promptring.py")
enrich = _load("enrich_context", "enrich_context.py")
mh = _load("merge_hooks", "merge-hooks.py")


def _read(path):
    with open(path) as fh:
        return json.load(fh)


class ComposeLayout(unittest.TestCase):
    """The macOS reference banner layout must hold on every OS."""

    def test_title_includes_label(self):
        spec = pr.compose("done", "all green", "my-session", "")
        self.assertEqual(spec["title"], "promptring — my-session")

    def test_title_without_label(self):
        spec = pr.compose("done", "all green", "", "")
        self.assertEqual(spec["title"], "promptring")

    def test_subtitle_is_emoji_plus_status(self):
        spec = pr.compose("done", "x", "s", "")
        self.assertEqual(spec["subtitle"], "✅ Task complete")

    def test_body_prefers_explicit_message_over_summary(self):
        spec = pr.compose("done", "explicit", "s", "from-transcript")
        self.assertEqual(spec["body"], "explicit")

    def test_body_falls_back_to_summary(self):
        spec = pr.compose("done", "", "s", "from-transcript")
        self.assertEqual(spec["body"], "from-transcript")

    def test_spec_carries_icon_and_sound(self):
        spec = pr.compose("done", "x", "s", "")
        self.assertTrue(spec["icon"].endswith("icon.png"))
        self.assertEqual(spec["sound_name"], "tring")


class Categories(unittest.TestCase):
    def test_known_categories(self):
        for key, status in [
            ("done", "Task complete"),
            ("input", "Needs your input"),
            ("ready", "Ready to continue"),
            ("blocked", "Blocked — needs you"),
            ("info", "Update"),
        ]:
            emoji, st, sound = pr.parse_category(key)
            self.assertEqual(st, status, key)
            self.assertTrue(emoji, key)
            self.assertEqual(sound, "tring", key)

    def test_unknown_category_degrades_gracefully(self):
        emoji, status, sound = pr.parse_category("totally-unknown")
        self.assertEqual(status, "totally-unknown")
        self.assertEqual(sound, "tring")
        self.assertTrue(emoji)


class Sound(unittest.TestCase):
    def test_bundled_tring_resolves(self):
        self.assertTrue(os.path.isfile(pr.resolve_sound("tring")))

    def test_dash_is_silent(self):
        self.assertEqual(pr.resolve_sound("-"), "")
        self.assertEqual(pr.resolve_sound(""), "")

    def test_sound_toggle_env(self):
        os.environ["COPILOT_NOTIFY_SOUND"] = "0"
        self.assertFalse(pr.sound_enabled())
        os.environ["COPILOT_NOTIFY_SOUND"] = "1"
        self.assertTrue(pr.sound_enabled())
        del os.environ["COPILOT_NOTIFY_SOUND"]


class MuteAndTone(unittest.TestCase):
    """`--mute` / `--tring` persist to a state file the delivery path reads."""

    def setUp(self):
        # isolate each test on its own state file + custom-tone dir
        fd, self._state = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        os.remove(self._state)                       # start with no state
        self._saved_state = os.environ.get("PROMPTRING_STATE")
        os.environ["PROMPTRING_STATE"] = self._state
        pr.STATE_FILE = self._state
        self._saved_custom = pr.CUSTOM_DIR
        pr.CUSTOM_DIR = os.path.join(tempfile.mkdtemp(), "custom")

    def tearDown(self):
        import shutil
        if self._saved_state is None:
            os.environ.pop("PROMPTRING_STATE", None)
        else:
            os.environ["PROMPTRING_STATE"] = self._saved_state
        pr.STATE_FILE = self._saved_state or os.path.join(
            os.path.dirname(BIN), "state.json")
        for p in (self._state, os.path.dirname(pr.CUSTOM_DIR)):
            shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else (
                os.path.exists(p) and os.remove(p))
        pr.CUSTOM_DIR = self._saved_custom

    # --- mute ---------------------------------------------------------
    def test_no_state_keeps_sound_on(self):
        self.assertTrue(pr.sound_enabled())

    def test_mute_flag_silences_then_unmute_restores(self):
        self.assertEqual(pr.handle_cli(["--mute"]), 0)
        self.assertTrue(pr.load_state().get("muted"))
        self.assertFalse(pr.sound_enabled())
        self.assertEqual(pr.handle_cli(["--unmute"]), 0)
        self.assertFalse(pr.load_state().get("muted"))
        self.assertTrue(pr.sound_enabled())

    def test_env_off_still_wins_when_unmuted(self):
        pr.handle_cli(["--unmute"])
        os.environ["COPILOT_NOTIFY_SOUND"] = "0"
        try:
            self.assertFalse(pr.sound_enabled())
        finally:
            del os.environ["COPILOT_NOTIFY_SOUND"]

    # --- custom tone --------------------------------------------------
    def _make_tone(self):
        d = tempfile.mkdtemp()
        src = os.path.join(d, "mine.wav")
        with open(src, "wb") as fh:
            fh.write(b"RIFFdummy")
        return src

    def test_tring_copies_and_compose_uses_it(self):
        src = self._make_tone()
        self.assertEqual(pr.handle_cli(["--tring", src]), 0)
        tone = pr.load_state().get("tone")
        self.assertTrue(tone and os.path.isfile(tone))
        self.assertEqual(os.path.dirname(tone), pr.CUSTOM_DIR)   # copied, not referenced
        spec = pr.compose("done", "x", "s", "")
        self.assertEqual(spec["sound_file"], tone)
        self.assertEqual(spec["sound_name"], "custom")

    def test_untring_reverts_to_bundled(self):
        pr.handle_cli(["--tring", self._make_tone()])
        self.assertEqual(pr.handle_cli(["--untring"]), 0)
        self.assertFalse(pr.load_state().get("tone"))
        self.assertFalse(os.path.isdir(pr.CUSTOM_DIR))
        spec = pr.compose("done", "x", "s", "")
        self.assertEqual(spec["sound_name"], "tring")           # bundled default

    def test_missing_tone_falls_back(self):
        # a stored tone whose file has vanished must not break compose
        pr.save_state({"tone": "/nope/does-not-exist.wav"})
        spec = pr.compose("done", "x", "s", "")
        self.assertEqual(spec["sound_name"], "tring")

    def test_tring_missing_file_is_error(self):
        self.assertEqual(pr.handle_cli(["--tring", "/nope/missing.wav"]), 1)
        self.assertFalse(pr.load_state().get("tone"))

    def test_unknown_flag_is_usage_error(self):
        self.assertEqual(pr.handle_cli(["--wat"]), 2)


class Enrich(unittest.TestCase):
    def test_summarize_strips_markdown(self):
        out = enrich.summarize("## Done\n- **fixed** the `bug`")
        self.assertNotIn("**", out)
        self.assertNotIn("`", out)
        self.assertNotIn("#", out)
        self.assertTrue(out)

    def test_summarize_handles_empty(self):
        self.assertEqual(enrich.summarize(""), "")
        self.assertEqual(enrich.summarize(None) if False else enrich.summarize(""), "")

    def test_summarize_is_one_line(self):
        out = enrich.summarize("line one\nline two\nline three")
        self.assertNotIn("\n", out)


class MergeHooks(unittest.TestCase):
    def _src(self):
        return os.path.join(REPO, "hooks.json")

    def _write(self, data):
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        with open(path, "w") as fh:
            json.dump(data, fh)
        return path

    def test_add_into_empty(self):
        target = self._write({"version": 1, "hooks": {}})
        try:
            mh.do_add(target, self._src())
            d = _read(target)
            self.assertIn("agentStop", d["hooks"])
            entry = d["hooks"]["agentStop"][0]
            self.assertTrue(mh._is_ours(entry))
        finally:
            os.remove(target)

    def test_add_is_idempotent(self):
        target = self._write({"version": 1, "hooks": {}})
        try:
            mh.do_add(target, self._src())
            n1 = len(_read(target)["hooks"]["agentStop"])
            mh.do_add(target, self._src())
            n2 = len(_read(target)["hooks"]["agentStop"])
            self.assertEqual(n1, n2)
        finally:
            os.remove(target)

    def test_foreign_hooks_preserved(self):
        target = self._write({
            "version": 1,
            "hooks": {"sessionStart": [{"type": "command", "bash": "user-init.sh"}]},
        })
        try:
            mh.do_add(target, self._src())
            d = _read(target)
            self.assertEqual(d["hooks"]["sessionStart"][0]["bash"], "user-init.sh")
            self.assertIn("agentStop", d["hooks"])
        finally:
            os.remove(target)

    def test_remove_strips_only_ours(self):
        target = self._write({
            "version": 1,
            "hooks": {"agentStop": [{"type": "command", "bash": "user-init.sh"}]},
        })
        try:
            mh.do_add(target, self._src())
            mh.do_remove(target)
            d = _read(target)
            stops = d.get("hooks", {}).get("agentStop", [])
            self.assertEqual(len(stops), 1)
            self.assertEqual(stops[0]["bash"], "user-init.sh")
            self.assertFalse(mh._is_ours(stops[0]))
        finally:
            if os.path.exists(target):
                os.remove(target)

    def test_entry_matches_powershell_key(self):
        entry = {"type": "command",
                 "powershell": 'python "$env:USERPROFILE\\.copilot\\promptring\\bin\\promptring.py" done'}
        self.assertTrue(mh._is_ours(entry))


class InputRequestDetection(unittest.TestCase):
    """agentStop 'done' must re-fire as 'input' when the agent is asking."""

    def test_question_mark_tail_is_input(self):
        self.assertTrue(pr.is_input_request("I built the module.\nWhich database should I use?"))

    def test_offer_to_continue_is_input(self):
        self.assertTrue(pr.is_input_request("Done with phase 1. Want me to start phase 2?"))

    def test_soft_closing_without_qmark_is_not_input(self):
        # polite offers that aren't questions must stay 'done'
        self.assertFalse(pr.is_input_request("Finished the refactor. Let me know how you'd like to proceed."))
        self.assertFalse(pr.is_input_request("Two options here. Your call."))
        self.assertFalse(pr.is_input_request("All tests pass. Let me know if you want any tweaks."))

    def test_plain_completion_is_not_input(self):
        self.assertFalse(pr.is_input_request("All 19 tests passed and the build is green."))
        self.assertFalse(pr.is_input_request("Fixed the bug and pushed the branch."))

    def test_empty_is_not_input(self):
        self.assertFalse(pr.is_input_request(""))
        self.assertFalse(pr.is_input_request(None))

    def test_early_question_does_not_trigger_on_completion(self):
        # a question buried far above a completion tail should not flip it
        msg = ("Should I have used Postgres? I went with SQLite.\n"
               + "\n".join(f"Step {i} done." for i in range(1, 12))
               + "\nEverything is committed and the suite is green.")
        self.assertFalse(pr.is_input_request(msg))

    def test_question_followed_by_statement_is_not_input(self):
        # the closing sentence, not an earlier question, decides intent
        self.assertFalse(pr.is_input_request("Should I deploy? Let me know."))

    def test_toggle_env_disables(self):
        os.environ["PROMPTRING_AUTO_INPUT"] = "0"
        self.assertFalse(pr.autoinput_enabled())
        os.environ["PROMPTRING_AUTO_INPUT"] = "1"
        self.assertTrue(pr.autoinput_enabled())
        del os.environ["PROMPTRING_AUTO_INPUT"]


class DeliveryFallback(unittest.TestCase):
    """_spawn reports failure; WSL falls back to Linux when the bridge is down."""

    def test_spawn_returns_false_on_bad_exec(self):
        # mimics ENOEXEC (broken WSL interop) / a missing binary
        self.assertFalse(pr._spawn(["/nonexistent/promptring-xyz", "a"]))

    def test_spawn_returns_true_when_launched(self):
        self.assertTrue(pr._spawn(["echo", "ok"]))

    def test_wsl_falls_back_to_linux_when_inline_fails(self):
        saved = (pr.IS_MACOS, pr.IS_WINDOWS, pr.IS_LINUX, pr.IS_WSL,
                 pr.deliver_wsl_inline, pr.deliver_linux)
        try:
            pr.IS_MACOS = pr.IS_WINDOWS = pr.IS_LINUX = False
            pr.IS_WSL = True
            pr.deliver_wsl_inline = lambda spec: False  # interop down
            seen = {}
            pr.deliver_linux = lambda spec: seen.setdefault("linux", True)
            self.assertTrue(pr.deliver(pr.compose("done", "x", "lbl", "")))
            self.assertTrue(seen.get("linux", False))
        finally:
            (pr.IS_MACOS, pr.IS_WINDOWS, pr.IS_LINUX, pr.IS_WSL,
             pr.deliver_wsl_inline, pr.deliver_linux) = saved

    def test_wsl_no_fallback_when_inline_succeeds(self):
        saved = (pr.IS_MACOS, pr.IS_WINDOWS, pr.IS_LINUX, pr.IS_WSL,
                 pr.deliver_wsl_inline, pr.deliver_linux)
        try:
            pr.IS_MACOS = pr.IS_WINDOWS = pr.IS_LINUX = False
            pr.IS_WSL = True
            pr.deliver_wsl_inline = lambda spec: True   # inline toast works
            seen = {}
            pr.deliver_linux = lambda spec: seen.setdefault("linux", True)
            self.assertTrue(pr.deliver(pr.compose("done", "x", "lbl", "")))
            self.assertNotIn("linux", seen)
        finally:
            (pr.IS_MACOS, pr.IS_WINDOWS, pr.IS_LINUX, pr.IS_WSL,
             pr.deliver_wsl_inline, pr.deliver_linux) = saved


    def test_stage_avoids_basename_collisions(self):
        # two different sources sharing a basename + size must stage distinctly
        d = tempfile.mkdtemp()
        a_dir = os.path.join(d, "a"); b_dir = os.path.join(d, "b")
        os.makedirs(a_dir); os.makedirs(b_dir)
        wsl_dir = os.path.join(d, "stage"); os.makedirs(wsl_dir)
        src_a = os.path.join(a_dir, "icon.png"); open(src_a, "wb").write(b"AAAA")
        src_b = os.path.join(b_dir, "icon.png"); open(src_b, "wb").write(b"BBBB")
        win_a = pr._stage(src_a, r"C:\Temp\promptring", wsl_dir)
        win_b = pr._stage(src_b, r"C:\Temp\promptring", wsl_dir)
        self.assertTrue(win_a and win_b)
        self.assertNotEqual(win_a, win_b)
        self.assertEqual(open(os.path.join(wsl_dir, os.path.basename(win_a.replace("\\", "/"))), "rb").read(), b"AAAA")
        self.assertEqual(open(os.path.join(wsl_dir, os.path.basename(win_b.replace("\\", "/"))), "rb").read(), b"BBBB")

    def test_stage_is_stable_across_runs(self):
        # the hash prefix must be deterministic so re-staging dedupes
        d = tempfile.mkdtemp()
        src = os.path.join(d, "icon.png"); open(src, "wb").write(b"XYZ")
        wsl_dir = os.path.join(d, "stage"); os.makedirs(wsl_dir)
        self.assertEqual(pr._stage(src, r"C:\T", wsl_dir),
                         pr._stage(src, r"C:\T", wsl_dir))


if __name__ == "__main__":
    unittest.main(verbosity=2)

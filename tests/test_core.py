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


if __name__ == "__main__":
    unittest.main(verbosity=2)

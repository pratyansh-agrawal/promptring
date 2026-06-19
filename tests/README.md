# promptring — tests

promptring's logic is OS-independent (one Python orchestrator); only the
final banner delivery is native. The tests mirror that split.

## 1. Cross-platform unit tests — run anywhere with `python3`

```
python3 tests/test_core.py
```

Covers the shared core (no banner shown):

- **compose layout** — the macOS reference contract holds on every OS:
  `title = promptring — <session>`, `subtitle = <emoji> <status>`,
  body prefers an explicit message, else the transcript summary.
- **categories.conf parsing** — all shipped categories + graceful
  fallback for unknown keys.
- **sound resolution** — bundled `tring` resolves; `-`/empty is silent;
  the `COPILOT_NOTIFY_SOUND` toggle.
- **enrich-context** — markdown is stripped and the summary is one line.
- **merge-hooks** — add / idempotent re-add / foreign-hook preservation /
  remove-strips-only-ours / matches the `powershell` hook key.

## 2. Smoke tests — per OS

Fire every category through the **real orchestrator**. Default is
`PROMPTRING_DRYRUN=1` (asserts exit 0 + correct delivery backend, no
banner). Add the live flag to actually show banners + play the chime.

| OS              | command                          | live banners            |
| --------------- | -------------------------------- | ----------------------- |
| macOS / Linux   | `tests/smoke.sh`                 | `tests/smoke.sh --live` |
| WSL             | `tests/smoke.sh`                 | `tests/smoke.sh --live` |
| Windows         | `powershell -File tests\smoke.ps1` | `… smoke.ps1 -Live`   |

## 3. Manual delivery checklist (validate native UI per OS)

Run after `install.sh` / `install.ps1`. The banner UI/sound/icon must
match the macOS reference on every platform.

### macOS  ✅ verified on dev box
- [x] `~/.copilot/promptring/bin/promptring.py done "hi"` shows a banner:
      title `promptring — <tab>`, subtitle `✅ Task complete`, body `hi`,
      promptring icon, `tring` chime.
- [x] First run: macOS permission prompt → Allow; alert style = Banners.
- [x] Hook fires at end of a real Copilot turn (restart session first).

### Windows  ⚠ validate on a Windows machine
- [ ] `python %USERPROFILE%\.copilot\promptring\bin\promptring.py done "hi"`
      → WinRT toast under the **promptring** name + app icon.
- [ ] Taskbar icon flashes and shows a badge.
- [ ] `tring` chime plays.
- [ ] `powershell -File tests\smoke.ps1 -Live` pops all 5 categories.
- [ ] After `install.ps1` + Copilot restart, the hook fires at turn end
      (Copilot runs the `powershell` hook key → `python promptring.py`).

### Linux  ⚠ validate on a desktop Linux machine
- [ ] `notify-send` present (`sudo apt install libnotify-bin` if not).
- [ ] `promptring.py done "hi"` → libnotify banner with promptring icon.
- [ ] Sound via `paplay`/`aplay`/`canberra-gtk-play`.
- [ ] `tests/smoke.sh --live` pops all categories.
- [ ] Headless/SSH: no daemon → expect silence (documented limitation).

### WSL  ⚠ validate inside WSL with a Windows host
- [ ] **WSL interop works** — `powershell.exe -NoProfile -Command "exit 0"` runs
      without `Exec format error`. If it fails, the bridge can't deliver; the
      installer tries to re-register the `WSLInterop` binfmt handler, but a
      `wsl --shutdown` (from Windows) + reopen is the reliable repair.
- [ ] `install.sh` detects WSL, copies assets to the Windows-side
      `%USERPROFILE%\.copilot\promptring`, registers the AUMID.
- [ ] `promptring.py done "hi"` shells to the Windows toast → banner
      appears on the **Windows** desktop with the promptring icon + chime.
- [ ] `tests/smoke.sh` reports backend `wsl`.
- [ ] Debugging: `PROMPTRING_DEBUG=1 ~/.copilot/promptring/bin/promptring.py done "hi"`
      prints why delivery failed (and logs to `~/.copilot/promptring/promptring.log`).
      When interop is down, delivery falls back to `notify-send` (WSLg).

Report failures with the exact `PROMPTRING_DRYRUN=1 … <category>` spec
JSON so the composed fields can be compared against the reference.

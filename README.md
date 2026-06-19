<h1 align="center">
  <img src="app/icon.png" width="116" alt="promptring icon"><br>
  promptring
</h1>

<p align="center">
  <strong>prompt·tring</strong> &nbsp;/ˈprɒm(p)t.trɪŋ/&nbsp; — that little <strong>tring</strong> 🔔 the moment your terminal agent is done.
</p>

<p align="center">
  <a href="https://pratyansh-agrawal.github.io/promptring/"><strong>Website</strong></a> &nbsp;·&nbsp;
  <a href="#install">Install</a> &nbsp;·&nbsp;
  <a href="#usage">Usage</a>
  <br><br>
  <img src="https://img.shields.io/badge/platform-macOS%20·%20Windows%20·%20Linux%20·%20WSL-000" alt="macOS · Windows · Linux · WSL">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <img src="https://img.shields.io/badge/dependencies-python3-brightgreen" alt="Only python3">
</p>

<p align="center">
  <img src="docs/media/banner-demo.gif" width="640" alt="promptring banners cycling through task complete, needs input, and blocked states">
</p>

Terminal-native desktop notifications for the **GitHub Copilot CLI** — so you
know the moment an agent finishes a task, needs your input, or hits a blocker,
even when you've switched to another app. Works on **macOS, Windows, Linux and
WSL** from a single, OS-independent codebase.

No Homebrew, no extra packages, no `osascript` hacks. One small Python
orchestrator owns all the logic; each OS only handles the final banner with its
own native delivery — a self-contained signed app on macOS, a WinRT toast +
taskbar badge on Windows, `notify-send` on Linux, and an inline WinRT toast
under WSL (rendered through `powershell.exe`, **no Windows-side install**, with
a `notify-send`/WSLg fallback). The look, the promptring icon, and the bundled
**tring** chime are identical everywhere.

```
✅ Copilot — Task complete: rebuilt the auth module
🟡 Copilot — Needs your input: choose a database engine
⛔ Copilot — Blocked — needs you: build failed, missing env var
```


## Install

promptring works the same on every platform — one `python3` dependency, one
install dir (`~/.copilot/promptring`), one `hooks.json` that carries both a
`bash` and a `powershell` command so the Copilot CLI picks the right one per OS.

### macOS · Linux · WSL

**Prerequisites:** `python3`, `git`, `bash`.
macOS also needs **Xcode Command Line Tools** (`xcode-select --install`).
Linux also needs **`notify-send`** (`sudo apt install libnotify-bin`).

```sh
# 1. Clone
git clone https://github.com/pratyansh-agrawal/promptring.git
cd promptring

# 2. Install (auto-detects macOS / Linux / WSL)
./install.sh

# 3. Verify (expect: a desktop banner + the bundled tring chime)
~/.copilot/promptring/bin/promptring.py done "promptring works"

# 4. Start / restart a Copilot CLI session so it loads the hook
copilot
```

### Windows

**Prerequisites:** **Python 3** (from python.org, "Add to PATH"), Windows
Terminal recommended.

```powershell
# 1. Clone
git clone https://github.com/pratyansh-agrawal/promptring.git
cd promptring

# 2. Install (registers the toast app identity + merges hooks)
powershell -ExecutionPolicy Bypass -File install.ps1

# 3. Verify (expect: a toast + taskbar badge + tring chime)
python "$env:USERPROFILE\.copilot\promptring\bin\promptring.py" done "promptring works"

# 4. Restart your Copilot CLI session
copilot
```

On macOS, the **first banner** triggers a notification-permission prompt for
Promptring — click **Allow**. Then, one time per machine, open **System
Settings → Notifications → Promptring** and set its alert style to **Banners**
(macOS sometimes defaults new apps to "None"/Notification Center only).

Everything installs under `~/.copilot/promptring`, so once the installer
finishes you can safely **delete or move the cloned folder**. Restart Copilot
after installing so the hook loads (it's read fresh at session start).

## Usage

Once installed, the Copilot CLI fires notifications automatically on its own
lifecycle events — when an agent finishes, needs your approval, or asks a
question. No further action needed.

The installer also writes a fenced, mandatory block into
`~/.copilot/copilot-instructions.md` (shared source:
[`copilot-instructions.block.md`](./copilot-instructions.block.md)). The
Copilot CLI fires no hookable event when an agent pauses on the built-in
`ask_user` tool, so under `--yolo` a decision prompt would otherwise show no
banner — the block requires the agent to fire the `input` banner itself right
before it asks you to decide (with the correct command for each OS). All
installers (macOS, Linux, WSL, Windows) write the same block; re-running
refreshes it in place and keeps your other instructions.

To fire one manually:

```sh
~/.copilot/promptring/bin/promptring.py <category> [message]
```

| Category | Emoji | Meaning |
| --- | --- | --- |
| `done`    | ✅ | Task complete |
| `input`   | 🟡 | Needs your input |
| `ready`   | ▶️ | Long-running command finished |
| `blocked` | ⛔ | Blocked / error — needs you |
| `info`    | 💬 | Heads-up / status update |

Unknown categories fall back to a generic 🔔 banner.

## Configuration

Edit [`categories.conf`](./categories.conf) — pipe-delimited, one scenario per
line:

```
# key      | emoji | title    | subtitle              | sound
done       | ✅    | Copilot  | Task complete         | tring
input      | 🟡    | Copilot  | Needs your input      | tring
```

promptring ships its own sound (`sounds/tring.mp3`). Sound names resolve to a
bundled file first, then `~/Library/Sounds`, then macOS system sounds (`Glass`,
`Ping`, …). To disable the sound layer and use only the terminal's own:

```sh
export COPILOT_NOTIFY_SOUND=0
```

### Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `COPILOT_NOTIFY_SOUND` | `1` | Set `0` to mute the bundled chime (the terminal's own sound still plays). |
| `PROMPTRING_AUTO_INPUT` | `1` | Set `0` to stop re-classifying a `done` turn as a 🟡 `input` banner when the agent ends by asking you a question. |
| `PROMPTRING_DEBUG` | – | Set `1` to log delivery decisions to stderr and `~/.copilot/promptring/promptring.log` (handy for diagnosing WSL). |
| `PROMPTRING_AUMID` | – | **WSL** — override the Windows AppUserModelID used for the inline toast. |
| `COPILOT_NOTIFY_CONFIG` | – | Path to an alternate `categories.conf`. |

## Troubleshooting

**No banner under WSL?** The toast is rendered on the Windows side through
`powershell.exe`, so WSL interop must be working. Diagnose with:

```sh
PROMPTRING_DEBUG=1 ~/.copilot/promptring/bin/promptring.py done "hi"
```

If you see an `Exec format error` / `ENOEXEC`, the kernel's `WSLInterop`
handler is missing — run `wsl --shutdown` from Windows and reopen the distro
(the installer also tries to re-register it). promptring automatically falls
back to `notify-send` (WSLg) when the toast can't run, so `sudo apt install
libnotify-bin` enables that path.

## Platform support

| OS          | Delivery backend                                  | Sound                          | Session label             | Status            |
| ----------- | ------------------------------------------------- | ------------------------------ | ------------------------- | ----------------- |
| **macOS**   | signed `UNUserNotificationCenter` app (`Promptring.app`) | `afplay`                | iTerm/Terminal tab title  | ✅ reference       |
| **Windows** | WinRT toast (PS 5.1) + taskbar flash & badge      | `MediaPlayer`                  | Windows Terminal title    | ⚠ needs validation |
| **Linux**   | `notify-send` (libnotify)                         | `paplay`/`aplay`/`canberra`    | working-folder fallback   | ⚠ needs validation |
| **WSL**     | inline WinRT toast via `powershell.exe` (no Windows install) → `notify-send`/WSLg fallback | Windows-side chime | Windows Terminal title | ✅ verified |

All platforms share the same title/subtitle/body layout, the promptring icon, and the
bundled `tring` chime. One Python orchestrator (`bin/promptring.py`) composes the
banner; only the final delivery is native.

## Requirements

- **`python3`** on every OS (the single orchestrator). On macOS it ships with the
  Command Line Tools; on Windows install from python.org with "Add to PATH".
- **macOS:** Xcode Command Line Tools (`swiftc`, `codesign`, `sips`, `iconutil`).
- **Windows:** Windows PowerShell 5.1 (built in) for the WinRT toast.
- **Linux:** `notify-send` (`libnotify-bin`); a sound player (`paplay`/`aplay`).
- **WSL:** a Windows host with working WSL interop (`powershell.exe` must be
  runnable). **No Windows-side promptring install needed** — the toast is
  rendered inline; promptring falls back to `notify-send`/WSLg if interop is down.

## Uninstall

The hook removal is identical on every OS (your other hooks are preserved):

```sh
# macOS / Linux / WSL
python3 ~/.copilot/promptring/bin/merge-hooks.py remove ~/.copilot/hooks/hooks.json
rm -rf ~/.copilot/promptring
# macOS also: unregister the app
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -u "$HOME/.copilot/promptring/platform/macos/Promptring.app"
```

```powershell
# Windows
python "$env:USERPROFILE\.copilot\promptring\bin\merge-hooks.py" remove "$env:USERPROFILE\.copilot\hooks\hooks.json"
Remove-Item -Recurse -Force "$env:USERPROFILE\.copilot\promptring"
Remove-Item -Recurse -Force "HKCU:\Software\Classes\AppUserModelId\com.promptring.notifier"
```

On macOS you can also remove Promptring from **System Settings → Notifications**
after unregistering.

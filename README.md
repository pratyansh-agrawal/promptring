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
  <img src="https://img.shields.io/badge/dependency-python3-brightgreen" alt="Only python3">
</p>

<p align="center">
  <img src="docs/media/banner-demo.gif" width="640" alt="promptring prompt notifications cycling through task complete, needs input, and blocked states">
</p>

**promptring** brings **prompt notifications** to the **GitHub Copilot CLI** —
real desktop banners that fire the moment an agent finishes a task, needs your
input, or hits a blocker. Switch to another window and you'll still catch the
*tring* 🔔, so you never sit babysitting the terminal again.

```
✅ Copilot — Task complete: rebuilt the auth module
🟡 Copilot — Needs your input: choose a database engine
⛔ Copilot — Blocked: build failed, missing env var
```

## Why promptring

- 🌍 **Cross-platform** — native desktop notifications on every major OS, from one codebase and a single `python3` dependency.
- 🔔 **Real banners, not hacks** — genuine Notification Center / toast banners, never fragile terminal escape codes.
- 📂 **Session-aware** — each banner names the terminal tab that pinged you and recaps what the agent did in one line.
- 🪝 **Deterministic** — fires on the Copilot CLI's own lifecycle hooks, so you're alerted on finish, permission prompts, and input requests.
- 🔊 **Yours to tune** — a bundled *tring* chime and editable categories; swap the sound or mute it entirely.

## Install

One line, no clone. The installer lands everything in `~/.copilot/promptring`;
restart the Copilot CLI afterward so the hook loads.

**macOS · Linux · WSL**

```sh
curl -fsSL https://pratyansh-agrawal.github.io/promptring/install.sh | bash
```

**Windows**

```powershell
irm https://pratyansh-agrawal.github.io/promptring/install.ps1 | iex
```

> **Prerequisites:** `python3`. macOS also needs Xcode Command Line Tools
> (`xcode-select --install`); Linux/WSL also needs `notify-send`
> (`sudo apt install libnotify-bin`); Windows needs Python from
> [python.org](https://www.python.org/downloads/) ("Add to PATH").

Send a test banner — expect a notification plus the *tring*:

```sh
~/.copilot/promptring/bin/promptring.py done "promptring works"
```

> On macOS, the first banner asks for notification permission — click **Allow**,
> then set **System Settings → Notifications → Promptring** to **Banners** (new
> apps sometimes default to "None").

<details>
<summary><strong>Prefer to install from source?</strong></summary>

```sh
git clone https://github.com/pratyansh-agrawal/promptring.git
cd promptring
./install.sh        # macOS · Linux · WSL
# Windows:  powershell -ExecutionPolicy Bypass -File install.ps1
```

</details>

## Usage

Once installed, promptring fires automatically on the Copilot CLI's lifecycle
events — when an agent finishes, needs approval, or asks a question. Nothing
else to do.

To send a **prompt notification** by hand:

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

## Customize

Edit [`categories.conf`](./categories.conf) to change any emoji, wording, or
sound — it's pipe-delimited, one scenario per line:

```
# key  | emoji | title   | subtitle          | sound
done    | ✅    | Copilot | Task complete     | tring
input   | 🟡    | Copilot | Needs your input  | tring
```

A few environment variables fine-tune behavior:

| Variable | Default | Effect |
| --- | --- | --- |
| `COPILOT_NOTIFY_SOUND` | `1` | Set `0` to mute the bundled chime. |
| `PROMPTRING_AUTO_INPUT` | `1` | Set `0` to stop re-tagging a finished turn as 🟡 when the agent ends by asking you a question. |
| `PROMPTRING_DEBUG` | – | Set `1` to log delivery decisions to `~/.copilot/promptring/promptring.log`. |
| `COPILOT_NOTIFY_CONFIG` | – | Path to an alternate `categories.conf`. |

## Troubleshooting

**No banner under WSL?** The toast is rendered on the Windows side through
`powershell.exe`, so WSL interop must work. Diagnose with:

```sh
PROMPTRING_DEBUG=1 ~/.copilot/promptring/bin/promptring.py done "hi"
```

An `Exec format error` / `ENOEXEC` means the kernel's `WSLInterop` handler is
missing — run `wsl --shutdown` from Windows and reopen the distro. promptring
falls back to `notify-send` (WSLg) when the toast can't run, so
`sudo apt install libnotify-bin` keeps notifications working meanwhile.

## Uninstall

Your other Copilot hooks are preserved.

```sh
# macOS / Linux / WSL
python3 ~/.copilot/promptring/bin/merge-hooks.py remove ~/.copilot/hooks/hooks.json
# macOS only: unregister the app BEFORE deleting it
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -u "$HOME/.copilot/promptring/platform/macos/Promptring.app"
rm -rf ~/.copilot/promptring
```

```powershell
# Windows
python "$env:USERPROFILE\.copilot\promptring\bin\merge-hooks.py" remove "$env:USERPROFILE\.copilot\hooks\hooks.json"
Remove-Item -Recurse -Force "$env:USERPROFILE\.copilot\promptring"
Remove-Item -Recurse -Force "HKCU:\Software\Classes\AppUserModelId\com.promptring.notifier"
```

---

<sub><strong>promptring</strong> — prompt notifications &amp; desktop alerts for the GitHub Copilot CLI · built by <a href="https://github.com/pratyansh-agrawal">Pratyansh Agrawal</a> · MIT License</sub>

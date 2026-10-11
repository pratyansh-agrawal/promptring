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
  <img src="https://img.shields.io/badge/requires-Node.js%2018%2B%20%2B%20Python%203-brightgreen" alt="Requires Node.js 18+ and Python 3">
  <a href="https://www.npmjs.com/package/promptring"><img src="https://img.shields.io/npm/v/promptring" alt="npm version"></a>
  <a href="https://www.npmjs.com/package/promptring"><img src="https://img.shields.io/npm/dm/promptring" alt="npm downloads"></a>
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

- 🌍 **Cross-platform** — native desktop notifications on every major OS, driven by one shared Python orchestrator.
- 🔔 **Real banners, not hacks** — genuine Notification Center / toast banners, never fragile terminal escape codes.
- 📂 **Session-aware** — each banner names the terminal tab that pinged you and recaps what the agent did in one line.
- 🪝 **Deterministic** — fires on the Copilot CLI's own lifecycle hooks, so you're alerted on finish, permission prompts, and input requests.
- 🔊 **Yours to tune** — a bundled *tring* chime and editable categories; swap the sound or mute it entirely.

## Install

Install the official npm package:

```sh
npm install -g promptring
```

**Prerequisites:** Node.js 18+ and Python 3. macOS also needs Xcode Command
Line Tools; Linux/WSL needs `notify-send` for notification banners.

The npm installer detects macOS, Windows, Linux, or WSL automatically and lands
everything in `~/.copilot/promptring`. Restart the Copilot CLI afterward so the
hook loads.

<details>
<summary><strong>Alternative direct or source installation</strong></summary>

**macOS · Linux · WSL**

```sh
curl -fsSL https://pratyansh-agrawal.github.io/promptring/install.sh | bash
```

**Windows**

```powershell
irm https://pratyansh-agrawal.github.io/promptring/install.ps1 | iex
```

**From source**

```sh
git clone https://github.com/pratyansh-agrawal/promptring.git
cd promptring
./install.sh
# Windows: powershell -ExecutionPolicy Bypass -File install.ps1
```

</details>

Send a test banner — expect a notification plus the *tring*:

```sh
~/.copilot/promptring/bin/promptring.py done "promptring works"
```

> On macOS, the first banner asks for notification permission — click **Allow**,
> then set **System Settings → Notifications → Promptring** to **Banners** (new
> apps sometimes default to "None").

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

### Control the chime

The installer also puts a **`promptring`** command on your PATH. Open a **new**
terminal and use it to mute the sound or set your own tone — from anywhere, with
no config editing. On-screen banners are unaffected; only the sound changes.

```sh
promptring --check             # send a test notification and play the active chime
promptring --mute              # silence the chime (banners still show)
promptring --unmute            # bring it back
promptring --tring ~/alert.mp3 # use your own audio for every notification
promptring --untring           # revert to the bundled tring
promptring --status            # show the current mute state + active tone
promptring --info              # list all available commands
```

The custom tone is copied into `~/.copilot/promptring`, so it keeps working even
if you later move or delete the original file. Most audio formats play on macOS,
Windows, and WSL; on plain Linux the `paplay`/`aplay` players favor `wav`/`ogg`/
`flac`, so prefer those there.

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
| `COPILOT_NOTIFY_SOUND` | `1` | Set `0` to mute the chime for one session. For a persistent, terminal-wide mute use `promptring --mute` instead. |
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
# drop the PATH line the installer added (in ~/.zshrc, ~/.bashrc, or ~/.profile):
#   # promptring:path:start … # promptring:path:end
```

```powershell
# Windows
python "$env:USERPROFILE\.copilot\promptring\bin\merge-hooks.py" remove "$env:USERPROFILE\.copilot\hooks\hooks.json"
Remove-Item -Recurse -Force "$env:USERPROFILE\.copilot\promptring"
Remove-Item -Recurse -Force "HKCU:\Software\Classes\AppUserModelId\com.promptring.notifier"
# drop the shim folder from your user PATH
$shim = Join-Path $env:USERPROFILE '.copilot\promptring\shim'
$p = ([Environment]::GetEnvironmentVariable('Path','User') -split ';' | Where-Object { $_ -ne $shim }) -join ';'
[Environment]::SetEnvironmentVariable('Path', $p, 'User')
```

---

<sub><strong>promptring</strong> — prompt notifications &amp; desktop alerts for the GitHub Copilot CLI · built by <a href="https://github.com/pratyansh-agrawal">Pratyansh Agrawal</a> · MIT License</sub>

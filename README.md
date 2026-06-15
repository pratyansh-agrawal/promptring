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
  <img src="https://img.shields.io/badge/platform-macOS-000?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <img src="https://img.shields.io/badge/dependencies-none-brightgreen" alt="Zero dependencies">
</p>

<p align="center">
  <img src="docs/media/banner-demo.gif" width="640" alt="promptring banners cycling through task complete, needs input, and blocked states">
</p>

Terminal-native desktop notifications for the **GitHub Copilot CLI** — so you
know the moment an agent finishes a task, needs your input, or hits a blocker,
even when you've switched to another app.

No Homebrew, no extra packages, no `osascript` hacks. promptring ships a tiny,
self-contained macOS notification agent (built locally from source) plus the
built-in `afplay` for sound — real desktop **banners** that work from **any**
terminal, including Terminal.app and iTerm2.

```
✅ Copilot — Task complete: rebuilt the auth module
🟡 Copilot — Needs your input: choose a database engine
⛔ Copilot — Blocked — needs you: build failed, missing env var
```


## Install

**Prerequisites:** macOS · **Xcode Command Line Tools** (`xcode-select
--install`) · `git`, `bash`.

```sh
# 1. Clone
git clone https://github.com/pratyansh-agrawal/promptring.git
cd promptring

# 2. Install
./install.sh

# 3. Verify (expect: a desktop banner + the bundled tring.mp3)
~/.copilot/promptring/bin/copilot-notify done "promptring works"

# 4. Start / restart a Copilot CLI session so it loads the hook
copilot
```

On the **first banner**, macOS asks for notification permission for
Promptring — click **Allow**. Then, one time per machine, open **System
Settings → Notifications → Promptring** and set its alert style to **Banners**
(macOS sometimes defaults new apps to "None"/Notification Center only).

Everything installs under `~/.copilot/promptring`, so once `install.sh` finishes
you can safely **delete or move the cloned folder**. Restart Copilot after
installing so the hook loads (it's read fresh at session start).

## Usage

Once installed, the Copilot CLI fires notifications automatically on its own
lifecycle events — when an agent finishes, needs your approval, or asks a
question. No further action needed.

To fire one manually:

```sh
~/.copilot/promptring/bin/copilot-notify <category> [message]
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

## Requirements

- macOS (uses a signed `UNUserNotificationCenter` app + `afplay`)
- **Xcode Command Line Tools** (`swiftc`, `codesign`, `sips`, `iconutil`)
- `python3` (ships with the CLT)
- `bash`, `ps`, `sed`, `awk` (all standard)

## Uninstall

```sh
# remove only promptring's hooks (your other hooks are preserved),
# then unregister and delete the app
python3 ~/.copilot/promptring/bin/merge-hooks.py remove ~/.copilot/hooks/hooks.json
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -u "$HOME/.copilot/promptring/app/Promptring.app"
rm -rf ~/.copilot/promptring
```

You can also remove Promptring from **System Settings → Notifications** after
unregistering.

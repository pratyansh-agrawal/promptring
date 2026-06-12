# promptring 🔔

Terminal-native desktop notifications for the **GitHub Copilot CLI** — so you
know the moment an agent finishes a task, needs your input, or hits a blocker,
even when you've switched to another app.

No Homebrew, no `terminal-notifier`, no `osascript`. promptring ships a tiny,
self-contained macOS notification agent (built locally from source) plus the
built-in `afplay` for sound — real desktop **banners** that work from **any**
terminal, including Terminal.app and iTerm2.

```
✅ Copilot — Task complete: rebuilt the auth module
🟡 Copilot — Needs your input: choose a database engine
⛔ Copilot — Blocked — needs you: build failed, missing env var
```

## Why this exists

Getting a reliable banner out of a CLI/hook context on modern macOS is
surprisingly hard:

- The Copilot CLI runs each shell tool on its **own captured PTY**, so terminal
  escape sequences (`printf '\e]9;…\a'`) get swallowed and never reach your
  emulator.
- `osascript display notification` posts as "Script Editor"; from a CLI/hook
  context macOS finds no responsible app and **drops it entirely** — not even in
  Notification Center.
- `terminal-notifier` and other legacy `NSUserNotification` tools reach
  Notification Center but their **banners are suppressed on macOS 14/15**.

The only thing that pops a banner reliably is a **real, signed `.app` bundle**
with its own bundle identity that posts via `UNUserNotificationCenter`. So
promptring builds exactly that — `Promptring.app`, a ~tiny `LSUIElement`
(background) agent — at install time and fires it for every notification.

## How it works

For each notification the helper:

1. **Enriches the banner from hook context.** When fired by a Copilot CLI hook,
   the CLI pipes a JSON payload on `stdin` (e.g. `agentStop` →
   `{cwd, sessionId, transcriptPath, …}`). promptring then:
   - resolves your **terminal tab title** by matching the session's TTY against
     iTerm2/Terminal via AppleScript — so the banner leads with the exact tab
     that pinged you (e.g. *"Prompt-tring (copilot)"*), even with many windows
     open. (First use may trigger a one-time macOS **Automation** permission
     prompt; on deny / other terminals it falls back to the working-folder name,
     skipping the bare home dir.)
   - reads the agent's last message from the transcript for a one-line
     **summary** of what it just did (`bin/enrich-context.py`).
2. **Launches `Promptring.app`** (detached, in the background) with the title
   (the tab name, or `emoji · category` if unknown), subtitle (category), and
   message (summary). The app posts a `UNUserNotificationCenter` banner + adds
   it to Notification Center, then quietly exits.
3. **Plays a sound** via the built-in `afplay` (the bundled `tring.mp3` by
   default; see below).
4. On iTerm2, also sends `OSC 1337 RequestAttention` for a Dock bounce; on
   non-macOS / no-app environments, falls back to `OSC 777` + bell.

Silent + never fails the calling turn. The app stays a background
(`.accessory`) process so it never steals focus. Its icon (`app/icon.png`,
rendered to `icon.icns` at build time) is the promptring "p" mark.

## Install

**Prerequisites:** macOS · **Xcode Command Line Tools** (`xcode-select
--install`) to build the app · `git`, `bash`.

```sh
# 1. Clone
git clone https://github.com/pratyansh-agrawal/promptring.git
cd promptring

# 2. Install — builds Promptring.app, registers it, symlinks the helper + hook
./install.sh

# 3. Verify (expect: a desktop banner + the bundled tring.mp3)
~/.copilot/notify/bin/copilot-notify done "promptring works"

# 4. Start / restart a Copilot CLI session so it loads the hook
copilot
```

On the **first banner**, macOS asks for notification permission for
Promptring — click **Allow**. Then, one time per machine, open **System
Settings → Notifications → Promptring** and set its alert style to **Banners**
(macOS sometimes defaults new apps to "None"/Notification Center only).

### What `install.sh` does

- **Builds `Promptring.app`** from `app/src/main.swift` via `swiftc` and
  ad-hoc-signs it (`codesign --sign -`), then **registers it with
  LaunchServices** so macOS gives it a notification identity.
- Symlinks `bin/copilot-notify` + `categories.conf` → `~/.copilot/notify/`, so
  this repo stays the single source of truth. The helper resolves its real path
  even through the symlink, so it still finds `Promptring.app` + `sounds/tring.mp3`.
- Installs the notification hook by symlinking `hooks.json` →
  `~/.copilot/hooks/hooks.json`. The Copilot CLI reads this on every session
  start and fires the notifier **directly on its own events** — so firing is
  deterministic and never depends on the model remembering to run a command.
- Removes any obsolete `promptring` instruction block from
  `~/.copilot/copilot-instructions.md` left by older versions.

> ⚠️ Don't move or delete the cloned folder after install — the live paths
> (helper, config, **and the app**) symlink/resolve into it. **Restart Copilot**
> after installing so the hook loads (it's read fresh at session start).

## Usage

```sh
copilot-notify <category> [message]
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
done       | ✅    | Copilot  | Task complete         | Glass
input      | 🟡    | Copilot  | Needs your input      | Glass
```

System sounds: `Basso Blow Bottle Frog Funk Glass Hero Morse Ping Pop Purr
Sosumi Submarine Tink` (or drop a custom `.aiff` in `~/Library/Sounds`).

### Sound

promptring **ships its own notification sound** (`sounds/tring.mp3`), so the
package is fully standalone — no reliance on system audio files. Each category
plays it via the built-in `afplay`, layered on top of the banner.

Sound names in `categories.conf` are resolved in this order (first hit wins):

1. **bundled** — `sounds/<name>.{wav,aiff,mp3,m4a}`
2. **user** — `~/Library/Sounds/<name>.aiff`
3. **system** — `/System/Library/Sounds/<name>.aiff`

So `tring` uses the packaged sound, while names like `Glass` or `Ping` still
resolve to the macOS system sounds if you prefer them. To disable the afplay
layer entirely and use only the terminal's own notification sound:

```sh
export COPILOT_NOTIFY_SOUND=0
```

To use a different sound, drop a file into `sounds/` (or `~/Library/Sounds`)
and set its name (without extension) in `categories.conf`. macOS system sounds
(`Glass`, etc.) are only ever referenced **by name** at runtime, never
redistributed.

## Copilot CLI integration

promptring hooks into the Copilot CLI's **native notification hook system**
([`hooks.json`](./hooks.json)), so notifications fire deterministically on the
CLI's own lifecycle events — no reliance on the model remembering to run a
command. `install.sh` symlinks it to `~/.copilot/hooks/hooks.json`; the CLI
reads it fresh at the start of every session.

| CLI event | matcher | fires |
| --- | --- | --- |
| `agentStop` | — | `copilot-notify done` (agent handed control back to you) |
| `notification` | `permission_prompt` | `copilot-notify input` (a tool needs approval) |
| `notification` | `elicitation_dialog` | `copilot-notify input` (`ask_user` / MCP prompt) |

Each hook is a `type: "command"` entry whose `bash` runs the helper. Edit
`hooks.json` to remap events to other categories or add more (`sessionStart`,
`preToolUse`, `errorOccurred`, …). Restart Copilot to reload.

## Requirements

- macOS (uses a signed `UNUserNotificationCenter` app + `afplay`)
- **Xcode Command Line Tools** (`swiftc`, `codesign`, `sips`, `iconutil`) — to build the app + icon
- `python3` (ships with the CLT) — for hook-context enrichment
- `bash`, `ps`, `sed`, `awk` (all standard)

## Uninstall

```sh
# remove the symlinks + hook
rm ~/.copilot/notify/bin/copilot-notify ~/.copilot/notify/categories.conf
rm ~/.copilot/hooks/hooks.json

# unregister + delete the built app
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -u "$(pwd)/app/Promptring.app"
rm -rf app/Promptring.app
```

You can also remove Promptring from **System Settings → Notifications** after
unregistering.

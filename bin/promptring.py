#!/usr/bin/env python3
# ════════════════════════════════════════════════════════════════════
#  promptring — cross-platform notification orchestrator for Copilot CLI
# ════════════════════════════════════════════════════════════════════
#  ONE entrypoint for every OS. All OS-independent work (read the hook
#  payload, summarise the agent's last message, resolve the session
#  label, look up the category, compose the banner, pick the sound) lives
#  here. Only the final delivery is native, isolated behind deliver():
#
#      macOS  → Promptring.app (UNUserNotificationCenter) + afplay
#      Windows→ WinRT toast (PowerShell 5.1) + taskbar badge + MediaPlayer
#      Linux  → notify-send (libnotify) + paplay/aplay
#      WSL    → bridge to the Windows toast (reuses the Windows backend)
#
#  The banner design is identical everywhere (the macOS reference):
#      promptring — <session>     ← title
#      <emoji> <status>           ← subtitle
#      <summary>                  ← body
#
#  Usage:  promptring.py <category> [message]    (hook JSON optional on STDIN)
#  Silent + never fails the calling turn (always exits 0).
# ════════════════════════════════════════════════════════════════════
import sys, os, re, json, subprocess, platform

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HOME_DIR   = os.path.dirname(SCRIPT_DIR)                       # install root
CONFIG     = os.environ.get("COPILOT_NOTIFY_CONFIG") or os.path.join(HOME_DIR, "categories.conf")
SOUNDS_DIR = os.path.join(HOME_DIR, "sounds")
ICON_PNG   = os.path.join(HOME_DIR, "app", "icon.png")
AUMID      = "com.promptring.notifier"

# Reuse the shared enricher (same dir) for the one-line summary.
sys.path.insert(0, SCRIPT_DIR)
try:
    import enrich_context  # type: ignore
except Exception:
    enrich_context = None


# ── platform detection ──────────────────────────────────────────────
def _is_wsl():
    if platform.system() != "Linux":
        return False
    try:
        with open("/proc/version", "r") as fh:
            return "microsoft" in fh.read().lower()
    except Exception:
        return False

IS_MACOS   = platform.system() == "Darwin"
IS_WINDOWS = platform.system() == "Windows" or os.name == "nt"
IS_WSL     = _is_wsl()
IS_LINUX   = platform.system() == "Linux" and not IS_WSL


# ── hook payload + enrichment ───────────────────────────────────────
def read_payload():
    """Return the hook JSON dict (empty if none / not piped)."""
    if sys.stdin is None or sys.stdin.isatty():
        return {}
    try:
        raw = sys.stdin.read()
    except Exception:
        return {}
    if not raw or not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {}


def enrich(payload):
    """(folder, summary, last_msg) derived from the hook payload.

    `last_msg` is the raw final assistant message (used to tell whether the
    agent is asking the user for direction vs. reporting completion).
    Any field may be ''."""
    cwd = payload.get("cwd") or ""
    folder = os.path.basename(cwd.rstrip("/\\")) if cwd else ""
    summary, last_msg = "", ""
    if enrich_context is not None:
        sid = payload.get("session_id") or payload.get("sessionId") or ""
        tp  = payload.get("transcript_path") or payload.get("transcriptPath") or ""
        try:
            last_msg = enrich_context.last_assistant_message(tp, sid) or ""
            summary = enrich_context.summarize(last_msg)
        except Exception:
            summary, last_msg = "", ""
    return folder, summary, last_msg


# ── intent: is the agent asking for direction, or reporting done? ────
#  The Copilot CLI fires `agentStop` on *every* turn-end with a hardcoded
#  stop reason, so it can't tell us "done" from "waiting on you". We infer
#  it from the agent's closing words instead — a question near the end, or
#  an explicit ask for direction, means it's really an input request (this
#  fires even under `--yolo`, where no permission prompt is ever shown).
_ASK_PATTERNS = re.compile(
    r"let me know|"
    r"would you like|do you want|want me to|"
    r"shall i|should i\b|"
    r"which (?:option|one|of|would|do you)|"
    r"please (?:confirm|advise|choose|pick|let me know|clarify|specify)|"
    r"could you (?:clarify|confirm|tell me|specify)|"
    r"can you (?:confirm|clarify|tell me|specify)|"
    r"how would you like|what would you (?:like|prefer)|"
    r"your call|up to you|pick one|"
    r"waiting for your|awaiting your|"
    r"need(?:s)? your (?:input|direction|decision|guidance|call)",
    re.IGNORECASE,
)


def _closing(text, lines=4, chars=320):
    """The tail of the message — where a question usually lives."""
    text = re.sub(r"```.*?```", "", text or "", flags=re.DOTALL)
    segs = [l.strip() for l in text.splitlines() if l.strip()]
    return (" ".join(segs[-lines:]) if segs else "")[-chars:]


def is_input_request(text):
    """True when the agent's final message is asking the user for direction."""
    if not text:
        return False
    tail = _closing(text)
    if not tail:
        return False
    if "?" in tail[-220:]:
        return True
    return bool(_ASK_PATTERNS.search(tail))


def autoinput_enabled():
    return os.environ.get("PROMPTRING_AUTO_INPUT", "1").lower() not in (
        "0", "false", "no", "off")


# ── session label (the human-recognisable terminal tab) ─────────────
def _run(cmd, inp=None, timeout=4):
    try:
        p = subprocess.run(cmd, input=inp, capture_output=True,
                           text=True, timeout=timeout)
        return p.stdout
    except Exception:
        return ""


def _macos_tab_title():
    """The iTerm2/Terminal tab title for the session that fired (matched by
    TTY), via AppleScript. Falls back silently on other terminals."""
    if not IS_MACOS:
        return ""
    pty = _macos_find_pty()
    if not pty or pty == "/dev/tty":
        return ""
    term = os.environ.get("TERM_PROGRAM", "")
    script = ""
    if term == "iTerm.app":
        script = (
            'tell application "iTerm2"\n'
            '  repeat with w in windows\n'
            '    repeat with t in tabs of w\n'
            '      repeat with s in sessions of t\n'
            f'        if (tty of s) is "{pty}" then return (name of s)\n'
            '      end repeat\n'
            '    end repeat\n'
            '  end repeat\n'
            'end tell\n'
            'return ""')
    elif term == "Apple_Terminal":
        script = (
            'tell application "Terminal"\n'
            '  repeat with w in windows\n'
            '    repeat with t in tabs of w\n'
            f'      if (tty of t) is "{pty}" then\n'
            '        try\n'
            '          set ct to custom title of t\n'
            '          if ct is not "" then return ct\n'
            '        end try\n'
            '        return (name of w)\n'
            '      end if\n'
            '    end repeat\n'
            '  end repeat\n'
            'end tell\n'
            'return ""')
    else:
        return ""
    out = _run(["osascript", "-e", script]).replace("\r", " ").replace("\n", " ").strip()
    return out


def _macos_find_pty():
    """Outermost real, writable TTY in the process-ancestor chain — the
    terminal emulator's session PTY (the agent runs on a captured sub-PTY)."""
    pid = os.getppid()
    result = ""
    for _ in range(16):
        line = _run(["ps", "-o", "ppid=,tty=,comm=", "-p", str(pid)]).strip()
        if not line:
            break
        parts = line.split()
        if len(parts) < 2:
            break
        ppid, tty = parts[0], parts[1]
        if tty and tty not in ("??", "?"):
            dev = "/dev/" + tty
            if os.access(dev, os.W_OK):
                result = dev
        if ppid in ("", "0", "1"):
            break
        try:
            pid = int(ppid)
        except ValueError:
            break
    if result:
        return result
    return "/dev/tty" if os.access("/dev/tty", os.W_OK) else ""


def _windows_terminal_title():
    """The Windows Terminal window title (all Copilot tabs share one WT
    window, so its MainWindowTitle is the active session). Works from WSL
    too via powershell.exe interop."""
    ps = _powershell_exe()
    if not ps:
        return ""
    cmd = ("$ErrorActionPreference='SilentlyContinue';"
           "(Get-Process WindowsTerminal | Where-Object { $_.MainWindowHandle -ne 0 } |"
           " Select-Object -First 1).MainWindowTitle")
    out = _run([ps, "-NoProfile", "-Command", cmd]).replace("\r", "").strip()
    return out


def session_label(folder):
    """Resolve the tab/session label, with the working-folder as fallback
    (never the home dir, whose basename is just the username = noise)."""
    label = ""
    if IS_MACOS:
        label = _macos_tab_title()
    elif IS_WINDOWS or IS_WSL:
        label = _windows_terminal_title()
    if not label and folder and folder != os.path.basename(os.path.expanduser("~")):
        label = folder
    return label


# ── category lookup + composition ───────────────────────────────────
def parse_category(key):
    """(emoji, status, sound_name) for `key` from categories.conf.
    Format: key | emoji | title | subtitle | sound  (title col unused)."""
    emoji = status = sound = ""
    if os.path.isfile(CONFIG):
        try:
            with open(CONFIG, encoding="utf-8") as fh:
                for line in fh:
                    t = line.strip()
                    if not t or t.startswith("#"):
                        continue
                    cols = [c.strip() for c in t.split("|")]
                    if len(cols) < 5:
                        continue
                    if cols[0] == key:
                        emoji, status, sound = cols[1], cols[3], cols[4]
                        break
        except Exception:
            pass
    if not status:                       # unknown category → graceful default
        status, emoji, sound = key, "🔔", "tring"
    return emoji, status, sound


def compose(key, message, label, summary):
    """Build the banner fields (the macOS reference layout)."""
    emoji, status, sound_name = parse_category(key)
    body = message or summary or ""
    title_line = f"promptring — {label}" if label else "promptring"
    subtitle_line = f"{emoji} {status}".strip() if emoji else status
    return {
        "category": key,
        "title": title_line,
        "subtitle": subtitle_line,
        "body": body,
        "status": status,
        "label": label,
        "icon": ICON_PNG,
        "sound_name": sound_name,
        "sound_file": resolve_sound(sound_name),
    }


def resolve_sound(name):
    """Absolute path to the sound file, or '' for silent/'-'/not-found.
    Bundled sounds first (keeps it standalone); on macOS also honour plain
    system-sound names (~/Library/Sounds, /System/Library/Sounds)."""
    if not name or name == "-":
        return ""
    dirs = [SOUNDS_DIR]
    exts = ["wav", "aiff", "mp3", "m4a", "caf"]
    if IS_MACOS:
        dirs += [os.path.expanduser("~/Library/Sounds"), "/System/Library/Sounds"]
    for d in dirs:
        for ext in exts:
            cand = os.path.join(d, f"{name}.{ext}")
            if os.path.isfile(cand):
                return cand
    return ""


def sound_enabled():
    return os.environ.get("COPILOT_NOTIFY_SOUND", "1").lower() not in (
        "0", "false", "no", "off")


# ── delivery backends ───────────────────────────────────────────────
def _spawn(cmd):
    """Fire-and-forget a detached child; never block the hook."""
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    except Exception:
        pass


def deliver_macos(spec):
    app_bin = os.path.join(HOME_DIR, "platform", "macos",
                           "Promptring.app", "Contents", "MacOS", "promptring")
    delivered = False
    if os.path.exists(app_bin):
        _spawn([app_bin, "--title", spec["title"],
                "--subtitle", spec["subtitle"], "--message", spec["body"]])
        delivered = True
        # iTerm bonus: bounce the dock to grab attention.
        if os.environ.get("TERM_PROGRAM") == "iTerm.app":
            pty = _macos_find_pty()
            if pty and pty != "/dev/tty":
                try:
                    with open(pty, "w") as fh:
                        fh.write("\033]1337;RequestAttention=yes\033\\")
                except Exception:
                    pass
    if sound_enabled() and spec["sound_file"]:
        _spawn(["afplay", spec["sound_file"]])
    return delivered


def _powershell_exe():
    """Path to Windows PowerShell 5.1 (has the WinRT toast projection).
    On Windows prefer System32; on WSL use the interop powershell.exe."""
    if IS_WINDOWS:
        cand = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                            "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
        return cand if os.path.exists(cand) else "powershell.exe"
    if IS_WSL:
        for p in ("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
                  "powershell.exe"):
            if p == "powershell.exe" or os.path.exists(p):
                return p
    return ""


def _winpath(path):
    """Translate a path to a Windows path when on WSL (no-op on Windows)."""
    if IS_WSL and path:
        out = _run(["wslpath", "-w", path]).strip()
        return out or path
    return path


def deliver_windows(spec, bridge=False):
    ps = _powershell_exe()
    if not ps:
        return False
    toast = os.path.join(HOME_DIR, "platform", "windows", "toast.ps1")
    if bridge:
        # WSL: assets live on the Windows side; resolve the bridge install.
        win_home = _bridge_win_home()
        if win_home:
            toast = win_home + r"\platform\windows\toast.ps1"
    args = [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", toast,
            "-Title",    spec["title"],
            "-Subtitle", spec["subtitle"],
            "-Body",     spec["body"],
            "-Status",   spec["status"],
            "-Label",    spec.get("label") or "",
            "-Icon",     _winpath(spec["icon"]),
            "-Aumid",    AUMID]
    sound = spec["sound_file"]
    if bridge and sound:
        sound = _bridge_win_home() + r"\sounds\\" + os.path.basename(sound)
    elif sound:
        sound = _winpath(sound)
    if sound and sound_enabled():
        args += ["-Sound", sound]
    _spawn(args)
    return True


def _bridge_win_home():
    """Windows-side install root used by the WSL bridge."""
    env = os.environ.get("PROMPTRING_WIN_HOME")
    if env:
        return env
    up = _run([_powershell_exe(), "-NoProfile", "-Command", "$env:USERPROFILE"]).strip()
    if up:
        return up + r"\.copilot\promptring"
    return ""


def deliver_linux(spec):
    delivered = False
    if _which("notify-send"):
        body = spec["body"]
        # notify-send: arg1=summary, arg2=body. Fold subtitle into the body.
        full_body = spec["subtitle"]
        if body:
            full_body = full_body + "\n" + body if full_body else body
        cmd = ["notify-send", "-a", "promptring",
               "-i", spec["icon"], spec["title"], full_body]
        _spawn(cmd)
        delivered = True
    if sound_enabled() and spec["sound_file"]:
        for player in ("paplay", "aplay", "canberra-gtk-play"):
            if _which(player):
                if player == "canberra-gtk-play":
                    _spawn([player, "-f", spec["sound_file"]])
                else:
                    _spawn([player, spec["sound_file"]])
                break
    return delivered


def _which(name):
    from shutil import which
    return which(name)


def deliver(spec):
    if IS_MACOS:
        return deliver_macos(spec)
    if IS_WINDOWS:
        return deliver_windows(spec)
    if IS_WSL:
        return deliver_windows(spec, bridge=True)
    if IS_LINUX:
        return deliver_linux(spec)
    return False


# ── main ────────────────────────────────────────────────────────────
def main(argv):
    if len(argv) < 2 or not argv[1]:
        return 0
    key = argv[1]
    message = argv[2] if len(argv) > 2 else ""
    payload = read_payload()
    folder, summary, last_msg = enrich(payload)
    label = session_label(folder)
    # agentStop fires "done" on every turn-end; if the agent actually closed
    # by asking the user for direction, deliver it as an input request instead.
    if key == "done" and not message and autoinput_enabled() and is_input_request(last_msg):
        key = "input"
    spec = compose(key, message, label, summary)
    if os.environ.get("PROMPTRING_DRYRUN", "").lower() in ("1", "true", "yes"):
        spec["platform"] = ("macos" if IS_MACOS else "windows" if IS_WINDOWS
                            else "wsl" if IS_WSL else "linux" if IS_LINUX else "unknown")
        print(json.dumps(spec, ensure_ascii=False))
        return 0
    deliver(spec)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception:
        sys.exit(0)   # never fail the calling turn

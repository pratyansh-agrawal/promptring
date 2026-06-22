#!/usr/bin/env python3
"""
promptring — hook context enricher.

The Copilot CLI pipes a JSON payload to a command hook's STDIN, e.g. for
`agentStop`:  {"cwd","sessionId","transcriptPath","stopReason",...}

This reads that payload and prints two lines to STDOUT:

    <folder>     # the working-folder name  (basename of cwd)
    <summary>    # the agent's last message, one line, truncated

`copilot-notify` uses <folder> only as a fallback label when the real
terminal tab title can't be resolved. Either line may be empty. Always
exits 0 and never raises — notifications must never fail the calling turn.
"""
import sys, os, json, glob, re, time, datetime

MAX = 140  # max summary length
MIN_MEANINGFUL = 12  # shorter cleaned lines are treated as lead-ins/labels

# When the calling agent has just finished a turn, the final assistant.message
# may not yet be flush-visible to this separately-spawned reader process — most
# notably on WSL, where writes from the Linux CLI propagate to a concurrent
# reader with a small delay (or the last line is read mid-write). Without this,
# the notification shows the *previous* turn's message. When wait=True we briefly
# poll until the newest message belongs to the turn that just ended.
WAIT_DEADLINE_S = 1.5     # hard cap on added latency (never hang the hook)
WAIT_STEP_S = 0.1
FRESH_WINDOW_MS = 2000    # a turn's final message lands within ~2s of its stop


def _clean_md(line):
    """Strip common markdown so a line reads as plain prose."""
    s = line.strip()
    s = re.sub(r"^>\s?", "", s)                   # blockquote
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)  # [text](url) -> text
    s = s.replace("**", "").replace("__", "").replace("`", "")
    s = re.sub(r"(?<![\w*_])[*_](?=\S)", "", s)   # stray emphasis markers
    s = re.sub(r"^#{1,6}\s+", "", s)              # ATX headings
    s = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+", "", s)  # list markers / "1." "1)"
    s = re.sub(r"\s+", " ", s).strip()
    return s


def summarize(text):
    """Pick the first substantive sentence, skipping headings/lead-ins.

    A leading line such as "Two things:" or a markdown heading is a poor
    summary, so we skip lines that end with ':' or are very short when a
    more substantial line follows.
    """
    text = (text or "").strip()
    if not text:
        return ""
    text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)  # drop code fences
    lines = [c for c in (_clean_md(l) for l in text.splitlines()) if c]
    if not lines:
        return ""
    chosen = ""
    for i, line in enumerate(lines):
        is_leadin = line.endswith(":") or len(line) < MIN_MEANINGFUL
        if is_leadin and i + 1 < len(lines):
            continue
        chosen = line
        break
    if not chosen:
        chosen = lines[0]
    if len(chosen) > MAX:
        chosen = chosen[: MAX - 1].rstrip() + "…"
    return chosen


def _parse_iso_ms(s):
    """ISO-8601 timestamp (e.g. '2026-06-20T13:18:18.708Z') -> epoch ms, or None."""
    if not s:
        return None
    try:
        s = s.strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return int(datetime.datetime.fromisoformat(s).timestamp() * 1000)
    except Exception:
        return None


def _scan_file(path):
    """(content, ts_ms) of the last parseable assistant.message in `path`.

    Returns ('', None) if none. A final line that fails to parse (a torn,
    mid-flush write) is ignored — the loop simply keeps the last clean message,
    and the caller's wait loop will re-read once the write completes."""
    content, ts_ms = "", None
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                s = ln.strip()
                if not s or '"assistant.message"' not in s:
                    continue
                try:
                    obj = json.loads(s)
                except Exception:
                    continue
                if obj.get("type") == "assistant.message":
                    c = (obj.get("data") or {}).get("content")
                    if c:
                        content = c
                        ts_ms = _parse_iso_ms(obj.get("timestamp"))
    except Exception:
        return "", None
    return content, ts_ms


def _read_freshest(paths):
    """Freshest (content, ts_ms) across candidate files, chosen by timestamp.

    Picking by timestamp (rather than the first file that has any content) means
    that if one source lags behind another, we still surface the newest message."""
    best = ("", None)
    for p in paths:
        if not p or not os.path.isfile(p):
            continue
        c, ts = _scan_file(p)
        if not c:
            continue
        if best[1] is None or (ts is not None and ts > best[1]):
            best = (c, ts)
    return best


def last_assistant_message(transcript_path, session_id, trigger_ts_ms=None, wait=False):
    """Return the content of the final assistant.message in the transcript.

    `trigger_ts_ms` is the agentStop trigger time (epoch ms). With `wait=True`,
    the reader briefly polls until it sees a message from the turn that just
    ended — fixing the WSL case where the latest message isn't yet flush-visible
    and the previous turn's message would otherwise be shown."""
    paths = []
    if transcript_path:
        paths.append(transcript_path)
    if session_id:
        home = os.path.expanduser("~")
        paths.append(os.path.join(
            home, ".copilot", "session-state", session_id, "events.jsonl"))
    # de-dupe (the agentStop payload's transcriptPath is usually events.jsonl)
    seen, uniq = set(), []
    for p in paths:
        key = os.path.abspath(p) if p else p
        if key in seen:
            continue
        seen.add(key)
        uniq.append(p)
    paths = uniq

    try:
        trigger_ts_ms = int(trigger_ts_ms) if trigger_ts_ms is not None else None
    except Exception:
        trigger_ts_ms = None

    content, ts_ms = _read_freshest(paths)
    if not wait or trigger_ts_ms is None:
        return content

    def _fresh(ts):
        return ts is not None and (trigger_ts_ms - ts) <= FRESH_WINDOW_MS

    deadline = time.monotonic() + WAIT_DEADLINE_S
    while not _fresh(ts_ms) and time.monotonic() < deadline:
        time.sleep(WAIT_STEP_S)
        c, t = _read_freshest(paths)
        if c:
            content, ts_ms = c, t
    return content


def _is_wsl():
    try:
        with open("/proc/version", encoding="utf-8", errors="replace") as f:
            return "microsoft" in f.read().lower()
    except Exception:
        return False


def main():
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    payload = {}
    if raw.strip():
        try:
            payload = json.loads(raw)
        except Exception:
            payload = {}

    cwd = payload.get("cwd") or ""
    session_id = payload.get("session_id") or payload.get("sessionId") or ""
    transcript = payload.get("transcript_path") or payload.get("transcriptPath") or ""

    tab = os.path.basename(cwd.rstrip("/")) if cwd else ""
    summary = summarize(last_assistant_message(
        transcript, session_id,
        trigger_ts_ms=payload.get("timestamp"), wait=_is_wsl()))

    print(tab)
    print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # never fail the hook
        print("")
        print("")

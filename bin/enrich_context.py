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
import sys, os, json, glob, re

MAX = 140  # max summary length
MIN_MEANINGFUL = 12  # shorter cleaned lines are treated as lead-ins/labels


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


def last_assistant_message(transcript_path, session_id):
    """Return the content of the final assistant.message in the transcript."""
    paths = []
    if transcript_path:
        paths.append(transcript_path)
    if session_id:
        home = os.path.expanduser("~")
        paths.append(os.path.join(
            home, ".copilot", "session-state", session_id, "events.jsonl"))
    for p in paths:
        try:
            if not p or not os.path.isfile(p):
                continue
            last = ""
            with open(p, encoding="utf-8", errors="replace") as fh:
                for ln in fh:
                    ln = ln.strip()
                    if not ln or '"assistant.message"' not in ln:
                        continue
                    try:
                        obj = json.loads(ln)
                    except Exception:
                        continue
                    if obj.get("type") == "assistant.message":
                        content = (obj.get("data") or {}).get("content")
                        if content:
                            last = content
            if last:
                return last
        except Exception:
            continue
    return ""


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
    summary = summarize(last_assistant_message(transcript, session_id))

    print(tab)
    print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # never fail the hook
        print("")
        print("")

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


def first_line(text):
    text = (text or "").strip()
    if not text:
        return ""
    # collapse to a single tidy line
    line = text.splitlines()[0].strip()
    line = re.sub(r"\s+", " ", line)
    if len(line) > MAX:
        line = line[: MAX - 1].rstrip() + "…"
    return line


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
    summary = first_line(last_assistant_message(transcript, session_id))

    print(tab)
    print(summary)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # never fail the hook
        print("")
        print("")

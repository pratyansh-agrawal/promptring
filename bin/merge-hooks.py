#!/usr/bin/env python3
"""promptring — idempotent hook merger.

Adds or removes promptring's notification hooks inside a JSON hooks file
shaped like  {"version"?: N, "hooks": {"<event>": [ <entry>, ... ]}}  —
e.g. the Copilot CLI's ~/.copilot/hooks/hooks.json — WITHOUT touching any
hook the user already defined.

    merge-hooks.py add    <target.json> <source.json>
    merge-hooks.py remove <target.json>

Our entries are identified by the command substring MARKER, so:
  • add    — strips any previous promptring entries, then appends the
             current ones (idempotent: re-running never duplicates and
             always refreshes paths). The user's own hooks are preserved.
  • remove — deletes only our entries; the file is removed entirely only
             if it held nothing but our hooks.

A .bak backup is written before any change. A pre-existing target that is
not valid JSON is left untouched (we refuse rather than clobber).
"""
import sys, os, json, shutil

MARKER = "promptring/bin/copilot-notify"

# Substrings that identify a hook entry as ours, across platforms and across
# upgrades from older entrypoints. Matched against an entry's bash / command /
# powershell value so re-install is idempotent and `remove` strips only ours.
MARKERS = (
    "promptring/bin/promptring",     # current — bash/Linux/macOS/WSL
    "promptring\\bin\\promptring",   # current — Windows (PowerShell, backslashes)
    "promptring-win",                # legacy Windows port
    "promptring/bin/copilot-notify", # legacy macOS entrypoint
    "copilot-notify.ps1",            # legacy Windows entrypoint
)


def _entry_cmd(entry):
    if not isinstance(entry, dict):
        return ""
    return entry.get("bash") or entry.get("command") or entry.get("powershell") or ""


def _is_ours(entry):
    cmd = _entry_cmd(entry)
    return any(m in cmd for m in MARKERS)


def _load(path):
    """Return the parsed dict, or {} if the file is missing/empty.

    Raises ValueError if the file exists with non-JSON or non-object
    content, so callers can refuse to overwrite a user's file.
    """
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        text = fh.read().strip()
    if not text:
        return {}
    data = json.loads(text)  # may raise ValueError
    if not isinstance(data, dict):
        raise ValueError("top-level JSON is not an object")
    return data


def _backup(path):
    if os.path.exists(path):
        try:
            shutil.copy2(path, path + ".bak")
        except Exception:
            pass


def _write(path, doc):
    # Never write through a symlink (older installs may have symlinked the
    # target into the repo) — replace it with a real, standalone file.
    if os.path.islink(path):
        try:
            os.unlink(path)
        except Exception:
            pass
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")


def do_add(target, source):
    src = _load(source)
    src_hooks = src.get("hooks")
    if not isinstance(src_hooks, dict):
        raise ValueError("source has no hooks object")
    doc = _load(target)
    if "version" in src and "version" not in doc:
        doc["version"] = src["version"]
    hooks = doc.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
        doc["hooks"] = hooks
    for event, entries in src_hooks.items():
        if not isinstance(entries, list):
            continue
        current = hooks.get(event)
        current = [e for e in current if not _is_ours(e)] if isinstance(current, list) else []
        current.extend(entries)
        hooks[event] = current
    _backup(target)
    _write(target, doc)


def do_remove(target):
    if not os.path.exists(target):
        return
    doc = _load(target)
    hooks = doc.get("hooks")
    if not isinstance(hooks, dict):
        return
    for event in list(hooks.keys()):
        entries = hooks.get(event)
        if not isinstance(entries, list):
            continue
        kept = [e for e in entries if not _is_ours(e)]
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    _backup(target)
    other_keys = [k for k in doc if k not in ("version", "hooks")]
    if not hooks and not other_keys:
        if os.path.islink(target):
            try:
                os.unlink(target)
                return
            except Exception:
                pass
        try:
            os.remove(target)
        except Exception:
            pass
        return
    _write(target, doc)


def main(argv):
    if len(argv) < 3:
        print("usage: merge-hooks.py add <target> <source> | remove <target>",
              file=sys.stderr)
        return 2
    mode, target = argv[1], argv[2]
    try:
        if mode == "add":
            if len(argv) < 4:
                print("merge-hooks: add requires <source>", file=sys.stderr)
                return 2
            do_add(target, argv[3])
        elif mode == "remove":
            do_remove(target)
        else:
            print(f"merge-hooks: unknown mode {mode!r}", file=sys.stderr)
            return 2
    except ValueError as e:
        print(f"merge-hooks: {target} is not valid promptring-mergeable JSON "
              f"({e}); left untouched", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"merge-hooks: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

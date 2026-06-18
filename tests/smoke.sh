#!/usr/bin/env bash
# promptring smoke test — macOS & Linux (and WSL).
#
# Fires every notification category through the real orchestrator and
# asserts it exits cleanly and resolves the expected delivery backend.
# By default it runs in DRYRUN (no banners shown, just the composed spec).
# Pass --live to show real banners + sounds.
#
#   tests/smoke.sh          # dry run: assert compose + platform dispatch
#   tests/smoke.sh --live   # actually pop banners for each category
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PR="$REPO/bin/promptring.py"
LIVE=0
[ "${1:-}" = "--live" ] && LIVE=1

cats="done input ready blocked info"
fail=0

case "$(uname -s)" in
  Darwin) want="macos" ;;
  Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then want="wsl"; else want="linux"; fi ;;
  *)      want="unknown" ;;
esac
echo "platform: expecting backend '$want'"

for c in $cats; do
  if [ "$LIVE" = "1" ]; then
    python3 "$PR" "$c" "smoke: $c" ; rc=$?
    [ $rc -eq 0 ] && echo "  ✓ $c  (live, exit 0)" || { echo "  ✗ $c  exit $rc"; fail=1; }
    sleep 1
  else
    out="$(PROMPTRING_DRYRUN=1 python3 "$PR" "$c" "smoke: $c")" ; rc=$?
    if [ $rc -ne 0 ]; then echo "  ✗ $c  exit $rc"; fail=1; continue; fi
    got="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["platform"])' 2>/dev/null)"
    body="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["body"])' 2>/dev/null)"
    if [ "$got" = "$want" ] && [ "$body" = "smoke: $c" ]; then
      echo "  ✓ $c  → $got"
    else
      echo "  ✗ $c  backend='$got' body='$body'"; fail=1
    fi
  fi
done

# unknown category must still degrade gracefully (exit 0)
PROMPTRING_DRYRUN=1 python3 "$PR" "made-up" "x" >/dev/null 2>&1 \
  && echo "  ✓ unknown-category degrades" || { echo "  ✗ unknown-category failed"; fail=1; }

[ $fail -eq 0 ] && echo "smoke: PASS" || echo "smoke: FAIL"
exit $fail

#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  promptring — installer
# ════════════════════════════════════════════════════════════════════
#  1. Builds the Promptring.app notification agent (signed .app bundle —
#     the only thing that shows banners reliably from any terminal).
#  2. Registers it with LaunchServices so macOS grants it a notification
#     identity (appears in System Settings → Notifications).
#  3. Symlinks the notifier + config into ~/.copilot/notify so this repo
#     stays the single source of truth (edit here, changes apply live).
#  4. Installs the Copilot CLI notification hook (deterministic firing on
#     the CLI's own events — no dependence on the model).
#
#  Idempotent: re-running just refreshes everything in place.
#
#  Usage:   ./install.sh
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── pretty output helpers ───────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'
  C=$'\033[36m'; X=$'\033[0m'
else
  B=''; DIM=''; G=''; Y=''; C=''; X=''
fi
step()  { printf '\n%s▸ %s%s\n' "$B$C" "$1" "$X"; }
ok()    { printf '  %s✓%s %s\n' "$G" "$X" "$1"; }
warn()  { printf '  %s!%s %s\n' "$Y" "$X" "$1"; }
info()  { printf '  %s%s%s\n'   "$DIM" "$1" "$X"; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_DIR="$HOME/.copilot"
NOTIFY_DIR="$COPILOT_DIR/notify"
INSTRUCTIONS="$COPILOT_DIR/copilot-instructions.md"
HOOKS_SRC="$REPO/hooks.json"
HOOKS_DST="$COPILOT_DIR/hooks/hooks.json"
APP="$REPO/app/Promptring.app"
APP_BIN="$APP/Contents/MacOS/promptring"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

printf '%s' "$B$C"
cat <<'BANNER'
  ┌─────────────────────────────────┐
  │   promptring 🔔  ·  installer    │
  └─────────────────────────────────┘
BANNER
printf '%s' "$X"
info "repo: $REPO"

# ── 1. build the notification agent app ─────────────────────────────
step "Building Promptring.app (notification agent)"
if [ "$(uname -s)" != "Darwin" ]; then
  warn "Not macOS — skipping app build. Bell/OSC fallback will be used."
elif bash "$REPO/app/build.sh" >/dev/null 2>&1; then
  ok "built  → $APP"
else
  warn "Build failed. Ensure Xcode Command Line Tools are installed:"
  info "    xcode-select --install"
  info "Continuing — bell/OSC fallback will be used until the app builds."
fi

# ── 2. register the app with LaunchServices ─────────────────────────
if [ -x "$APP_BIN" ] && [ -x "$LSREGISTER" ]; then
  step "Registering app with LaunchServices"
  "$LSREGISTER" -f "$APP" 2>/dev/null || true
  ok "registered com.promptring.notifier"
fi

# ── 3. link the helper + config ─────────────────────────────────────
step "Linking notifier into ~/.copilot/notify"
mkdir -p "$NOTIFY_DIR/bin"
ln -sf "$REPO/bin/copilot-notify" "$NOTIFY_DIR/bin/copilot-notify"
ln -sf "$REPO/categories.conf"    "$NOTIFY_DIR/categories.conf"
chmod +x "$REPO/bin/copilot-notify"
ok "linked → $NOTIFY_DIR/bin/copilot-notify"
ok "linked → $NOTIFY_DIR/categories.conf"
info "sounds + app resolved from the repo via real-path resolution"

# ── 4. install the notification hook (deterministic firing) ─────────
#  Copilot CLI reads ~/.copilot/hooks/hooks.json on every session start
#  and fires our notifier directly on its own events — no dependence on
#  the model remembering to run a command.
#    • agentStop                       → copilot-notify done
#    • notification permission_prompt  → copilot-notify input
#    • notification elicitation_dialog → copilot-notify input
step "Installing Copilot CLI notification hook"
if [ -L "$HOOKS_DST" ] || [ ! -e "$HOOKS_DST" ]; then
  mkdir -p "$(dirname "$HOOKS_DST")"
  ln -sf "$HOOKS_SRC" "$HOOKS_DST"
  ok "linked → $HOOKS_DST"
else
  warn "$HOOKS_DST exists (not a promptring symlink) — left untouched."
  info "Merge the hooks from $HOOKS_SRC into it manually."
fi

# ── 5. remove any obsolete promptring instruction block ─────────────
#  The hook supersedes the old instruction-based firing; leaving the
#  block in would double-fire, so strip it.
if [ -e "$INSTRUCTIONS" ] && grep -qF "promptring:start" "$INSTRUCTIONS"; then
  awk '
    index($0, "promptring:start") { skip = 1; next }
    skip && index($0, "promptring:end") { skip = 0; next }
    skip { next }
    { print }
  ' "$INSTRUCTIONS" > "$INSTRUCTIONS.tmp" && mv "$INSTRUCTIONS.tmp" "$INSTRUCTIONS"
  if [ ! -s "$INSTRUCTIONS" ] || ! grep -q '[^[:space:]]' "$INSTRUCTIONS"; then
    rm -f "$INSTRUCTIONS"
    info "removed obsolete instruction block (file emptied → deleted)"
  else
    info "removed obsolete instruction block (kept your other content)"
  fi
fi

# ── done ────────────────────────────────────────────────────────────
printf '\n%s✓ promptring installed%s\n' "$B$G" "$X"
cat <<EOF

${B}Next steps${X}
  ${DIM}1.${X} Fire a test banner:
       ${C}$NOTIFY_DIR/bin/copilot-notify done "promptring works"${X}
  ${DIM}2.${X} First time only: macOS shows a ${B}Promptring${X} permission prompt → ${B}Allow${X},
       then set its alert style to ${B}Banners${X} in System Settings → Notifications.
  ${DIM}3.${X} Restart your Copilot CLI session so the hook loads.

${DIM}Don't move the cloned folder after install — live paths symlink into it.${X}
EOF

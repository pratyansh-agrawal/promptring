#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  promptring — installer
# ════════════════════════════════════════════════════════════════════
#  1. Copies the notifier, config and sound into ~/.copilot/promptring and
#     builds the Promptring.app notification agent there (a signed .app —
#     the only thing that shows banners reliably from any terminal).
#  2. Registers the app with LaunchServices so macOS grants it a
#     notification identity (appears in System Settings → Notifications).
#  3. Installs the Copilot CLI notification hook into ~/.copilot/hooks.
#
#  Everything lives under ~/.copilot, so the clone is no longer needed
#  after install — you can delete or move it freely.
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
HOME_DIR="$COPILOT_DIR/promptring"          # self-contained install home
INSTRUCTIONS="$COPILOT_DIR/copilot-instructions.md"
HOOKS_SRC="$REPO/hooks.json"
HOOKS_DST="$COPILOT_DIR/hooks/hooks.json"
APP="$HOME_DIR/app/Promptring.app"
APP_BIN="$APP/Contents/MacOS/promptring"
LEGACY_NOTIFY="$COPILOT_DIR/notify"         # pre-1.x symlink location
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

printf '%s' "$B$C"
cat <<'BANNER'
  ┌─────────────────────────────────┐
  │   promptring 🔔  ·  installer    │
  └─────────────────────────────────┘
BANNER
printf '%s' "$X"
info "repo: $REPO"

# ── 1. copy the runtime into ~/.copilot/promptring ─────────────────
step "Installing into $HOME_DIR"
rm -rf "$HOME_DIR"
mkdir -p "$HOME_DIR/app"
cp -R "$REPO/bin"            "$HOME_DIR/bin"
cp -R "$REPO/sounds"         "$HOME_DIR/sounds"
cp    "$REPO/categories.conf" "$HOME_DIR/categories.conf"
cp    "$REPO/app/build.sh" "$REPO/app/Info.plist" "$REPO/app/icon.png" "$HOME_DIR/app/"
cp -R "$REPO/app/src"        "$HOME_DIR/app/src"
chmod +x "$HOME_DIR/bin/copilot-notify" "$HOME_DIR/bin/enrich-context.py" "$HOME_DIR/app/build.sh"
ok "copied notifier + config + sound"

# ── 2. build the notification agent app (in place) ──────────────────
step "Building Promptring.app (notification agent)"
if [ "$(uname -s)" != "Darwin" ]; then
  warn "Not macOS — skipping app build. Bell/OSC fallback will be used."
elif bash "$HOME_DIR/app/build.sh" >/dev/null 2>&1; then
  ok "built  → $APP"
else
  warn "Build failed. Ensure Xcode Command Line Tools are installed:"
  info "    xcode-select --install"
  info "Continuing — bell/OSC fallback will be used until the app builds."
fi

# ── 3. register the app with LaunchServices ─────────────────────────
if [ -x "$APP_BIN" ] && [ -x "$LSREGISTER" ]; then
  step "Registering app with LaunchServices"
  "$LSREGISTER" -f "$APP" 2>/dev/null || true
  ok "registered com.promptring.notifier"
fi

# ── 4. install the notification hook ────────────────────────────────
#  Copilot CLI reads ~/.copilot/hooks/hooks.json on every session start
#  and fires the notifier directly on its own events — no dependence on
#  the model remembering to run a command.
#    • agentStop                       → copilot-notify done
#    • notification permission_prompt  → copilot-notify input
#    • notification elicitation_dialog → copilot-notify input
step "Installing Copilot CLI notification hook"
mkdir -p "$(dirname "$HOOKS_DST")"
if [ ! -e "$HOOKS_DST" ] || [ -L "$HOOKS_DST" ] || grep -q "copilot-notify" "$HOOKS_DST" 2>/dev/null; then
  rm -f "$HOOKS_DST"
  cp "$HOOKS_SRC" "$HOOKS_DST"
  ok "installed → $HOOKS_DST"
else
  warn "$HOOKS_DST exists with other hooks — left untouched."
  info "Merge the hooks from $HOOKS_SRC into it manually."
fi

# ── 5. clean up legacy install (pre-1.x symlink layout) ─────────────
if [ -d "$LEGACY_NOTIFY" ]; then
  rm -rf "$LEGACY_NOTIFY"
  info "removed legacy ~/.copilot/notify (symlink layout)"
fi

# ── 6. remove any obsolete promptring instruction block ─────────────
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
       ${C}$HOME_DIR/bin/copilot-notify done "promptring works"${X}
  ${DIM}2.${X} First time only: macOS shows a ${B}Promptring${X} permission prompt → ${B}Allow${X},
       then set its alert style to ${B}Banners${X} in System Settings → Notifications.
  ${DIM}3.${X} Restart your Copilot CLI session so the hook loads.

${DIM}Everything lives under ~/.copilot/promptring now — you can safely delete or move this clone.${X}
EOF

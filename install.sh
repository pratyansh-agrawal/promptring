#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  promptring — installer  (macOS · Linux · WSL)
# ════════════════════════════════════════════════════════════════════
#  Copies the cross-platform notifier into ~/.copilot/promptring and wires
#  it into the Copilot CLI hooks (your existing hooks are preserved).
#
#  One Python orchestrator (bin/promptring.py) drives every OS; only the
#  delivery is native:
#    • macOS — builds + registers the signed Promptring.app (banners from
#      any terminal) and plays the chime via afplay.
#    • Linux — delivers via notify-send (libnotify) + paplay/aplay.
#    • WSL   — sets up a bridge to the Windows toast (a real Windows banner
#      from inside WSL), since WSL has no notification daemon of its own.
#
#  Everything lives under ~/.copilot/promptring, so the clone can be
#  deleted or moved afterward. Idempotent: re-running refreshes in place.
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
INSTRUCTIONS_BLOCK="$REPO/copilot-instructions.block.md"
HOOKS_SRC="$REPO/hooks.json"
HOOKS_DST="$COPILOT_DIR/hooks/hooks.json"
LEGACY_NOTIFY="$COPILOT_DIR/notify"
LEGACY_WIN="$COPILOT_DIR/promptring-win"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
AUMID="com.promptring.notifier"

# ── detect platform ─────────────────────────────────────────────────
OS="$(uname -s)"
IS_WSL=0
if [ "$OS" = "Linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1
fi

printf '%s' "$B$C"
cat <<'BANNER'
  ┌─────────────────────────────────┐
  │   promptring 🔔  ·  installer    │
  └─────────────────────────────────┘
BANNER
printf '%s' "$X"
info "repo: $REPO"
case "$OS" in
  Darwin) info "platform: macOS" ;;
  Linux)  [ "$IS_WSL" = 1 ] && info "platform: WSL (Windows bridge)" || info "platform: Linux" ;;
  *)      warn "platform: $OS (unsupported — bell/OSC fallback only)" ;;
esac

# ── python3 is required (single orchestrator) ───────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  warn "python3 not found — promptring's orchestrator requires it."
  info "Install python3 and re-run. (macOS: 'xcode-select --install'; Debian/Ubuntu: 'sudo apt install python3')"
  exit 1
fi

# ── 1. copy the runtime into ~/.copilot/promptring ──────────────────
step "Installing into $HOME_DIR"
rm -rf "$HOME_DIR"
mkdir -p "$HOME_DIR/app"
cp -R "$REPO/bin"            "$HOME_DIR/bin"
cp -R "$REPO/sounds"         "$HOME_DIR/sounds"
cp -R "$REPO/platform"       "$HOME_DIR/platform"
cp    "$REPO/categories.conf" "$HOME_DIR/categories.conf"
cp    "$REPO/app/icon.png" "$REPO/app/icon.svg" "$HOME_DIR/app/"
find "$HOME_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
chmod +x "$HOME_DIR/bin/promptring.py" "$HOME_DIR/bin/enrich_context.py" \
         "$HOME_DIR/bin/merge-hooks.py" "$HOME_DIR/platform/macos/build.sh" 2>/dev/null || true
ok "copied orchestrator + config + sound + platform backends"

# ── 2. platform-specific delivery setup ─────────────────────────────
if [ "$OS" = "Darwin" ]; then
  step "Building Promptring.app (notification agent)"
  if bash "$HOME_DIR/platform/macos/build.sh" >/dev/null 2>&1; then
    APP="$HOME_DIR/platform/macos/Promptring.app"
    ok "built  → $APP"
    if [ -x "$APP/Contents/MacOS/promptring" ] && [ -x "$LSREGISTER" ]; then
      step "Registering app with LaunchServices"
      "$LSREGISTER" -f "$APP" 2>/dev/null || true
      ok "registered $AUMID"
    fi
  else
    warn "Build failed. Ensure Xcode Command Line Tools are installed:"
    info "    xcode-select --install"
    info "Continuing — bell/OSC fallback will be used until the app builds."
  fi

elif [ "$IS_WSL" = 1 ]; then
  step "Setting up the WSL → Windows toast bridge"
  if command -v powershell.exe >/dev/null 2>&1; then
    WIN_USERPROFILE="$(powershell.exe -NoProfile -Command '$env:USERPROFILE' 2>/dev/null | tr -d '\r')"
    if [ -n "$WIN_USERPROFILE" ]; then
      WIN_HOME_WSL="$(wslpath "$WIN_USERPROFILE" 2>/dev/null)/.copilot/promptring"
      mkdir -p "$WIN_HOME_WSL/platform/windows" "$WIN_HOME_WSL/app" "$WIN_HOME_WSL/sounds"
      cp -R "$HOME_DIR/platform/windows/." "$WIN_HOME_WSL/platform/windows/"
      cp    "$HOME_DIR/app/icon.png"       "$WIN_HOME_WSL/app/"
      cp -R "$HOME_DIR/sounds/."           "$WIN_HOME_WSL/sounds/"
      # register the toast app identity (name + horn icon) on the Windows side
      WIN_ICON="$(wslpath -w "$WIN_HOME_WSL/app/icon.png" 2>/dev/null)"
      powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
        \$k='HKCU:\\Software\\Classes\\AppUserModelId\\$AUMID';
        if (-not (Test-Path \$k)) { New-Item -Path \$k -Force | Out-Null }
        New-ItemProperty -Path \$k -Name 'DisplayName' -Value 'promptring' -PropertyType String -Force | Out-Null
        New-ItemProperty -Path \$k -Name 'IconUri' -Value '$WIN_ICON' -PropertyType String -Force | Out-Null
      " >/dev/null 2>&1 || true
      ok "bridge installed → $WIN_HOME_WSL"
      info "promptring runs the Windows toast via powershell.exe from inside WSL."
    else
      warn "Could not resolve the Windows user profile; bridge not set up."
    fi
  else
    warn "powershell.exe not reachable from WSL — cannot bridge to Windows toasts."
    info "Ensure WSL interop is enabled (default)."
  fi

elif [ "$OS" = "Linux" ]; then
  step "Checking Linux notification stack"
  if command -v notify-send >/dev/null 2>&1; then
    ok "notify-send found"
  else
    warn "notify-send not found — banners won't show until you install it."
    info "Debian/Ubuntu: sudo apt install libnotify-bin   ·   Fedora: sudo dnf install libnotify"
  fi
  if command -v paplay >/dev/null 2>&1 || command -v aplay >/dev/null 2>&1; then
    ok "audio player found (paplay/aplay)"
  else
    info "No paplay/aplay found — the chime will be skipped (banner still shows)."
  fi
fi

# ── 3. merge the Copilot CLI notification hooks ─────────────────────
#  Non-destructive: our entries are added/refreshed while any hooks you
#  already defined are preserved. Re-running never duplicates.
step "Installing Copilot CLI notification hooks"
mkdir -p "$(dirname "$HOOKS_DST")"
if python3 "$HOME_DIR/bin/merge-hooks.py" add "$HOOKS_DST" "$HOOKS_SRC"; then
  ok "merged hooks → $HOOKS_DST (your existing hooks preserved)"
else
  warn "$HOOKS_DST could not be merged (not valid JSON?) — left untouched."
  info "Merge the hooks from $HOOKS_SRC into it manually."
fi

# ── 4. clean up legacy installs ─────────────────────────────────────
[ -d "$LEGACY_NOTIFY" ] && { rm -rf "$LEGACY_NOTIFY"; info "removed legacy ~/.copilot/notify"; }
[ -d "$LEGACY_WIN" ]    && { rm -rf "$LEGACY_WIN";    info "removed legacy ~/.copilot/promptring-win"; }

# ── 5. install the promptring instruction block ─────────────────────
#  The hooks cover permission_prompt, elicitation_dialog and agentStop, but
#  the Copilot CLI fires NO hookable event when the agent pauses mid-turn on
#  the built-in `ask_user` tool — so under `--yolo` a decision/direction
#  prompt shows no banner and the user can't tell the agent is waiting. We
#  close that gap by instructing the agent to fire the notifier itself right
#  before it calls `ask_user`. The block is fenced by markers so it can be
#  refreshed or removed cleanly without disturbing your other instructions,
#  and its text is the single shared source in copilot-instructions.block.md.
step "Installing promptring instruction block"
mkdir -p "$(dirname "$INSTRUCTIONS")"
[ -e "$INSTRUCTIONS" ] || : > "$INSTRUCTIONS"
# strip any previous promptring block, preserving your other content
awk '
  index($0, "promptring:start") { skip = 1; next }
  skip && index($0, "promptring:end") { skip = 0; next }
  skip { next }
  { print }
' "$INSTRUCTIONS" > "$INSTRUCTIONS.tmp" && mv "$INSTRUCTIONS.tmp" "$INSTRUCTIONS"
# drop trailing blank lines so the appended block sits cleanly
awk 'NF{p=NR} {a[NR]=$0} END{for(i=1;i<=p;i++) print a[i]}' \
  "$INSTRUCTIONS" > "$INSTRUCTIONS.tmp" && mv "$INSTRUCTIONS.tmp" "$INSTRUCTIONS"
[ -s "$INSTRUCTIONS" ] && printf '\n' >> "$INSTRUCTIONS"
cat "$INSTRUCTIONS_BLOCK" >> "$INSTRUCTIONS"
ok "instruction block written → $INSTRUCTIONS"

# ── done ────────────────────────────────────────────────────────────
printf '\n%s✓ promptring installed%s\n' "$B$G" "$X"
cat <<EOF

${B}Next steps${X}
  ${DIM}1.${X} Fire a test banner:
       ${C}$HOME_DIR/bin/promptring.py done "promptring works"${X}
  ${DIM}2.${X} Restart your Copilot CLI session so the hook loads.
EOF
if [ "$OS" = "Darwin" ]; then
  cat <<EOF
  ${DIM}·${X} First time only: macOS shows a ${B}Promptring${X} permission prompt → ${B}Allow${X},
       then set its alert style to ${B}Banners${X} in System Settings → Notifications.
EOF
fi
printf '\n%sEverything lives under ~/.copilot/promptring now — you can delete or move this clone.%s\n' "$DIM" "$X"

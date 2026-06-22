#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  promptring — one-line installer  (macOS · Linux · WSL)
# ════════════════════════════════════════════════════════════════════
#  Usage:
#    curl -fsSL https://pratyansh-agrawal.github.io/promptring/install.sh | bash
#
#  Downloads the latest promptring source into a temp directory and runs the
#  real installer — no manual clone required. The temp checkout is removed
#  afterward; the install itself lives in ~/.copilot/promptring.
#
#  Pin a branch/tag with PROMPTRING_REF, or point at a custom archive with
#  PROMPTRING_TARBALL:
#    curl -fsSL .../install.sh | PROMPTRING_REF=v1.0 bash
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

REPO_SLUG="pratyansh-agrawal/promptring"
REF="${PROMPTRING_REF:-main}"
TARBALL="${PROMPTRING_TARBALL:-https://github.com/${REPO_SLUG}/archive/refs/heads/${REF}.tar.gz}"

say() { printf '\033[1;36m▸ %s\033[0m\n' "$1"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v tar >/dev/null 2>&1 || die "tar is required but was not found."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/promptring.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Downloading promptring ($REF)…"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$TARBALL" | tar -xz -C "$TMP" \
    || die "download/extract failed. Check your network or PROMPTRING_REF."
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "$TARBALL" | tar -xz -C "$TMP" \
    || die "download/extract failed. Check your network or PROMPTRING_REF."
else
  die "need curl or wget to download promptring."
fi

SRC="$(find "$TMP" -maxdepth 1 -type d -name 'promptring-*' | head -n1)"
[ -n "${SRC:-}" ] && [ -f "$SRC/install.sh" ] \
  || die "downloaded archive is missing install.sh."

say "Running installer…"
bash "$SRC/install.sh" "$@"

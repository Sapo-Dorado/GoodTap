#!/usr/bin/env bash
# deploy.sh — Deploy GoodTap to the Hetzner server
#
# Usage:
#   ./scripts/deploy.sh [server-ip]
#
# If server-ip is not provided, reads GOODTAP_SERVER from environment.
#
# How it works:
#   SSHes into the server and runs nixos-rebuild there, pointing at the GitHub
#   repo with --refresh to bypass Nix's tarball cache (default TTL is 1 hour).
#   This avoids needing nixos-rebuild installed locally (it's a NixOS-only tool).
#
# Prerequisites:
#   - SSH key access to root@server
#   - The server is already running NixOS (use nixos-anywhere for first install)
#   - Your changes are pushed to GitHub

set -euo pipefail

SERVER="${1:-${GOODTAP_SERVER:-}}"

if [[ -z "$SERVER" ]]; then
  echo "Usage: $0 <server-ip>"
  echo "   or: GOODTAP_SERVER=<ip> $0"
  exit 1
fi

# Determine the current git remote URL to build from
FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_URL="$(git -C "$FLAKE_DIR" remote get-url origin 2>/dev/null || true)"
CURRENT_BRANCH="$(git -C "$FLAKE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

# Convert SSH remote (git@github.com:user/repo.git) to nix flake URL
if [[ "$REMOTE_URL" =~ git@github\.com:(.+)\.git ]]; then
  GITHUB_REPO="${BASH_REMATCH[1]}"
  FLAKE_REF="github:${GITHUB_REPO}/${CURRENT_BRANCH}"
elif [[ "$REMOTE_URL" =~ https://github\.com/(.+)\.git ]]; then
  GITHUB_REPO="${BASH_REMATCH[1]}"
  FLAKE_REF="github:${GITHUB_REPO}/${CURRENT_BRANCH}"
else
  echo "Warning: could not parse GitHub remote from: $REMOTE_URL"
  echo "Using flake ref: github:Sapo-Dorado/GoodTap/main"
  FLAKE_REF="github:Sapo-Dorado/GoodTap/main"
fi

# Check for unpushed commits
UNPUSHED="$(git -C "$FLAKE_DIR" log "origin/${CURRENT_BRANCH}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$UNPUSHED" -gt 0 ]]; then
  echo "WARNING: You have $UNPUSHED unpushed commit(s). Push first or the server will build the old version."
  echo "  git push"
  echo ""
  read -r -p "Continue anyway? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

echo "==> Deploying $FLAKE_REF to root@$SERVER"
echo "    (nixos-rebuild runs on the server; --refresh bypasses GitHub tarball cache)"
echo ""

# Run nixos-rebuild on the server itself.
# --refresh forces Nix to re-check GitHub even if the tarball was cached recently.
# -t (allocate TTY) so nixos-rebuild can show progress output.
ssh -t "root@${SERVER}" \
  "nixos-rebuild switch --flake '${FLAKE_REF}#goodtap' --refresh"

echo ""
echo "==> Deploy complete!"
echo ""
GOODTAP_BIN="$(ssh "root@${SERVER}" "systemctl cat goodtap | grep '^ExecStart=' | sed 's/ExecStart=//;s/ start$//'")"
echo "To seed the database (fetches from Scryfall):"
echo "  ssh root@${SERVER} 'export \$(cat /etc/goodtap/secrets | xargs); DATABASE_URL=ecto://goodtap@localhost/goodtap PHX_HOST=goodtap.in PORT=4000 ${GOODTAP_BIN} eval \"Goodtap.Release.seed()\"'"

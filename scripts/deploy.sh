#!/usr/bin/env bash
# deploy.sh — Deploy GoodTap to the Hetzner server
#
# Usage:
#   ./scripts/deploy.sh [server-ip]
#
# If server-ip is not provided, reads GOODTAP_SERVER from environment.
#
# How it works:
#   nixos-rebuild evaluates the flake from this LOCAL checkout (no caching
#   issues), then SSH-copies the result and activates it on the remote.
#   --build-host=server means the Linux server builds its own closure, which
#   avoids cross-compilation issues from macOS.
#
# Prerequisites:
#   - SSH key access to root@server
#   - Nix installed locally (for flake evaluation)
#   - The server is already running NixOS (use nixos-anywhere for first install)

set -euo pipefail

SERVER="${1:-${GOODTAP_SERVER:-}}"

if [[ -z "$SERVER" ]]; then
  echo "Usage: $0 <server-ip>"
  echo "   or: GOODTAP_SERVER=<ip> $0"
  exit 1
fi

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Deploying from $FLAKE_DIR to root@$SERVER"
echo "    (build happens on the server, no macOS→Linux cross-compile needed)"
echo ""

# --fast            skip rebuilding the nix binary itself (required from macOS)
# --build-host      build the closure on the remote Linux server
# --target-host     activate the new generation on this host
# --use-remote-sudo not needed for root, but harmless

nixos-rebuild switch \
  --flake "${FLAKE_DIR}#goodtap" \
  --fast \
  --build-host "root@${SERVER}" \
  --target-host "root@${SERVER}"

echo ""
echo "==> Deploy complete!"
echo ""
echo "To seed the database (first deploy or card data update):"
echo "  ssh root@${SERVER} goodtap eval 'Goodtap.Release.seed()'"

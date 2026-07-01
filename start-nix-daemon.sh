#!/bin/bash
# Idempotently start nix-daemon in the background.
#
# Run by postStartCommand in devcontainer.json on every container start.
# Required because the Determinate Systems installer is configured with
# --init none (no systemd inside the container), so nothing else
# supervises the daemon.
#
# Safe to invoke repeatedly: a running daemon is detected and skipped.

set -euo pipefail

DAEMON=/nix/var/nix/profiles/default/bin/nix-daemon
LOG=/var/log/nix-daemon.log

if [ ! -x "$DAEMON" ]; then
    echo "[start-nix-daemon] $DAEMON not found, skipping" >&2
    exit 0
fi

if pgrep -x nix-daemon >/dev/null 2>&1; then
    exit 0
fi

touch "$LOG" 2>/dev/null || true
nohup "$DAEMON" >>"$LOG" 2>&1 &
disown || true

#!/usr/bin/env bash
set -euo pipefail

host="${1:-codex@8.134.70.237}"
command -v ssh >/dev/null || { echo 'OpenSSH client is required.' >&2; exit 127; }

ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes "$host" '
  set -eu
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI: unavailable"
    if command -v systemctl >/dev/null 2>&1; then
      printf "Docker service: "
      systemctl is-active docker 2>/dev/null || true
    fi
    exit 127
  fi
  if command -v systemctl >/dev/null 2>&1; then
    printf "Docker service: "
    systemctl is-active docker || true
  fi
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
'

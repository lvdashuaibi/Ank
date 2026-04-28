#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.server.pid" ]]; then
  kill "$(cat "$ROOT_DIR/.server.pid")" || true
  rm -f "$ROOT_DIR/.server.pid"
fi

if [[ -f "$ROOT_DIR/.client.pid" ]]; then
  kill "$(cat "$ROOT_DIR/.client.pid")" || true
  rm -f "$ROOT_DIR/.client.pid"
fi

docker compose -f "$ROOT_DIR/docker-compose.dev.yml" stop postgres || true

echo "[ank] local processes stopped"

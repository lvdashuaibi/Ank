#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[ank] starting local postgres"
docker compose -f "$ROOT_DIR/docker-compose.dev.yml" up -d postgres

echo "[ank] starting server on :8080"
(
  cd "$ROOT_DIR/server"
  STORE_DRIVER=postgres \
  AUTO_MIGRATE=true \
  DATABASE_URL='postgres://flashcard:flashcard@localhost:5432/flashcard?sslmode=disable' \
  go run ./cmd/server
) &
SERVER_PID=$!

echo "[ank] starting flutter web on :3100"
(
  cd "$ROOT_DIR/client"
  flutter run -d web-server \
    --web-hostname 127.0.0.1 \
    --web-port 3100 \
    --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
) &
CLIENT_PID=$!

echo "$SERVER_PID" > "$ROOT_DIR/.server.pid"
echo "$CLIENT_PID" > "$ROOT_DIR/.client.pid"

echo "[ank] server pid: $SERVER_PID"
echo "[ank] client pid: $CLIENT_PID"
echo "[ank] web preview: http://127.0.0.1:3100/"
wait

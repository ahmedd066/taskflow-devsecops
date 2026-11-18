#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${SCRIPT_DIR}/backend"
FRONTEND_DIR="${SCRIPT_DIR}/frontend"

BACKEND_IMAGE="url-shortener-backend:local"
FRONTEND_IMAGE="url-shortener-frontend:local"

log() {
  printf '[build-test] %s\n' "$*"
}

log_error() {
  printf '[build-test] ERROR: %s\n' "$*" >&2
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_error "Required command not found: ${cmd}"
    exit 1
  fi
}

for tool in node npm docker; do
  require_command "${tool}"
done

if ! docker compose version >/dev/null 2>&1; then
  log_error "Required command not found: docker compose"
  exit 1
fi

log "Installing backend dependencies..."
(
  cd "${BACKEND_DIR}"
  npm ci
)

log "Running Jest unit tests with coverage..."
(
  cd "${BACKEND_DIR}"
  npm test
)

log "Building backend Docker image..."
docker build -t "${BACKEND_IMAGE}" "${BACKEND_DIR}"

log "Building frontend Docker image..."
docker build -t "${FRONTEND_IMAGE}" "${FRONTEND_DIR}"

log "Starting the stack with docker compose..."
docker compose up -d

log "Validating backend health endpoint..."
for i in $(seq 1 30); do
  if curl --no-verbose --tries=1 --spider http://localhost:3000/health >/dev/null 2>&1; then
    log "Backend is healthy."
    break
  fi
  if [ "${i}" -eq 30 ]; then
    log_error "Backend did not become healthy in time."
    docker compose logs backend || true
    exit 1
  fi
  sleep 2
done

log "Validating frontend is reachable..."
for i in $(seq 1 30); do
  if curl --no-verbose --tries=1 --spider http://localhost:8080/ >/dev/null 2>&1; then
    log "Frontend is reachable."
    break
  fi
  if [ "${i}" -eq 30 ]; then
    log_error "Frontend did not become reachable in time."
    docker compose logs frontend || true
    exit 1
  fi
  sleep 2
done

log "Build, test, and stack startup completed successfully."
log "Backend:  http://localhost:3000"
log "Frontend: http://localhost:8080"

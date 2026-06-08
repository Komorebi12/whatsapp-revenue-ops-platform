#!/usr/bin/env bash
set -euo pipefail

FORCE=0
SKIP_BUILD=0
SKIP_RAG_SEED=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --skip-rag-seed) SKIP_RAG_SEED=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT/deploy"

if [ "$FORCE" -ne 1 ]; then
  echo "This will run docker compose down -v and remove local demo volumes."
  printf "Continue? Type RESET to proceed: "
  read -r answer
  if [ "$answer" != "RESET" ]; then
    echo "Demo reset cancelled."
    exit 0
  fi
fi

docker compose down -v

if [ "$SKIP_BUILD" -eq 1 ]; then
  docker compose up -d
else
  docker compose up -d --build
fi

wait_for_http() {
  local name="$1"
  local url="$2"
  for _ in $(seq 1 40); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "$name ready"
      return 0
    fi
    sleep 3
  done
  echo "$name was not ready after waiting" >&2
  return 1
}

wait_for_http "rag-api" "http://localhost:8000/health"
wait_for_http "n8n" "http://localhost:5678/healthz"

if [ "$SKIP_RAG_SEED" -ne 1 ]; then
  "$PROJECT_ROOT/scripts/seed-rag-knowledge.sh"
fi

"$PROJECT_ROOT/scripts/health-check.sh"
"$PROJECT_ROOT/scripts/simulate-rag-query.sh" "What is your return policy?" >/dev/null
"$PROJECT_ROOT/scripts/simulate-message.sh" "I want pricing for your CRM automation product" >/dev/null

echo "Demo reset complete."

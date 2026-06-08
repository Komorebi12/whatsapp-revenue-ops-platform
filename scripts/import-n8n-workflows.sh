#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../deploy"

if [[ -d n8n/credentials ]]; then
  docker compose exec -T n8n n8n import:credentials --separate --input=/credentials
fi

docker compose exec -T n8n n8n import:workflow --separate --input=/workflows

if [[ "${1:-}" != "--no-activate" ]]; then
  for workflow_file in ../deploy/n8n/workflows/*.json; do
    workflow_id="$(node -e "console.log(require(process.argv[1]).id)" "$workflow_file")"
    docker compose exec -T n8n n8n publish:workflow --id="$workflow_id"
  done
fi

echo "n8n workflows imported"

if [[ "${2:-}" != "--no-restart" && "${1:-}" != "--no-restart" ]]; then
  docker compose restart n8n
fi

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT/deploy"

check_http() {
  local name="$1"
  local url="$2"
  local level="${3:-alive}"
  curl -fsS "$url" >/dev/null
  echo "$name [$level]: ok"
}

check_http "ghl-mock" "http://localhost:8090/health"
check_http "sales-agent" "http://localhost:8020/health"
check_http "ghl-sync" "http://localhost:8010/health"
check_http "qdrant" "http://localhost:6333/"
check_http "rag-api" "http://localhost:8000/health"
check_http "n8n" "http://localhost:5678/healthz"

docker compose exec -T postgres pg_isready -U postgres -d revenue_ops >/dev/null
echo "postgres revenue_ops [alive]: ok"

docker compose exec -T postgres pg_isready -U postgres -d n8n_metadata >/dev/null
echo "postgres n8n_metadata [alive]: ok"

n8n_tables="$(docker compose exec -T postgres psql -U postgres -d revenue_ops -tAc "select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('workflow_entity', 'execution_entity', 'credentials_entity');" | tr -d '[:space:]')"
if [ "$n8n_tables" != "0" ]; then
  echo "n8n metadata tables found in revenue_ops" >&2
  exit 1
fi
echo "postgres revenue_ops isolation [ready]: ok"

workflow_count="$(docker compose exec -T postgres psql -U postgres -d n8n_metadata -tAc "select count(*) from workflow_entity where name in ('wf_phase1a_whatsapp_inbound', 'wf_console_staff_reply');" | tr -d '[:space:]')"
if [ "$workflow_count" -lt 2 ]; then
  echo "expected workflows were not imported into n8n_metadata" >&2
  exit 1
fi
echo "n8n workflows [configured]: ok - count=$workflow_count"

collection_json="$(curl -fsS http://localhost:8000/collection)"
vectors="$(printf '%s' "$collection_json" | sed -n 's/.*"vectors":[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
if [ -z "$vectors" ] || [ "$vectors" -le 0 ]; then
  echo "rag collection has no vectors" >&2
  exit 1
fi
echo "rag collection [ready]: ok - vectors=$vectors"

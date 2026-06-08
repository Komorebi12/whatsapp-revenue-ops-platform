#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../deploy"
docker compose exec -T postgres psql -U postgres -d revenue_ops -f /docker-entrypoint-initdb.d/00_schema.sql
docker compose exec -T postgres psql -U postgres -d revenue_ops -f /docker-entrypoint-initdb.d/01_seed.sql

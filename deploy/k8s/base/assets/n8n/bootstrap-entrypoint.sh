#!/bin/sh
set -eu

echo "[phase2] waiting for postgres n8n_metadata"
attempt=1
while ! node -e "const net=require('net'); const socket=net.createConnection({host: process.env.DB_POSTGRESDB_HOST || 'postgres', port: Number(process.env.DB_POSTGRESDB_PORT || 5432)}, () => { socket.end(); process.exit(0); }); socket.setTimeout(1000, () => { socket.destroy(); process.exit(1); }); socket.on('error', () => process.exit(1));" >/dev/null 2>&1; do
  if [ "$attempt" -ge 30 ]; then
    echo "[phase2] postgres n8n_metadata was not ready after ${attempt} attempts" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 2
done

if [ -d /credentials ]; then
  echo "[phase1c] importing n8n credentials from /credentials"
  n8n import:credentials --separate --input=/credentials || {
    echo "[phase2] credential import failed, retrying once"
    sleep 2
    n8n import:credentials --separate --input=/credentials
  }
fi

echo "[phase1c] importing n8n workflows from /workflows"
n8n import:workflow --separate --input=/workflows || {
  echo "[phase2] workflow import failed, retrying once"
  sleep 2
  n8n import:workflow --separate --input=/workflows
}

echo "[phase1c] activating imported n8n workflows"
for workflow_file in /workflows/*.json; do
  workflow_id="$(node -e "console.log(require(process.argv[1]).id)" "$workflow_file")"
  if [ -n "$workflow_id" ]; then
    n8n publish:workflow --id="$workflow_id"
  fi
done

echo "[phase1c] starting n8n"
exec n8n start

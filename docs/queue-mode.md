# Queue Mode

This document describes the optional Docker Compose queue-mode overlay for the local self-hosted n8n reference stack.

The default quickstart remains the single-process n8n stack in `deploy/docker-compose.yml`. Queue mode is opt-in through `deploy/docker-compose.queue.yml`.

## Start Queue Mode

Run from the repository root:

```powershell
docker compose --env-file .\deploy\.env.mock `
  -f .\deploy\docker-compose.yml -f .\deploy\docker-compose.queue.yml `
  up -d --build --scale n8n-worker=2
```

Then run the local smoke:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-queue-mode.ps1 -WorkerScale 2
```

The smoke script verifies:

- the rendered Compose config keeps the three n8n processes aligned on encryption key, Postgres metadata settings, Redis queue settings, timezone, and binary-data mode,
- the queue stack becomes healthy,
- the dedicated webhook processor on host port `5680` can return complete sales and mock-RAG responses,
- the shared `n8n_data` volume is writable from `n8n-webhook` and readable from `n8n-worker` at the binary-data path,
- Redis exposes queue-related keys after webhook requests, and
- worker logs contain execution evidence.

## Topology

| Process | Compose service | Host port | Responsibility |
|---|---|---:|---|
| Main | `n8n` | 5678 | UI, scheduling, metadata migrations, and bootstrap workflow import |
| Webhook processor | `n8n-webhook` | 5680 | Receives production-style webhook calls and waits for worker completion |
| Worker | `n8n-worker` | none | Executes queued workflow jobs; scalable with `--scale n8n-worker=N` |
| Queue broker | `redis` | none | BullMQ queue broker for n8n queue mode |

`5678` remains the main n8n UI and default single-process webhook endpoint. Queue-mode verification should send inbound workflow calls to `5680` so the request enters the dedicated webhook processor.

## Shared State

All n8n processes share:

- `N8N_ENCRYPTION_KEY`
- the same Postgres `n8n_metadata` database
- the same Redis queue broker
- `N8N_DEFAULT_BINARY_DATA_MODE=filesystem`
- `n8n_data:/home/node/.n8n`

The queue overlay shares the existing full `n8n_data:/home/node/.n8n` volume across main, webhook, and worker processes. This matches the official n8n Compose queue-mode example pattern.

This solves the actual filesystem problem: if a webhook receives binary media, the worker must be able to read the file that the webhook process wrote.

The design originally preferred a narrower `binaryData`-only named volume, but the n8n `2.17.6` image created that nested mount with ownership that prevented the `node` user from writing to `/home/node/.n8n/binaryData`. M2.2 therefore uses the documented fallback: full `.n8n` sharing, with the tradeoff that runtime config files are also shared. The webhook and worker still wait for the main process to become healthy, so metadata migrations and workflow import are completed before they start.

## Static Config Gate

The queue overlay is checked without starting containers:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-queue-config.ps1
```

This script uses `docker compose config --format json` and asserts that `n8n`, `n8n-webhook`, and `n8n-worker` render equivalent queue-critical environment variables. This catches drift that a plain `docker compose config --quiet` would miss.

The same script runs in CI as part of the `quick-gate` job.

## Redis Queue Evidence

`scripts/smoke-queue-mode.ps1` scans Redis after queue webhook requests and prints queue-like keys. Keep this evidence tied to local test output because the exact BullMQ key names are implementation details of n8n and may change across versions.

Last verified on n8n `2.17.6`:

```text
bull:jobs:id
bull:jobs:stalled-check
n8n:cache:webhook:POST-console/reply
n8n:cache:webhook:POST-twilio/whatsapp/inbound
n8n:cache:workflow-project
```

## Local Reset

The default scripts do not delete volumes automatically.

If you need to reset only the base local CI-smoke project state, use the project-scoped command:

```powershell
docker compose -p revenueops-ci --env-file .\deploy\.env.mock -f .\deploy\docker-compose.yml down -v
```

If you need to reset only the queue-mode project state, use:

```powershell
docker compose -p revenueops-queue --env-file .\deploy\.env.mock `
  -f .\deploy\docker-compose.yml -f .\deploy\docker-compose.queue.yml down -v
```

Avoid generic `docker volume prune` for this project. It does not target the Compose project precisely, and broad prune commands can remove unrelated local volumes.

## Production Notes

This is a local reference topology, not a production HA deployment.

For production multi-node deployments, filesystem binary data needs a storage layer that all n8n processes can read and write safely. In Kubernetes, that means a real shared storage class for this path or an n8n-supported external binary storage option. Queue scaling and autoscaling policy are intentionally out of scope for this M2.2 Compose baseline.

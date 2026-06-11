# Proposal Proof Points

Use this page as the public evidence index when sending the repository to a technical buyer. Each point is backed by files in this repository and stays within the public claims ledger.

## 1. Self-Hosted n8n Reference Stack

The repository defines an eight-service local stack around self-hosted n8n:

- `postgres`
- `n8n`
- `sales-agent`
- `ghl-sync`
- `ghl-mock`
- `rag-api`
- `qdrant`
- `operator-console`

Evidence:

- `deploy/docker-compose.yml`
- `README.md`
- `docs/architecture.md`
- `docs/architecture-diagram.mmd`

Pinned infrastructure images are `postgres:16`, `n8nio/n8n:2.17.6`, and `qdrant/qdrant:v1.18.0`.

## 2. Mock-First CRM And RAG Demo

The public default uses `deploy/.env.mock` and does not require real GoHighLevel, Twilio, Clerk, or Gemini credentials for the core demo paths. GoHighLevel calls are routed to `ghl-mock`, the sales-agent LLM path points at a mock Gemini-compatible endpoint, and the RAG API returns deterministic mock answers when `MOCK_MODE=true` and no Gemini key is configured.

Evidence:

- `deploy/.env.mock`
- `mock/ghl-mock-server/`
- `services/rag-api/app/services/mock_rag.py`
- `services/rag-api/tests/test_mock_mode.py`
- `scripts/simulate-message.ps1`
- `scripts/simulate-rag-query.ps1`

## 3. Workflow Reliability Signals

The n8n workflows include retry behavior, fallback response formatting, environment-based secret expressions, and parameterized Postgres writes. The console reply workflow validates an environment-provided webhook secret before inserting a staff reply with `queryReplacement`.

Evidence:

- `deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json`
- `deploy/n8n/workflows/wf_console_staff_reply.json`
- `scripts/verify-phase3-static.ps1`

## 4. Inspectable Operational Surface

The platform ships with health checks, reset scripts, inspection scripts, CI gates, and a claims ledger that keeps public statements tied to source evidence. Health output is organized by `[alive]`, `[configured]`, and `[ready]` diagnostics.

Evidence:

- `.github/workflows/ci.yml`
- `scripts/ci-smoke.ps1`
- `scripts/health-check.ps1`
- `scripts/demo-reset.ps1`
- `scripts/inspect-postgres.ps1`
- `scripts/inspect-n8n-executions.ps1`
- `docs/portfolio/claims-ledger.md`

## 5. Clean Public Release Boundary

The public repository is a clean reference implementation, not the historical development workspace. Internal AI coordination files, real env files, bundles, screenshots, videos, and local runtime artifacts are excluded from the public release tree.

Evidence:

- `docs/public-release-manifest.md`
- `.gitignore`
- `.dockerignore`
- `scripts/verify-standalone-release.ps1`

## License Boundary

This repository is an open reference implementation for self-hosting n8n. It does not relicense n8n, provide a hosted n8n SaaS, or resell n8n core functionality. n8n itself remains governed by n8n's own license terms, including the Sustainable Use License.

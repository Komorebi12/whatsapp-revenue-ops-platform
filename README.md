# WhatsApp Revenue Ops Platform

[![CI](https://github.com/Komorebi12/whatsapp-revenue-ops-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/Komorebi12/whatsapp-revenue-ops-platform/actions/workflows/ci.yml)

Open reference implementation for self-hosting n8n as the orchestration layer for a WhatsApp-style revenue operations stack.

This repository packages a local, reproducible platform that connects n8n workflows, FastAPI integration services, a mocked GoHighLevel CRM API, an AI sales-agent path, an optional RAG path, Postgres-backed audit data, Qdrant, and an optional operator console.

It is intentionally a reference implementation and portfolio asset, not a production SaaS. The public default is mock-first: no real GoHighLevel, Twilio, Clerk, or Gemini credentials are required for the core sales/CRM or mock RAG demo paths.

## What It Demonstrates

- **Self-hosted n8n orchestration:** inbound routing, API calls, fallback formatting, and console reply writes.
- **Mock-first CRM integration:** GHL-style contact, note, and opportunity lifecycle calls against `ghl-mock`.
- **AI sales automation pattern:** a FastAPI sales agent using a local mock Gemini-compatible endpoint for the default demo.
- **Postgres-backed auditability:** customers, tickets, messages, lead scores, event log, and n8n metadata isolation.
- **Operational reliability:** health checks, startup ordering, reset scripts, retries, fallback responses, parameterized SQL, and inspection scripts.
- **RAG workflow with honest mock mode:** deterministic mock answers by default, plus Qdrant-backed document retrieval and Gemini-based answers when a real Gemini key is supplied locally.

## Architecture

The Compose stack defines eight services:

| Service | Port | Role |
|---|---:|---|
| `postgres` | 5432 | Shared business database plus isolated n8n metadata database |
| `n8n` | 5678 | Workflow orchestration and webhook routing |
| `sales-agent` | 8020 | AI sales conversation and lead scoring API |
| `ghl-sync` | 8010 | CRM sync service pointed at the local GHL mock |
| `ghl-mock` | 8090 | Local mock for GoHighLevel and sales-agent Gemini-style calls |
| `operator-console` | 3000 | Optional Next.js operator console, enabled with the `console` profile |
| `rag-api` | 8000 | Optional RAG chat API built from the knowledge-base service |
| `qdrant` | 6333 | Vector database for seeded knowledge chunks |

Pinned infrastructure images:

- `postgres:16`
- `n8nio/n8n:2.17.6`
- `qdrant/qdrant:v1.18.0`

Architecture diagram: [docs/architecture-diagram.mmd](docs/architecture-diagram.mmd)

## Message Flow

```text
Simulated inbound message
  -> n8n webhook
  -> Route Intent code node
    -> Sales path: sales-agent -> postgres -> ghl-sync -> ghl-mock
    -> RAG path: rag-api -> mock answer, or qdrant + Gemini when real RAG is configured
  -> Fallback formatter if a downstream service is unavailable
```

Operator replies use a separate local workflow:

```text
operator-console
  -> n8n /webhook/console/reply
  -> Postgres parameterized insert into messages
```

## Quick Start: Mock-First Core Demo

Run commands from this project directory.

### 1. Create a local mock env

```powershell
Copy-Item .\deploy\.env.mock .\deploy\.env
```

`deploy/.env` is git-ignored and must never be committed. The committed `deploy/.env.mock` contains only local demo values and placeholders.

### 2. Start the core stack

```powershell
docker compose --env-file .\deploy\.env -f .\deploy\docker-compose.yml up -d --build
```

This starts the mock-first core services. The operator console is profile-gated because it needs Clerk keys.

To include the operator console after adding local Clerk test keys to `deploy/.env`:

```powershell
docker compose --env-file .\deploy\.env -f .\deploy\docker-compose.yml --profile console up -d --build
```

### 3. Check core health

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\health-check.ps1
```

The default health check verifies the mock-first core stack. It does not require a seeded RAG collection.

### 4. Run the sales path

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\simulate-message.ps1 -Message "I want pricing for your CRM automation product"
```

Expected result: a sales-agent reply with lead scoring metadata such as `qualification_tier`, plus mocked CRM sync activity visible in `ghl-mock`.

### 5. Inspect state

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\inspect-postgres.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\inspect-n8n-executions.ps1
```

### 6. Optional: test console reply writeback

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\simulate-console-reply.ps1 -BodyText "Thanks, an operator will follow up shortly."
```

Expected result: a parameterized insert into the `messages` table.

### 7. Optional: reset the local demo

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\demo-reset.ps1
```

The reset script intentionally clears local Compose volumes and asks for a `RESET` confirmation by default.

## RAG Path: Mock By Default, Real With Local Keys

The default mock-first path does not require a real Gemini key. With `MOCK_MODE=true` and an empty `GEMINI_API_KEY`, `rag-api` returns a deterministic mock answer and source chunk so the RAG workflow can be exercised without external services.

The real RAG seed/query path still uses Gemini embeddings and generation, so treat it as an optional real-LLM path.

1. Copy the real integration template:

```powershell
Copy-Item .\deploy\.env.real.example .\deploy\.env
```

2. Fill only local values in `deploy/.env`, including `GEMINI_API_KEY`.

3. Seed the knowledge base:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\seed-rag-knowledge.ps1
```

4. Run the stricter RAG readiness check:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\health-check.ps1 -RequireRagReady
```

5. Run a RAG query:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\simulate-rag-query.ps1 -Message "What is your return policy?"
```

## Environment Files

| File | Purpose | Public-safe |
|---|---|---:|
| `deploy/.env.mock` | Mock-first local demo values | Yes |
| `deploy/.env.example` | Public variable inventory with empty values | Yes |
| `deploy/.env.real.example` | Template for real local integrations | Yes |
| `deploy/.env` | Local-only runtime values | No |

Do not commit real keys, real CRM IDs, real database URLs, logs, screenshots with credentials, or customer data.
`deploy/n8n/credentials/phase1c_revenue_ops_postgres.json` is a local-only demo credential for the bundled Postgres service (`postgres/postgres`); it is not a production secret and keeps the imported n8n workflow bound to a working local database credential.

## Troubleshooting

- If your host has `http_proxy` or `https_proxy` configured, local `curl` checks can be routed through the proxy and fail with proxy errors. Use `curl --noproxy '*' ...` for local service calls, or temporarily unset proxy variables while running the demo.

## Security And Release Model

- This project must be published from a clean release tree, not from the historical private multi-project workspace.
- The safe publication path is: copy a clean subtree, exclude local secrets and generated data, run local scans, `git init`, then publish a clean initial commit.
- `deploy/.env`, `.env.real`, logs, bundles, local runtime data, and monorepo history must not enter the public release tree.
- Public demos and Upwork proposals should use mock-only data by default.
- Real integration testing belongs in local-only `deploy/.env` files and private runtime environments.

The public release policy is tracked in [docs/public-release-manifest.md](docs/public-release-manifest.md). Internal audit notes are not part of the public release tree.

## License Boundary

This repository's own code, documentation, manifests, scripts, and mock services are released under the MIT License in [LICENSE](LICENSE).

n8n itself is not part of this project's MIT license. The `n8nio/n8n` image, n8n product, n8n trademarks, and n8n core functionality remain governed by n8n's own license terms, including the Sustainable Use License. This repository is an open reference implementation for self-hosting n8n; it does not relicense n8n, provide a hosted n8n SaaS, or resell n8n core functionality.

## Portfolio Materials

- [Case study](docs/case-study.md)
- [Architecture diagram](docs/architecture-diagram.mmd)
- [Claims ledger](docs/portfolio/claims-ledger.md)
- [Proposal proof points](docs/proposal-packet/proof-points.md)
- [CI workflow](.github/workflows/ci.yml)

Demo script, video, and screenshots belong to the proposal packet and should be published only after a separate asset-sanitization review.

## Known Limitations

- Twilio is simulated with local scripts; this project does not use a live WhatsApp Business API number.
- GoHighLevel is represented by `ghl-mock`; no real GHL production API calls are made in the public demo path.
- Intent routing is keyword-based, not an LLM intent classifier.
- The default sales-agent path uses `ghl-mock` as a mock Gemini-compatible endpoint.
- The default RAG path returns a deterministic mock answer. Real document retrieval and generation require a local Gemini key.
- `revenue_events` are available as demo/seed data and schema groundwork, not a fully real-time revenue analytics feature.
- The operator console requires valid Clerk test keys when the `console` profile is used.
- The n8n demo environment allows workflow env access for local secret parameterization; production hardening should move this to a stricter credential model.

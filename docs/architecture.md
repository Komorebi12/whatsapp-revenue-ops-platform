# Architecture

This document describes the standalone public reference implementation for self-hosting n8n as the orchestration layer for a WhatsApp-style revenue operations workflow.

The stack is intentionally local and mock-first. It is designed to be inspectable, reproducible, and safe to run without real GoHighLevel, Twilio, Clerk, or Gemini credentials.

## Runtime Topology

The default Compose stack runs eight services on one Docker network:

| Service | Image or build source | Port | Responsibility |
|---|---|---:|---|
| `postgres` | `postgres:16` | 5432 | Business data plus a separate `n8n_metadata` database |
| `n8n` | `n8nio/n8n:2.17.6` | 5678 | Webhook routing, workflow orchestration, retries, and fallback formatting |
| `sales-agent` | `services/sales-agent` | 8020 | Sales conversation API, lead scoring, and CRM sync trigger |
| `ghl-sync` | `services/ghl-sync` | 8010 | GoHighLevel-style contact and opportunity sync API |
| `ghl-mock` | `mock/ghl-mock-server` | 8090 | Local mock for CRM calls and mock Gemini-style sales responses |
| `rag-api` | `services/rag-api` | 8000 | RAG chat API with mock-first fallback and optional real Gemini-backed retrieval |
| `qdrant` | `qdrant/qdrant:v1.18.0` | 6333 | Vector storage for the optional real RAG path |
| `operator-console` | `apps/operator-console` | 3000 | Optional Next.js operator console enabled by the `console` profile |

All custom service images build from paths inside this repository. No Docker build context depends on a sibling project or historical monorepo checkout.

## Default Message Flow

```text
simulate-message.ps1 or simulate-rag-query.ps1
  -> n8n webhook: /webhook/twilio/whatsapp/inbound
  -> Route Intent code node
    -> Sales path:
       sales-agent -> Postgres -> ghl-sync -> ghl-mock
    -> RAG path:
       rag-api -> mock response when MOCK_MODE=true and GEMINI_API_KEY is empty
       rag-api -> Qdrant + Gemini when real local credentials are configured
  -> n8n fallback formatter if a downstream service is unavailable
  -> Postgres audit tables
```

The default mock environment uses keyword routing inside the workflow. Messages containing policy, return, refund, FAQ, or similar terms route to the RAG path. Other messages route to the sales-agent path.

## Queue Mode Topology

`deploy/docker-compose.queue.yml` is an opt-in overlay for running n8n queue mode without changing the default quickstart.

In queue mode:

- the existing `n8n` service becomes the main process for UI, scheduling, metadata migrations, and bootstrap workflow import,
- `n8n-webhook` listens on host port `5680` and receives production-style webhook calls,
- `n8n-worker` executes queued jobs and can be scaled with `--scale n8n-worker=N`,
- `redis:7.2-alpine` is the local BullMQ broker, and
- all n8n processes share the same encryption key, Postgres metadata database, Redis broker, timezone, and filesystem binary-data mode.

The default single-process n8n endpoint stays on `5678`. Queue-mode tests intentionally call `5680` to prove the webhook processor and worker path.

The queue overlay shares the base `n8n_data:/home/node/.n8n` volume across main, webhook, and worker containers. A narrower `binaryData`-only mount was tested first, but n8n `2.17.6` created the nested volume with write permissions that blocked the `node` user. Full `.n8n` sharing is the local Docker Compose fallback and matches the official n8n Compose queue-mode example pattern. Production multi-node deployments need a storage layer that all n8n processes can safely read and write.

## Mock-First Design

The public default is `deploy/.env.mock`.

Key properties:

- `MOCK_MODE=true`
- `GEMINI_API_KEY=` is empty
- CRM traffic points to `ghl-mock`
- sales-agent LLM calls point to `ghl-mock`'s mock Gemini-compatible endpoint
- rag-api returns deterministic mock RAG answers when `MOCK_MODE=true` and no Gemini key is present

This keeps the default demo reproducible without external credentials while preserving an upgrade path for real local integrations.

## Optional Real RAG Path

The RAG API has two modes:

| Mode | Trigger | Behavior |
|---|---|---|
| Mock RAG | `MOCK_MODE=true` and empty `GEMINI_API_KEY` | Returns deterministic local answers and source chunks without embedding or vector storage |
| Real RAG | `GEMINI_API_KEY` is set in a local-only env file | Parses PDFs, embeds chunks with Gemini, stores vectors in Qdrant, and generates cited answers |

The mock answer is a demo fixture. Real document retrieval and generation require a local Gemini key and should use `deploy/.env.real.example` as the template.

## n8n Workflow Responsibilities

The bundled n8n workflows are imported by `deploy/n8n/bootstrap-entrypoint.sh`:

- `deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json`
- `deploy/n8n/workflows/wf_console_staff_reply.json`

The inbound workflow is responsible for:

- normalizing simulated inbound payloads
- routing intent to sales or RAG
- calling internal FastAPI services
- retrying downstream calls
- formatting fallback responses
- writing business events to Postgres with parameterized SQL

The console workflow is responsible for authenticated staff reply writeback into the `messages` table.

## Database Separation

Postgres hosts two logical databases:

- `revenue_ops`: business demo data, CRM sync events, messages, tickets, lead scores, and revenue events
- `n8n_metadata`: n8n workflow metadata, credentials metadata, and execution state

The health-check script verifies that n8n metadata tables do not appear in the business database.

## Startup And Health

Compose uses service health checks and `depends_on.condition: service_healthy` where startup order matters.

Important readiness checks:

- Postgres uses `pg_isready`
- n8n uses `/healthz`
- FastAPI services expose `/health`
- Qdrant is checked via TCP on port 6333
- `scripts/health-check.ps1` validates live HTTP endpoints, database isolation, imported workflows, and RAG dependency configuration

The default health check does not require a real Gemini key or a seeded vector collection. The stricter real-RAG check is available with `-RequireRagReady`.

## Release Model

The safe public release path is:

```text
source project tree
  -> sanitized final-clean tree
  -> fresh publish-local git repository
  -> local initial commit
  -> pre-push gate
  -> public remote only after Human approval
```

The public repository must not include:

- historical monorepo git history
- internal AI coordination files
- real `.env` files
- local runtime volumes
- screenshots or videos before separate asset review
- bundles or historical private release artifacts

See `docs/public-release-manifest.md` for the release include/exclude policy.

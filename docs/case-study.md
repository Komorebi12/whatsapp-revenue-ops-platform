# WhatsApp Revenue Ops Platform Case Study

## Problem

The starting point was a set of separate WhatsApp, AI, CRM, analytics, operator-console, and knowledge-base projects. Each project had a useful role, but there was no single local environment that could demonstrate the full revenue-ops journey from an inbound customer message to AI response, lead scoring, CRM sync behavior, and operational visibility.

The practical demo problem was not one missing feature. It was orchestration:

- Services were split across different projects and runtimes.
- The database model needed to be made consistent enough for local integration.
- n8n workflows needed a reproducible import and activation path.
- GoHighLevel integration needed to be demo-safe without real CRM credentials.
- RAG knowledge retrieval needed to plug into the same inbound path as sales conversations.
- Failure modes needed visible fallback behavior instead of silent workflow endings.

## Solution

The platform packages the required services into one local reference implementation. It uses Docker Compose, n8n workflow orchestration, Postgres seed data, a local GoHighLevel mock, and reproducible scripts to make the full demo run from one project directory.

Earlier integration work kept source projects read-only. The public-ready layout now vendors the runtime code under `services/` and `apps/` so the repository can build without sibling monorepo projects.

Key capabilities:

- One Compose environment defines the local demo topology.
- n8n routes inbound messages to either a sales path or a RAG knowledge path.
- The sales path calls a FastAPI sales agent, updates Postgres conversation state, and reaches a GHL sync adapter pointed at a local mock.
- The RAG path calls a FastAPI RAG API that returns deterministic mock answers by default, with an optional Qdrant and Gemini path for real local retrieval.
- Failure paths return friendly fallback responses for both RAG and sales-agent outages.
- Workflow secrets are parameterized through n8n environment expressions.
- Console reply writes use parameterized Postgres query replacements.
- Health checks and reset scripts make the demo reproducible.

## Architecture

The current demo topology has eight Compose services:

| Service | Port | Purpose |
|---|---:|---|
| `postgres` | 5432 | Business data and n8n metadata databases |
| `n8n` | 5678 | Webhook and workflow orchestration |
| `sales-agent` | 8020 | AI sales reply and lead scoring service |
| `ghl-sync` | 8010 | CRM sync adapter pointed at the local mock |
| `ghl-mock` | 8090 | Demo-safe GoHighLevel API mock |
| `operator-console` | 3000 | Optional operator UI behind the `console` profile |
| `rag-api` | 8000 | RAG chat API |
| `qdrant` | 6333 | Vector database for seeded knowledge chunks |

Diagram: [architecture-diagram.mmd](architecture-diagram.mmd)

### Sales Path

Sales-oriented messages are sent to the n8n webhook and classified by the `Route Intent` code node. The sales branch calls the `AI Sales Agent` HTTP node, which reaches `sales-agent:8020`. The sales agent writes conversation and lead scoring data into Postgres and can trigger the GHL sync adapter. The sync adapter is configured to call `ghl-mock:8090`, not a real GoHighLevel account.

The lead scoring model uses physical database fields such as `lead_scores.total_score`, `lead_scores.qualification_tier`, and `lead_scores.score_breakdown`.

### Knowledge Path

Information-seeking messages, such as return policy questions, are routed to the `RAG Knowledge API` node. In the public mock-first environment, that node calls `rag-api:8000` and receives a deterministic answer with source context from the bundled demo policy document. When a local Gemini key is supplied and the knowledge base is seeded, the same API can retrieve chunks from Qdrant collection `whatsapp_demo_knowledge` and generate a real answer.

### Fallback Path

Both RAG and sales-agent HTTP nodes use retry settings. If the service is unavailable or returns an unusable payload, the workflow continues into formatter nodes that produce user-facing fallback replies:

- RAG fallback: `Sorry, the knowledge service is temporarily unavailable. Please try again later.`
- Sales fallback: `Sorry, the sales assistant is temporarily unavailable. Please try again later.`

### Operator Reply Path

The optional operator console can post a staff reply to a separate n8n webhook. The workflow validates the request with an environment-provided secret and inserts an outbound staff message using Postgres `queryReplacement` parameters.

## Results

The integration reached a reproducible local demo state:

- The Compose stack defines eight services and pins core infrastructure images: `postgres:16`, `n8nio/n8n:2.17.6`, and `qdrant/qdrant:v1.18.0`.
- Health checks report service availability and readiness levels across `[alive]`, `[configured]`, and `[ready]` diagnostics.
- The default RAG demo query returns a deterministic mock policy answer sourced from `demo-company-policy.pdf`.
- With a local Gemini key, RAG seed loads the demo policy PDF into Qdrant collection `whatsapp_demo_knowledge`.
- A sales demo query returns a sales-agent reply with lead scoring metadata such as `qualification_tier`.
- RAG and sales failure paths have verified fallback responses.
- Console reply writeback uses parameterized SQL instead of string-concatenated SQL.
- A reset script can rebuild the local demo state, seed RAG data, run health checks, and run smoke tests.

## Known Limitations

This is a local portfolio demo, not a production deployment.

- Twilio is simulated through local scripts; no live WhatsApp Business API number is configured.
- GoHighLevel is mocked by `ghl-mock`; no real GHL production API calls are made.
- Intent routing is keyword-based and does not use an LLM classifier.
- `revenue_events` are present as schema and demo/seed data; real-time revenue visibility is deferred to a future route.
- The operator console requires valid Clerk test keys when the `console` profile is used.
- The n8n demo uses `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` to support environment-based secret expressions; a pre-production deployment should move to a stricter credential model.
- `NODE_FUNCTION_ALLOW_EXTERNAL="*"` remains a local-demo convenience and should be narrowed before production use.

## Evidence Sources

The claims above are mapped in [portfolio/claims-ledger.md](portfolio/claims-ledger.md). That ledger links external-facing statements to public source files such as `deploy/docker-compose.yml`, `deploy/init-db/00_schema.sql`, n8n workflow JSON, scripts, and docs.

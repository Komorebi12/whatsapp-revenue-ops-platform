# Claims Ledger

This file maps public-facing portfolio claims to source evidence. README, case study, and Upwork copy should not make stronger claims than the evidence below.

| Claim | Evidence | Notes / Limits |
|---|---|---|
| The project orchestrates a local WhatsApp revenue-ops demo with Docker Compose. | `deploy/docker-compose.yml`; `README.md`; `scripts/simulate-message.ps1` | Local demo only, not production SaaS. |
| The Compose file defines eight services. | `deploy/docker-compose.yml`; `README.md` service table | `operator-console` is profile-gated with `phase1b`. |
| Core pinned infrastructure images are `postgres:16`, `n8nio/n8n:2.17.6`, and `qdrant/qdrant:v1.18.0`. | `deploy/docker-compose.yml` | Other services are locally built from project Dockerfiles. |
| Inbound demo messages are simulated with scripts. | `scripts/simulate-message.ps1`; `scripts/simulate-rag-query.ps1` | No real Twilio Business API number is configured. |
| n8n performs keyword-based routing between RAG and sales paths. | `deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json` node `Route Intent` | Not an LLM intent classifier. |
| RAG messages call a RAG Knowledge API branch. | `deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json`; `scripts/simulate-rag-query.ps1`; `services/rag-api/app/services/mock_rag.py` | The public mock-first path returns a deterministic RAG answer without Gemini; real retrieval and generation require a local Gemini key. |
| Sales messages call an AI Sales Agent branch. | `deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json`; `services/sales-agent/app/`; `scripts/simulate-message.ps1`; `docs/assets/05-postgres-inspect.png` | Demo path returns lead scoring metadata. |
| RAG uses Qdrant and seeded PDF knowledge. | `deploy/docker-compose.yml`; `deploy/rag-seed/demo-company-policy.pdf`; `scripts/seed-rag-knowledge.ps1` | Seeded demo knowledge, not a management UI. |
| RAG and sales-agent HTTP nodes have retry behavior. | `deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json` | Retry settings are workflow-level evidence. |
| RAG and sales-agent outages return friendly fallback responses. | `deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json` | Failure-path demo should be re-run before a final public release claim. |
| Workflow secrets are parameterized through n8n environment expressions. | `deploy/n8n/workflows/*.json`; `deploy/docker-compose.yml`; `deploy/.env.example` | Local demo uses `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`. |
| Console reply writeback uses parameterized SQL. | `deploy/n8n/workflows/wf_console_staff_reply.json` | Uses `queryReplacement`; no SQL string concatenation claim beyond this workflow. |
| Lead scoring data uses `lead_scores.total_score`, `lead_scores.qualification_tier`, and `lead_scores.score_breakdown`. | `deploy/init-db/00_schema.sql`; `services/sales-agent/app/` | `score` and `tier` are business aliases only. |
| GoHighLevel is mocked locally. | `deploy/docker-compose.yml`; `mock/ghl-mock-server/`; `deploy/.env.mock` | No real GHL production calls in the public demo path. |
| `revenue_events` are available as schema and demo/seed data, not real-time revenue visibility. | `deploy/init-db/00_schema.sql`; `deploy/init-db/01_seed.sql` | Real-time revenue visibility is deferred. |
| Health checks include alive/configured/ready diagnostics. | `scripts/health-check.ps1`; `scripts/health-check.sh`; `docs/assets/02-health-check.png` | External docs should not claim monitoring/alerting. |
| A demo reset script can rebuild the local demo state. | `scripts/demo-reset.ps1`; `scripts/demo-reset.sh` | It clears local volumes and requires confirmation by default. |
| Operator console visibility is optional and requires Clerk test keys. | `deploy/docker-compose.yml`; `apps/operator-console/`; `README.md` | Profile-gated service; not required for core script demo. |
| Required runtime service code is included in the reference repo layout. | `services/sales-agent/`; `services/ghl-sync/`; `services/rag-api/`; `apps/operator-console/`; `scripts/verify-standalone-release.ps1` | Public release must still be created through a clean initial commit. |
| A narrated demo video can be attached to proposals as a separate asset. | Proposal packet asset review; `docs/portfolio/upwork-listing.md` | Video/screenshots and narration scripts must pass a separate sanitization review before public sharing. |

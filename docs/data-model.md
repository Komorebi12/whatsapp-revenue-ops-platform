# Data Model

This document describes the public standalone data model used by the local WhatsApp Revenue Ops Platform reference implementation.

The source of truth for table creation is `deploy/init-db/00_schema.sql`. Synthetic seed data lives in `deploy/init-db/01_seed.sql`.

## Database Layout

The Compose stack creates a Postgres service with a default `revenue_ops` database. The n8n bootstrap process creates and uses a separate `n8n_metadata` database for workflow metadata.

| Database | Purpose |
|---|---|
| `revenue_ops` | Business demo data: customers, messages, tickets, lead scores, CRM sync events, and revenue events |
| `n8n_metadata` | n8n internal metadata and execution state |

The separation is intentional. `scripts/health-check.ps1` verifies that n8n metadata tables are not created in `revenue_ops`.

## Core Entities

### Customer

Table: `customers`

Represents a synthetic WhatsApp contact in the demo.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | Primary key |
| `phone` | `text` | Unique customer phone value; demo data only |
| `display_name` | `text` | Optional display name |
| `first_seen_at` | `timestamptz` | First observed timestamp |
| `last_seen_at` | `timestamptz` | Last observed timestamp |
| `metadata_json` | `jsonb` | Demo metadata and extension point |

### Ticket

Table: `tickets`

Represents the operator-facing support or sales thread.

| Column | Type | Notes |
|---|---|---|
| `ticket_id` | `text` | Primary key, stable demo ticket id |
| `customer_id` | `uuid` | References `customers.id` |
| `intent` | `text` | Routed intent such as `purchase` or `information_query` |
| `status` | `text` | One of `open`, `closed`, `awaiting_staff`, `awaiting_customer`, `pending_reactivation`, `resolved`, `abandoned` |
| `subject` | `text` | Short summary label |
| `summary` | `text` | Human-readable thread summary |
| `context_json` | `jsonb` | Structured workflow context |
| `last_customer_message_at` | `timestamptz` | Latest customer message timestamp |
| `last_staff_reply_at` | `timestamptz` | Latest staff reply timestamp |

### Message

Table: `messages`

Stores customer and staff-visible message records.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | Primary key |
| `customer_id` | `uuid` | References `customers.id` |
| `ticket_id` | `text` | References `tickets.ticket_id` |
| `direction` | `text` | `inbound` or `outbound` |
| `channel` | `text` | Defaults to `whatsapp` |
| `provider` | `text` | Demo provider label |
| `provider_message_id` | `text` | Provider id, unique when present |
| `idempotency_key` | `text` | Optional duplicate-protection key |
| `sender_role` | `text` | `customer`, `system`, or `staff` |
| `body_text` | `text` | Message text |
| `payload_json` | `jsonb` | Raw or derived payload |

### Conversation State

Table: `conversation_states`

Tracks the sales-agent conversation stage for a customer.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | Primary key |
| `customer_id` | `uuid` | References `customers.id` |
| `stage` | `text` | Sales stage such as `qualification` |
| `qualification_data` | `jsonb` | Structured qualification fields |
| `context_summary` | `text` | Rolling conversation summary |
| `turn_count` | `integer` | Conversation turn count |

### Lead Score

Table: `lead_scores`

Stores sales qualification output.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` | Primary key |
| `customer_id` | `uuid` | References `customers.id` |
| `conversation_id` | `uuid` | References `conversation_states.id` |
| `total_score` | `integer` | Demo lead score |
| `score_breakdown` | `jsonb` | Component scoring details |
| `qualification_tier` | `text` | Example: `qualified` |
| `ghl_stage_synced` | `text` | Last CRM stage label synced by the demo |

### Revenue Event

Table: `revenue_events`

Provides an audit trail for business events emitted by the sales-agent and CRM sync paths.

| Column | Type | Notes |
|---|---|---|
| `id` | `bigserial` | Primary key |
| `idempotency_key` | `text` | Unique event key |
| `event_type` | `text` | Example: `lead_qualified` |
| `customer_id` | `uuid` | Customer reference |
| `conversation_id` | `uuid` | Optional conversation reference |
| `pipeline_stage` | `text` | Demo stage label |
| `lead_score` | `integer` | Score at event time |
| `qualification_tier` | `text` | Tier at event time |
| `metadata` | `jsonb` | Structured event metadata |

### Event Log

Table: `event_log`

Stores workflow and integration audit events used by the operator console and inspection scripts.

| Column | Type | Notes |
|---|---|---|
| `id` | `bigserial` | Primary key |
| `type` | `text` | Event type |
| `ticket_id` | `text` | Optional ticket reference |
| `customer_id` | `uuid` | Optional customer reference |
| `payload_json` | `jsonb` | Structured event payload |
| `created_at` | `timestamptz` | Event timestamp |

## Seed Dataset

The public seed file creates one synthetic customer, one ticket, one inbound message, one conversation state, one lead score, and one revenue event.

The fixed demo identifiers are intentionally synthetic and safe to publish. They are used by local scripts so repeated demos are deterministic.

## Operator Console Reads

The optional Next.js operator console reads the same `revenue_ops` database through Drizzle schema files under `apps/operator-console/src/lib/db`.

Primary read paths:

- ticket queue from `tickets` joined to `customers`
- ticket detail from `tickets`, `customers`, and `messages`
- activity views from `event_log`

The console reply action posts back to n8n, which writes a staff outbound message through the console reply workflow.

## RAG Data

The mock-first RAG path does not write embeddings or vectors. It returns deterministic demo answers and source chunks while `MOCK_MODE=true` and no Gemini key is configured.

The optional real RAG path uses:

- `deploy/rag-seed/demo-company-policy.pdf`
- `services/rag-api`
- `qdrant/qdrant:v1.18.0`
- a local-only Gemini key supplied via `deploy/.env`

When real RAG is enabled, uploaded PDF chunks are embedded and stored in Qdrant, not in Postgres.

## Idempotency And Safety Notes

- Seed SQL uses `on conflict` clauses so it can be rerun safely in a local demo.
- n8n workflow SQL writes use parameterized queries.
- Message rows can carry `idempotency_key` values for duplicate protection.
- Revenue events use `idempotency_key` as the unique event identity.
- Public data is synthetic demo data only.

# Upwork Portfolio Form Copy

Use this file for the Upwork **Add a new portfolio project** form. It is intentionally shorter than the case study and avoids repeating every internal evidence asset.

## Project Title

WhatsApp Revenue Ops: AI Sales Agent, Knowledge Base & CRM Workflow

## Your Role

Integration & Automation Developer

## Project Description

I built a local WhatsApp revenue-ops demo in Docker Compose. An inbound message hits n8n, gets classified by intent, and routes to either an AI sales agent with lead scoring or a knowledge-base API that answers from a seeded policy document.

The stack includes CRM sync mocking, an operator console, health checks, reset scripts, and retry/fallback handling so the demo stays reproducible and inspectable.

Scope: Twilio is simulated, GoHighLevel is mocked, and intent routing is keyword-based.

## Skills and Deliverables

Upwork allows 5 skills. Recommended:

1. Workflow Automation
2. API Integration
3. Python
4. Docker
5. PostgreSQL

Alternates if Upwork suggestions differ:

- n8n
- FastAPI
- CRM Automation
- RAG
- GoHighLevel
- AI Chatbot Development

## Upload Assets

Upload the final MP4 first:

- `docs/assets/phase4-demo/whatsapp-revenue-ops-platform-demo-phase4.mp4`

Then upload 4-5 screenshots, not the SVG/TXT evidence files:

1. `docs/assets/03-n8n-workflow.png`
2. `docs/assets/01-compose-ps.png`
3. `docs/assets/07-operator-console.png`
4. `docs/assets/05-postgres-inspect.png`
5. `docs/assets/02-health-check.png`

Optional screenshot if Upwork accepts more:

- `docs/assets/06-rag-query.png`
- `docs/assets/04-n8n-executions.png`

Do not upload:

- `*.svg`
- `*.txt`
- `*.srt`
- `narration.mp3`
- `overlay-filter.txt`
- `recording-script.md`
- internal review files

## Existing Upwork Portfolio Replacement Notes

This project should become the main WhatsApp / AI automation flagship item. It can replace or demote several older, narrower portfolio items.

Recommended replacement / demotion:

| Existing portfolio item | Recommendation | Reason |
|---|---|---|
| WhatsApp AI Sales Agent--Gemini+GoHighLevel CRM+n8n | Replace with this project | This project includes the sales agent, n8n routing, CRM sync mocking, lead scoring, observability, and demo hardening. |
| WhatsApp Support Workflow MVP | Replace with this project | This project includes the inbound workflow, routing, persistence, operator visibility, and fallback behavior. |
| WhatsApp Support->GoHighLevel CRM: Real-Time Contact & Pipeline Sync | Replace with this project | The CRM sync story is now part of a broader revenue-ops workflow. Keep the old item only if a client specifically asks for GHL-only work. |

Recommended to keep, but lower than the new flagship if the profile is AI automation-first:

| Existing portfolio item | Recommendation | Reason |
|---|---|---|
| Power BI Dashboard for WhatsApp AI Customer Support | Keep near the top | It shows BI/reporting capability in the same WhatsApp / AI support domain. |
| Internal Document Knowledge Base with Cited Answers & API | Keep near the top | It shows standalone RAG/API capability; this project uses RAG as part of a larger workflow. |

Finance and Power BI portfolio items should stay because they serve a different buyer segment:

- Financial Model-5-Year Monthly P&L, Cash Flow, DCF for Services SME
- FX Exposure & Hedging Model -- Excel + IHB Netting + IFRS 9 Stress Test
- Power BI Dashboard: 13-Week Cash Forecast, Payroll, FX Hedging
- 13-Week Rolling Cash Flow - Multi-Entity Multi-Currency Model
- Excel Liquidity Framework: Multi-Entity Cash Pool, FX & KPI Monitor

## Suggested Portfolio Order

If the profile is meant to lead with automation / AI systems:

1. WhatsApp Revenue Ops: AI Sales Agent, Knowledge Base & CRM Workflow
2. Power BI Dashboard for WhatsApp AI Customer Support
3. Internal Document Knowledge Base with Cited Answers & API
4. Financial Model-5-Year Monthly P&L, Cash Flow, DCF for Services SME
5. Power BI Dashboard: 13-Week Cash Forecast, Payroll, FX Hedging
6. FX Exposure & Hedging Model -- Excel + IHB Netting + IFRS 9 Stress Test
7. 13-Week Rolling Cash Flow - Multi-Entity Multi-Currency Model
8. Excel Liquidity Framework: Multi-Entity Cash Pool, FX & KPI Monitor

If the profile is meant to lead with finance / FP&A work, keep the finance projects first and place this project as the first automation/AI item.

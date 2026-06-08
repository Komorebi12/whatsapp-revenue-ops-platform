# GHL Mock Server

Local-only mock for the `ghl-sync` service.

Supported endpoints:

- `GET /health`
- `GET /requests`
- `POST /contacts/upsert`
- `POST /contacts/{contact_id}/notes`
- `GET /opportunities/search`
- `POST /opportunities/`
- `PUT /opportunities/{opportunity_id}`
- `POST /mock-gemini/chat/completions`

`/mock-gemini/chat/completions` is an OpenAI-compatible stub used by the local
sales-agent container so P0 does not require a real Gemini key.

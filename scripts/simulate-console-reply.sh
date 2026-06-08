#!/usr/bin/env bash
set -euo pipefail

TICKET_ID="${1:-TICKET-PHASE1A-001}"
BODY_TEXT="${2:-Thanks for the details. A teammate will follow up shortly.}"
CLERK_USER_ID="${3:-user_demo_operator}"
IDEMPOTENCY_KEY="${4:-$(python - <<'PY'
import uuid
print(uuid.uuid4())
PY
)}"
SECRET="${MVP_REPLY_WEBHOOK_SECRET:-mock-console-secret}"

curl -sS -X POST http://localhost:5678/webhook/console/reply \
  -H "Authorization: Bearer ${SECRET}" \
  -H 'Content-Type: application/json' \
  -d "{
    \"ticket_id\":\"${TICKET_ID}\",
    \"body_text\":\"${BODY_TEXT}\",
    \"idempotency_key\":\"${IDEMPOTENCY_KEY}\",
    \"clerk_user_id\":\"${CLERK_USER_ID}\"
  }"

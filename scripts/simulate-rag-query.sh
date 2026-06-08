#!/usr/bin/env bash
set -euo pipefail

message="${1:-What is your return policy?}"
message_id="$(python - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"

curl -fsS -X POST http://localhost:5678/webhook/twilio/whatsapp/inbound \
  -H 'Content-Type: application/json' \
  -d "{
    \"customer_id\":\"11111111-1111-4111-8111-111111111111\",
    \"customer_phone\":\"+15551234567\",
    \"customer_display_name\":\"Demo Buyer\",
    \"message_id\":\"${message_id}\",
    \"inbound_text\":\"${message}\",
    \"intent\":\"information_query\",
    \"intent_confidence\":0.88,
    \"ticket_id\":\"TICKET-PHASE1A-001\"
  }"
echo
sleep 3

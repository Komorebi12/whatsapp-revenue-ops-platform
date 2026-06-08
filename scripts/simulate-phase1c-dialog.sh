#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

messages=(
  "Hi, I am interested in your product"
  "We have 50 users and need it this month with a \$5000 budget"
  "Can we see pricing and book a demo?"
)

for idx in "${!messages[@]}"; do
  message_id="phase1c-$(date +%s)-${idx}"
  curl -sS -X POST http://localhost:5678/webhook/twilio/whatsapp/inbound \
    -H 'Content-Type: application/json' \
    -d "{
      \"customer_id\":\"11111111-1111-4111-8111-111111111111\",
      \"customer_phone\":\"+15551234567\",
      \"customer_display_name\":\"Demo Buyer\",
      \"message_id\":\"${message_id}\",
      \"inbound_text\":\"${messages[$idx]}\",
      \"intent\":\"purchase\",
      \"intent_confidence\":0.91,
      \"ticket_id\":\"TICKET-PHASE1A-001\"
    }"
  echo
  sleep 1
done

cd "$script_dir/../deploy"
docker compose exec -T postgres psql -U postgres -d revenue_ops -c \
  "select total_score, qualification_tier, score_breakdown, updated_at from lead_scores order by updated_at desc limit 1;"

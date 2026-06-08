#!/usr/bin/env bash
set -euo pipefail
curl -sS -X POST http://localhost:5678/webhook/twilio/whatsapp/inbound \
  -H 'Content-Type: application/json' \
  -d '{
    "customer_id":"11111111-1111-4111-8111-111111111111",
    "customer_phone":"+15551234567",
    "customer_display_name":"Demo Buyer",
    "message_id":"22222222-2222-4222-8222-222222222222",
    "inbound_text":"Hi, I am interested in your product",
    "intent":"purchase",
    "intent_confidence":0.91,
    "ticket_id":"TICKET-PHASE1A-001"
  }'

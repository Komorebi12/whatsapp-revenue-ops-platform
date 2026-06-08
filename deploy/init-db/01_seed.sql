-- Synthetic demo data for Phase 1A. Safe to rerun.

insert into customers (id, phone, display_name, metadata_json)
values (
  '11111111-1111-4111-8111-111111111111',
  '+15551234567',
  'Demo Buyer',
  '{"synthetic": true, "source": "whatsapp-revenue-ops-platform"}'::jsonb
)
on conflict (phone) do update
set display_name = excluded.display_name,
    last_seen_at = now(),
    metadata_json = customers.metadata_json || excluded.metadata_json;

insert into inbound_raw (
  provider_message_id,
  raw_payload,
  payload_form,
  from_address,
  to_address,
  body_text,
  message_type
)
values (
  'SM_PHASE1A_SEED_001',
  '{"synthetic": true}'::jsonb,
  '{"Body": "Hi, I am interested in your product"}'::jsonb,
  'whatsapp:+15551234567',
  'whatsapp:+15557654321',
  'Hi, I am interested in your product',
  'text'
)
on conflict (provider_message_id) do nothing;

insert into tickets (
  ticket_id,
  customer_id,
  intent,
  status,
  subject,
  summary,
  context_json,
  last_customer_message_at
)
values (
  'TICKET-PHASE1A-001',
  '11111111-1111-4111-8111-111111111111',
  'purchase',
  'open',
  'Demo purchase inquiry',
  'Synthetic demo customer interested in the product.',
  '{"synthetic": true}'::jsonb,
  now()
)
on conflict (ticket_id) do update
set status = excluded.status,
    summary = excluded.summary,
    updated_at = now();

insert into messages (
  id,
  customer_id,
  ticket_id,
  direction,
  channel,
  provider,
  provider_message_id,
  idempotency_key,
  sender_role,
  body_text,
  payload_json
)
values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'TICKET-PHASE1A-001',
  'inbound',
  'whatsapp',
  'demo-script',
  'SM_PHASE1A_SEED_001',
  'phase1a-seed-message-001',
  'customer',
  'Hi, I am interested in your product',
  '{"synthetic": true}'::jsonb
)
on conflict (id) do nothing;

insert into conversation_states (
  id,
  customer_id,
  stage,
  qualification_data,
  context_summary,
  turn_count
)
values (
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'qualification',
  '{"need": "CRM automation", "team_size": "50 users", "budget": "$5000"}'::jsonb,
  'Synthetic Phase 1A seed conversation.',
  3
)
on conflict (id) do nothing;

insert into lead_scores (
  id,
  customer_id,
  conversation_id,
  total_score,
  score_breakdown,
  qualification_tier
)
values (
  '44444444-4444-4444-8444-444444444444',
  '11111111-1111-4111-8111-111111111111',
  '33333333-3333-4333-8333-333333333333',
  82,
  '{"need": 25, "budget": 25, "urgency": 12, "fit": 20}'::jsonb,
  'qualified'
)
on conflict (customer_id, conversation_id) do update
set total_score = excluded.total_score,
    score_breakdown = excluded.score_breakdown,
    qualification_tier = excluded.qualification_tier,
    updated_at = now();

insert into revenue_events (
  idempotency_key,
  event_type,
  customer_id,
  conversation_id,
  pipeline_stage,
  lead_score,
  qualification_tier,
  metadata
)
values (
  'phase1a-seed-lead-qualified',
  'lead_qualified',
  '11111111-1111-4111-8111-111111111111',
  '33333333-3333-4333-8333-333333333333',
  'qualification',
  82,
  'qualified',
  '{"synthetic": true, "source": "01_seed.sql"}'::jsonb
)
on conflict (idempotency_key) do nothing;

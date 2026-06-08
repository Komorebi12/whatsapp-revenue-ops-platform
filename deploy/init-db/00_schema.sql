-- WhatsApp Revenue Ops Platform local schema.
-- Standalone reference implementation schema for the public mock-first demo.
-- Combines support ticketing, inbound message persistence, sales lead scoring,
-- CRM sync audit data, revenue-event fixtures, and n8n metadata support tables.
-- Target runtime: the bundled local Postgres service in Docker Compose.

begin;

create extension if not exists pgcrypto;

create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  phone text not null unique,
  display_name text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  metadata_json jsonb not null default '{}'::jsonb
);

create table if not exists tickets (
  ticket_id text primary key,
  customer_id uuid not null references customers(id) on delete restrict,
  intent text not null,
  status text not null default 'open' check (
    status in (
      'open',
      'closed',
      'awaiting_staff',
      'awaiting_customer',
      'pending_reactivation',
      'resolved',
      'abandoned'
    )
  ),
  source_inbound_raw_id bigint,
  source_message_id uuid,
  subject text,
  summary text,
  context_json jsonb not null default '{}'::jsonb,
  pending_free_form text,
  pending_free_form_staff_id text,
  pending_free_form_at timestamptz,
  reactivation_attempts integer not null default 0,
  last_customer_message_at timestamptz,
  last_staff_reply_at timestamptz,
  last_template_sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_by_staff_id text,
  resolved_at timestamptz
);

alter table if exists tickets add column if not exists source_inbound_raw_id bigint;
alter table if exists tickets add column if not exists source_message_id uuid;
alter table if exists tickets add column if not exists subject text;
alter table if exists tickets add column if not exists closed_at timestamptz;
alter table if exists tickets add column if not exists closed_by_staff_id text;
alter table if exists tickets drop constraint if exists tickets_status_check;
alter table if exists tickets
  add constraint tickets_status_check check (
    status in (
      'open',
      'closed',
      'awaiting_staff',
      'awaiting_customer',
      'pending_reactivation',
      'resolved',
      'abandoned'
    )
  );

create table if not exists inbound_raw (
  id bigserial primary key,
  provider text not null default 'twilio',
  channel text not null default 'whatsapp',
  provider_message_id text not null unique,
  raw_payload jsonb not null,
  payload_form jsonb not null default '{}'::jsonb,
  twilio_signature text,
  from_address text not null,
  to_address text not null,
  body_text text,
  num_media integer not null default 0,
  message_type text not null check (message_type in ('text', 'media', 'unsupported', 'unknown')),
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create table if not exists staff_inbound_raw (
  id bigserial primary key,
  provider text not null default 'telegram',
  telegram_update_id bigint not null unique,
  raw_payload jsonb not null,
  chat_id bigint,
  from_id bigint,
  reply_to_message_id bigint,
  command_text text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete restrict,
  ticket_id text references tickets(ticket_id) on delete set null,
  direction text not null check (direction in ('inbound', 'outbound')),
  channel text not null default 'whatsapp',
  provider text not null default 'twilio',
  provider_message_id text unique,
  idempotency_key text,
  sender_role text not null check (sender_role in ('customer', 'system', 'staff')),
  message_type text not null default 'text',
  body_text text,
  payload_json jsonb not null default '{}'::jsonb,
  status text not null default 'accepted',
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  failed_at timestamptz
);

alter table if exists messages add column if not exists idempotency_key text;

do $$
begin
  alter table tickets
    add constraint tickets_source_inbound_raw_id_fkey
    foreign key (source_inbound_raw_id) references inbound_raw(id) on delete restrict;
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter table tickets
    add constraint tickets_source_message_id_fkey
    foreign key (source_message_id) references messages(id) on delete set null;
exception
  when duplicate_object then null;
end
$$;

create table if not exists staff_messages (
  id bigserial primary key,
  ticket_id text not null references tickets(ticket_id) on delete cascade,
  telegram_chat_id bigint not null,
  telegram_message_id bigint not null,
  message_role text not null default 'notification' check (message_role in ('notification', 'reply', 'system')),
  body_text text,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (telegram_chat_id, telegram_message_id)
);

create table if not exists event_log (
  id bigserial primary key,
  type text not null,
  ticket_id text references tickets(ticket_id) on delete set null,
  customer_id uuid references customers(id) on delete set null,
  payload_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists config_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

insert into config_settings (key, value, description) values
  (
    'whitelist.staff_telegram_from_ids',
    '[]'::jsonb,
    'Allowed Telegram user IDs (string list) for staff command authentication'
  ),
  (
    'whitelist.staff_telegram_chat_ids',
    '[]'::jsonb,
    'Allowed Telegram chat IDs (string list) for staff command authentication'
  ),
  (
    'secret.twilio_webhook_auth_token',
    '""'::jsonb,
    'Twilio Auth Token for inbound webhook signature validation. Populate outside git before testing valid signatures.'
  ),
  (
    'secret.console_reply_webhook_secret',
    '""'::jsonb,
    'Bearer secret shared with the operator console for /webhook/console/reply. Populate outside git before testing.'
  ),
  (
    'template.utility_content_sid',
    '""'::jsonb,
    'Twilio ContentSid for the approved utility template. Empty string keeps sandbox/demo on free-form fallback.'
  ),
  (
    'template.utility_content_variables',
    '{}'::jsonb,
    'JSON object for Twilio Content API variables when template sending is enabled in a later iteration.'
  )
on conflict (key) do nothing;

create unique index if not exists idx_tickets_one_active_per_customer
  on tickets(customer_id)
  where status in ('open', 'awaiting_staff', 'awaiting_customer', 'pending_reactivation');

create index if not exists idx_tickets_status_created_at
  on tickets(status, created_at desc);

create index if not exists idx_inbound_raw_received_at
  on inbound_raw(received_at desc);

create index if not exists idx_staff_inbound_raw_received_at
  on staff_inbound_raw(received_at desc);

create index if not exists idx_messages_customer_created_at
  on messages(customer_id, created_at desc);

create index if not exists idx_messages_ticket_created_at
  on messages(ticket_id, created_at desc);

create unique index if not exists idx_messages_idempotency_key
  on messages(idempotency_key)
  where idempotency_key is not null;

create index if not exists idx_event_log_ticket_created_at
  on event_log(ticket_id, created_at desc);

create index if not exists idx_event_log_customer_created_at
  on event_log(customer_id, created_at desc);

commit;
-- WhatsApp AI Sales Agent: additive tables only (no modifications to existing schema)

-- Conversation state machine tracking
create table if not exists conversation_states (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references customers(id),
    stage text not null default 'greeting'
        check (stage in (
            'greeting', 'discovery', 'qualification',
            'recommendation', 'closing', 'handoff', 'completed'
        )),
    qualification_data jsonb not null default '{}'::jsonb,
    context_summary text,
    turn_count integer not null default 0,
    last_ai_response_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- One active conversation per customer
create unique index if not exists idx_conversation_states_active_customer
    on conversation_states(customer_id)
    where stage not in ('completed', 'handoff');

-- Lead scores
create table if not exists lead_scores (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references customers(id),
    conversation_id uuid not null references conversation_states(id),
    total_score integer not null default 0
        check (total_score between 0 and 100),
    score_breakdown jsonb not null default '{}'::jsonb,
    qualification_tier text not null default 'unqualified'
        check (qualification_tier in (
            'unqualified', 'cold', 'warm', 'hot', 'qualified'
        )),
    ghl_stage_synced text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_lead_scores_customer
    on lead_scores(customer_id, updated_at desc);

create unique index if not exists idx_lead_scores_customer_conversation
    on lead_scores(customer_id, conversation_id);

-- AI response audit log
create table if not exists ai_responses (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references conversation_states(id),
    customer_id uuid not null references customers(id),
    message_id uuid,
    inbound_text text not null,
    system_prompt_hash text,
    model_name text not null,
    raw_model_response jsonb not null default '{}'::jsonb,
    generated_reply text not null,
    conversation_stage text not null,
    lead_score_snapshot integer,
    handoff_triggered boolean not null default false,
    customer_sentiment text not null default 'neutral'
        check (customer_sentiment in (
            'positive', 'neutral', 'negative', 'frustrated'
        )),
    latency_ms integer,
    created_at timestamptz not null default now()
);

create index if not exists idx_ai_responses_conversation
    on ai_responses(conversation_id, created_at desc);

create unique index if not exists idx_ai_responses_message_id
    on ai_responses(message_id)
    where message_id is not null;

-- Denormalized conversation history for fast context assembly
create table if not exists conversation_messages (
    id bigserial primary key,
    conversation_id uuid not null references conversation_states(id),
    role text not null check (role in ('customer', 'assistant', 'system')),
    content text not null,
    metadata_json jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists idx_conversation_messages_conv_time
    on conversation_messages(conversation_id, created_at desc);
-- WhatsApp Revenue Intelligence Phase 1: additive revenue event contract
-- Local/dev only unless explicitly approved for another environment.

create table if not exists revenue_events (
    id bigserial primary key,
    idempotency_key text not null unique,
    event_type text not null check (event_type in (
        'lead_qualified',
        'opportunity_created',
        'stage_advanced',
        'handoff_requested',
        'deal_won',
        'deal_lost',
        'deal_stale'
    )),
    customer_id uuid not null,
    conversation_id uuid,
    opportunity_id text,
    pipeline_stage text,
    lead_score integer,
    qualification_tier text,
    revenue_amount numeric(12,2),
    close_reason text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists idx_revenue_events_customer
    on revenue_events(customer_id);

create index if not exists idx_revenue_events_type
    on revenue_events(event_type);

create index if not exists idx_revenue_events_created
    on revenue_events(created_at);

create index if not exists idx_revenue_events_opp
    on revenue_events(opportunity_id)
    where opportunity_id is not null;

alter table conversation_states
    add column if not exists outcome text,
    add column if not exists outcome_at timestamptz,
    add column if not exists revenue_amount numeric(12,2);

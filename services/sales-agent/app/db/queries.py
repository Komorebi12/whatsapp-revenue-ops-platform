GET_ACTIVE_CONVERSATION = """
    select id, customer_id, stage, qualification_data, context_summary,
           turn_count, last_ai_response_at, created_at, updated_at
    from conversation_states
    where customer_id = $1
      and stage not in ('completed', 'handoff')
    limit 1
"""

CREATE_CONVERSATION = """
    insert into conversation_states (customer_id, stage)
    values ($1, 'greeting')
    returning id, stage, qualification_data, turn_count, created_at, updated_at
"""

UPDATE_CONVERSATION = """
    update conversation_states
    set stage = $2,
        qualification_data = $3,
        turn_count = $4,
        last_ai_response_at = now(),
        updated_at = now()
    where id = $1
    returning id, stage, qualification_data, turn_count, updated_at
"""

INSERT_CONVERSATION_MESSAGE = """
    insert into conversation_messages (conversation_id, role, content, metadata_json)
    values ($1, $2, $3, $4)
"""

GET_CONVERSATION_MESSAGES = """
    select role, content, created_at
    from conversation_messages
    where conversation_id = $1
    order by created_at desc
    limit $2
"""

INSERT_AI_RESPONSE = """
    insert into ai_responses (
        conversation_id, customer_id, message_id, inbound_text,
        model_name, raw_model_response, generated_reply,
        conversation_stage, lead_score_snapshot, handoff_triggered,
        latency_ms, customer_sentiment
    ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
    on conflict (message_id) where message_id is not null do nothing
    returning id
"""

GET_AI_RESPONSE_BY_MESSAGE_ID = """
    select id, generated_reply, conversation_stage, lead_score_snapshot,
           handoff_triggered, raw_model_response
    from ai_responses
    where message_id = $1
    limit 1
"""

UPSERT_LEAD_SCORE = """
    insert into lead_scores (customer_id, conversation_id, total_score, score_breakdown, qualification_tier)
    values ($1, $2, $3, $4, $5)
    on conflict (customer_id, conversation_id) do update
    set total_score = excluded.total_score,
        score_breakdown = excluded.score_breakdown,
        qualification_tier = excluded.qualification_tier,
        updated_at = now()
    returning id
"""

UPDATE_LEAD_SCORE = """
    update lead_scores
    set total_score = $3,
        score_breakdown = $4,
        qualification_tier = $5,
        updated_at = now()
    where customer_id = $1 and conversation_id = $2
    returning id
"""

GET_LEAD_SCORE = """
    select id, total_score, score_breakdown, qualification_tier, ghl_stage_synced
    from lead_scores
    where customer_id = $1 and conversation_id = $2
    limit 1
"""

GET_RECENT_SENTIMENTS = """
    select customer_sentiment
    from ai_responses
    where conversation_id = $1
    order by created_at desc
    limit $2
"""

LIST_CONVERSATIONS = """
    select cs.id as conversation_id, cs.customer_id, cs.stage, cs.turn_count,
           cs.qualification_data, cs.created_at, cs.updated_at,
           coalesce(ls.total_score, 0) as lead_score,
           coalesce(ls.qualification_tier, 'unqualified') as qualification_tier
    from conversation_states cs
    left join lead_scores ls on ls.conversation_id = cs.id
    order by cs.updated_at desc
    limit $1 offset $2
"""

LIST_LEAD_SCORES = """
    select ls.customer_id, ls.conversation_id::text, ls.total_score,
           ls.qualification_tier, ls.score_breakdown, ls.updated_at
    from lead_scores ls
    order by ls.total_score desc
    limit $1 offset $2
"""

UPDATE_LEAD_SCORE_GHL_STAGE = """
    update lead_scores
    set ghl_stage_synced = $2, updated_at = now()
    where id = $1
"""

INSERT_REVENUE_EVENT = """
    insert into revenue_events (
        idempotency_key, event_type, customer_id, conversation_id,
        opportunity_id, pipeline_stage, lead_score, qualification_tier,
        revenue_amount, close_reason, metadata
    ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    on conflict (idempotency_key) do nothing
"""

UPDATE_CONVERSATION_OUTCOME = """
    update conversation_states
    set outcome = $2,
        outcome_at = now(),
        revenue_amount = $3,
        updated_at = now()
    where id = $1
"""

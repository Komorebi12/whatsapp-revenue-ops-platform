import json

import asyncpg

from app.db import queries


async def get_active_conversation(pool: asyncpg.Pool, customer_id: str) -> dict | None:
    row = await pool.fetchrow(queries.GET_ACTIVE_CONVERSATION, customer_id)
    if row is None:
        return None
    conversation = dict(row)
    conversation["qualification_data"] = _jsonb_to_dict(
        conversation.get("qualification_data")
    )
    return conversation


async def create_conversation(pool: asyncpg.Pool, customer_id: str) -> dict:
    row = await pool.fetchrow(queries.CREATE_CONVERSATION, customer_id)
    conversation = dict(row)
    conversation["qualification_data"] = _jsonb_to_dict(
        conversation.get("qualification_data")
    )
    return conversation


async def update_conversation(
    pool: asyncpg.Pool,
    conversation_id: str,
    stage: str,
    qualification_data: dict,
    turn_count: int,
) -> dict:
    row = await pool.fetchrow(
        queries.UPDATE_CONVERSATION,
        conversation_id,
        stage,
        json.dumps(qualification_data),
        turn_count,
    )
    return dict(row)


async def insert_conversation_message(
    pool: asyncpg.Pool,
    conversation_id: str,
    role: str,
    content: str,
    metadata: dict | None = None,
) -> None:
    await pool.execute(
        queries.INSERT_CONVERSATION_MESSAGE,
        conversation_id,
        role,
        content,
        json.dumps(metadata or {}),
    )


async def get_conversation_messages(
    pool: asyncpg.Pool, conversation_id: str, limit: int = 10
) -> list[dict]:
    rows = await pool.fetch(queries.GET_CONVERSATION_MESSAGES, conversation_id, limit)
    # Reverse so oldest first
    return [dict(r) for r in reversed(rows)]


async def insert_ai_response(
    pool: asyncpg.Pool,
    conversation_id: str,
    customer_id: str,
    message_id: str,
    inbound_text: str,
    model_name: str,
    raw_response: dict,
    generated_reply: str,
    stage: str,
    lead_score: int,
    handoff_triggered: bool,
    latency_ms: int,
    customer_sentiment: str,
) -> str | None:
    row = await pool.fetchrow(
        queries.INSERT_AI_RESPONSE,
        conversation_id,
        customer_id,
        message_id,
        inbound_text,
        model_name,
        json.dumps(raw_response),
        generated_reply,
        stage,
        lead_score,
        handoff_triggered,
        latency_ms,
        customer_sentiment,
    )
    if row is None:
        return None
    return str(row["id"])


async def get_cached_response(pool: asyncpg.Pool, message_id: str) -> dict | None:
    row = await pool.fetchrow(queries.GET_AI_RESPONSE_BY_MESSAGE_ID, message_id)
    if row is None:
        return None
    return dict(row)


async def upsert_lead_score(
    pool: asyncpg.Pool,
    customer_id: str,
    conversation_id: str,
    total_score: int,
    breakdown: dict,
    tier: str,
) -> None:
    await pool.fetchrow(
        queries.UPSERT_LEAD_SCORE,
        customer_id,
        conversation_id,
        total_score,
        json.dumps(breakdown),
        tier,
    )


async def get_lead_score(
    pool: asyncpg.Pool, customer_id: str, conversation_id: str
) -> dict | None:
    row = await pool.fetchrow(queries.GET_LEAD_SCORE, customer_id, conversation_id)
    if row is None:
        return None
    return dict(row)


async def get_recent_sentiments(
    pool: asyncpg.Pool, conversation_id: str, limit: int = 5
) -> list[str]:
    rows = await pool.fetch(queries.GET_RECENT_SENTIMENTS, conversation_id, limit)
    sentiments = [row["customer_sentiment"] or "neutral" for row in rows]
    return list(reversed(sentiments))


async def list_conversations(
    pool: asyncpg.Pool, limit: int = 50, offset: int = 0
) -> list[dict]:
    rows = await pool.fetch(queries.LIST_CONVERSATIONS, limit, offset)
    return [dict(r) for r in rows]


async def list_lead_scores(
    pool: asyncpg.Pool, limit: int = 50, offset: int = 0
) -> list[dict]:
    rows = await pool.fetch(queries.LIST_LEAD_SCORES, limit, offset)
    return [dict(r) for r in rows]


async def update_lead_score_ghl_stage(
    pool: asyncpg.Pool, lead_score_id: str, ghl_stage: str
) -> None:
    await pool.execute(queries.UPDATE_LEAD_SCORE_GHL_STAGE, lead_score_id, ghl_stage)


async def insert_revenue_event(
    pool: asyncpg.Pool,
    *,
    idempotency_key: str,
    event_type: str,
    customer_id: str,
    conversation_id: str | None = None,
    opportunity_id: str | None = None,
    pipeline_stage: str | None = None,
    lead_score: int | None = None,
    qualification_tier: str | None = None,
    revenue_amount: float | None = None,
    close_reason: str | None = None,
    metadata: dict | None = None,
) -> None:
    await pool.execute(
        queries.INSERT_REVENUE_EVENT,
        idempotency_key,
        event_type,
        customer_id,
        conversation_id,
        opportunity_id,
        pipeline_stage,
        lead_score,
        qualification_tier,
        revenue_amount,
        close_reason,
        json.dumps(metadata or {}),
    )


async def record_conversation_outcome(
    pool: asyncpg.Pool,
    *,
    idempotency_key: str,
    event_type: str,
    customer_id: str,
    conversation_id: str,
    outcome: str,
    revenue_amount: float | None = None,
    close_reason: str | None = None,
    metadata: dict | None = None,
) -> None:
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                queries.UPDATE_CONVERSATION_OUTCOME,
                conversation_id,
                outcome,
                revenue_amount,
            )
            await conn.execute(
                queries.INSERT_REVENUE_EVENT,
                idempotency_key,
                event_type,
                customer_id,
                conversation_id,
                None,
                None,
                None,
                None,
                revenue_amount,
                close_reason,
                json.dumps(metadata or {}),
            )


def _jsonb_to_dict(value: object) -> dict:
    if value is None:
        return {}
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        return json.loads(value)
    return dict(value)

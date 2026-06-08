import json
import logging

import asyncpg

logger = logging.getLogger(__name__)

INSERT_REVENUE_EVENT = """
    insert into revenue_events (
        idempotency_key, event_type, customer_id, conversation_id,
        opportunity_id, pipeline_stage, lead_score, qualification_tier,
        revenue_amount, close_reason, metadata
    ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    on conflict (idempotency_key) do nothing
"""


async def init_revenue_pool(dsn: str | None) -> asyncpg.Pool | None:
    if not dsn:
        return None
    return await asyncpg.create_pool(dsn=dsn, min_size=1, max_size=5)


async def close_revenue_pool(pool: asyncpg.Pool | None) -> None:
    if pool is not None:
        await pool.close()


async def insert_revenue_event(
    pool: asyncpg.Pool | None,
    *,
    idempotency_key: str,
    event_type: str,
    customer_id: str | None,
    conversation_id: str | None = None,
    opportunity_id: str | None = None,
    pipeline_stage: str | None = None,
    lead_score: int | None = None,
    qualification_tier: str | None = None,
    revenue_amount: float | None = None,
    close_reason: str | None = None,
    metadata: dict | None = None,
) -> None:
    if pool is None:
        logger.warning("Revenue event skipped because revenue DB pool is not configured")
        return
    if not customer_id:
        logger.warning("Revenue event %s skipped because customer_id is missing", event_type)
        return

    await pool.execute(
        INSERT_REVENUE_EVENT,
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

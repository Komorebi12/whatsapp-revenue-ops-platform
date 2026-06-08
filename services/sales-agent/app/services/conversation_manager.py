import logging
from datetime import UTC, datetime

import asyncpg

from app.config import Settings
from app.db import repositories as repo
from app.models.conversation import (
    ACTIVE_STAGES,
    STAGE_ORDER,
    ConversationStage,
    QualificationTier,
)
from app.models.responses import AgentRespondResponse, GhlUpdate
from app.prompts.system_prompt import build_system_prompt
from app.prompts.templates import QUALIFICATION_FIELDS
from app.services.ai_client import AiClient, AiResponse
from app.services.ghl_sync_client import GhlSyncClient
from app.services.handoff_detector import EXPLICIT_HANDOFF_PATTERNS, should_handoff
from app.services.lead_scorer import compute_score, score_to_tier

logger = logging.getLogger(__name__)

TIER_TO_GHL_STATUS = {
    QualificationTier.UNQUALIFIED: "open",
    QualificationTier.COLD: "open",
    QualificationTier.WARM: "open",
    QualificationTier.HOT: "open",
    QualificationTier.QUALIFIED: "open",
}

TIER_TO_GHL_STAGE_LABEL = {
    QualificationTier.UNQUALIFIED: "lead_capture",
    QualificationTier.COLD: "lead_capture",
    QualificationTier.WARM: "qualification",
    QualificationTier.HOT: "won",
    QualificationTier.QUALIFIED: "won",
}

REVENUE_EVENT_MIN_SCORE = 40

HANDOFF_REPLY = (
    "I'm connecting you with a team member who can help you directly. "
    "They'll be in touch shortly! 🙌"
)


class ConversationManager:
    def __init__(
        self,
        pool: asyncpg.Pool,
        ai_client: AiClient,
        ghl_client: GhlSyncClient | None,
        settings: Settings,
    ):
        self._pool = pool
        self._ai = ai_client
        self._ghl = ghl_client
        self._settings = settings

    async def handle_message(
        self,
        customer_id: str,
        customer_phone: str,
        customer_display_name: str | None,
        message_id: str,
        inbound_text: str,
        intent: str,
        ticket_id: str | None,
    ) -> AgentRespondResponse:
        # Idempotency: check if we already processed this message
        cached = await repo.get_cached_response(self._pool, message_id)
        if cached:
            return self._build_cached_response(cached)

        # Get or create conversation
        conv = await repo.get_active_conversation(self._pool, customer_id)
        if conv is None:
            created = await repo.create_conversation(self._pool, customer_id)
            conv = {
                "id": created["id"],
                "stage": created["stage"],
                "qualification_data": created.get("qualification_data") or {},
                "turn_count": created["turn_count"],
            }

        conversation_id = str(conv["id"])
        stage = ConversationStage(conv["stage"])
        qual_data = conv.get("qualification_data") or {}
        turn_count = conv["turn_count"]

        explicit_handoff = EXPLICIT_HANDOFF_PATTERNS.match(inbound_text.strip())
        if explicit_handoff:
            await repo.insert_conversation_message(
                self._pool, conversation_id, "customer", inbound_text,
                {"message_id": message_id, "intent": intent},
            )
            await repo.update_conversation(
                self._pool, conversation_id, ConversationStage.HANDOFF.value,
                qual_data, turn_count,
            )
            await repo.insert_conversation_message(
                self._pool, conversation_id, "assistant", HANDOFF_REPLY,
                {
                    "action": "escalate",
                    "stage": ConversationStage.HANDOFF.value,
                    "handoff_reason": "customer_requested_human",
                },
            )
            await repo.insert_ai_response(
                pool=self._pool,
                conversation_id=conversation_id,
                customer_id=customer_id,
                message_id=message_id,
                inbound_text=inbound_text,
                model_name=self._settings.gemini_model,
                raw_response={"source": "handoff_precheck", "reason": "customer_requested_human"},
                generated_reply=HANDOFF_REPLY,
                stage=ConversationStage.HANDOFF.value,
                lead_score=0,
                handoff_triggered=True,
                latency_ms=0,
                customer_sentiment="neutral",
            )
            await repo.upsert_lead_score(
                self._pool, customer_id, conversation_id, 0, {},
                QualificationTier.UNQUALIFIED.value,
            )
            await repo.insert_revenue_event(
                self._pool,
                idempotency_key=f"{customer_id}:handoff_requested:{conversation_id}",
                event_type="handoff_requested",
                customer_id=customer_id,
                conversation_id=conversation_id,
                metadata={"reason": "customer_requested_human"},
            )
            if self._ghl:
                try:
                    await self._ghl.sync_contact(
                        phone=customer_phone,
                        display_name=customer_display_name,
                        message_body=inbound_text,
                        intent=intent,
                        ticket_id=ticket_id,
                    )
                except Exception:
                    logger.error(
                        "GHL sync_contact failed during handoff for %s",
                        customer_id,
                        exc_info=True,
                    )
            return AgentRespondResponse(
                action="escalate",
                reply_text=HANDOFF_REPLY,
                conversation_stage=ConversationStage.HANDOFF.value,
                lead_score=0,
                qualification_tier=QualificationTier.UNQUALIFIED.value,
                handoff_triggered=True,
            )

        # Store inbound message
        await repo.insert_conversation_message(
            self._pool, conversation_id, "customer", inbound_text,
            {"message_id": message_id, "intent": intent},
        )

        # Load conversation history for context
        history = await repo.get_conversation_messages(
            self._pool, conversation_id, self._settings.max_context_messages
        )
        history_dicts = [{"role": m["role"], "content": m["content"]} for m in history]

        # Get recent sentiments for handoff detection
        recent_sentiments = await repo.get_recent_sentiments(self._pool, conversation_id, 5)

        # Build system prompt and call AI
        system_prompt = build_system_prompt(
            stage=stage,
            company_name=self._settings.company_name,
            company_product_summary=self._settings.company_product_summary,
            qualification_data=qual_data,
            history=history_dicts,
        )

        ai_resp: AiResponse = await self._ai.generate(system_prompt, inbound_text)

        # Merge extracted fields into qualification data
        for field in QUALIFICATION_FIELDS:
            extracted = ai_resp.extracted_fields.get(field, "")
            if extracted and not qual_data.get(field):
                qual_data[field] = extracted

        turn_count += 1

        # Compute lead score
        score, breakdown = compute_score(
            qual_data, turn_count, recent_sentiments + [ai_resp.customer_sentiment],
            inbound_text,
        )
        tier = score_to_tier(score, self._settings)

        # Check handoff
        handoff, handoff_reason = should_handoff(
            inbound_text=inbound_text,
            stage=stage,
            turn_count=turn_count,
            max_turns=self._settings.max_turns_before_handoff,
            lead_score=score,
            recent_sentiments=recent_sentiments + [ai_resp.customer_sentiment],
            ai_suggest_handoff=ai_resp.suggest_handoff,
        )

        # Determine stage transition
        new_stage = stage
        if handoff:
            new_stage = ConversationStage.HANDOFF
        elif ai_resp.suggest_stage_advance and stage in ACTIVE_STAGES:
            idx = STAGE_ORDER.index(stage)
            if idx + 1 < len(STAGE_ORDER):
                new_stage = STAGE_ORDER[idx + 1]

        # Update conversation state
        await repo.update_conversation(
            self._pool, conversation_id, new_stage.value, qual_data, turn_count,
        )

        # Determine reply
        reply_text = HANDOFF_REPLY if handoff else ai_resp.reply_text
        action = "escalate" if handoff else "reply"

        # Store assistant message
        await repo.insert_conversation_message(
            self._pool, conversation_id, "assistant", reply_text,
            {"action": action, "stage": new_stage.value},
        )

        # Store AI response for audit
        await repo.insert_ai_response(
            pool=self._pool,
            conversation_id=conversation_id,
            customer_id=customer_id,
            message_id=message_id,
            inbound_text=inbound_text,
            model_name=self._settings.gemini_model,
            raw_response=ai_resp.raw_response,
            generated_reply=reply_text,
            stage=new_stage.value,
            lead_score=score,
            handoff_triggered=handoff,
            latency_ms=ai_resp.latency_ms,
            customer_sentiment=ai_resp.customer_sentiment,
        )

        # Update lead score
        await repo.upsert_lead_score(
            self._pool, customer_id, conversation_id, score, breakdown, tier.value,
        )
        if score >= REVENUE_EVENT_MIN_SCORE:
            await repo.insert_revenue_event(
                self._pool,
                idempotency_key=f"{customer_id}:lead_qualified:{conversation_id}",
                event_type="lead_qualified",
                customer_id=customer_id,
                conversation_id=conversation_id,
                lead_score=score,
                qualification_tier=tier.value,
                metadata={"score_breakdown": breakdown},
            )
        if handoff:
            await repo.insert_revenue_event(
                self._pool,
                idempotency_key=f"{customer_id}:handoff_requested:{conversation_id}",
                event_type="handoff_requested",
                customer_id=customer_id,
                conversation_id=conversation_id,
                lead_score=score,
                qualification_tier=tier.value,
                metadata={"reason": handoff_reason or "handoff_detector"},
            )

        # GHL sync (fire-and-forget style, errors logged but not raised)
        ghl_update = GhlUpdate()
        ghl_stage_label = TIER_TO_GHL_STAGE_LABEL.get(tier, "lead_capture")
        prev_score_row = await repo.get_lead_score(self._pool, customer_id, conversation_id)
        prev_ghl_stage = prev_score_row.get("ghl_stage_synced") if prev_score_row else None

        if self._ghl and ghl_stage_label != prev_ghl_stage:
            ghl_update = GhlUpdate(
                should_sync=True,
                pipeline_stage=ghl_stage_label,
                lead_score=score,
            )
            try:
                # Sync contact
                await self._ghl.sync_contact(
                    phone=customer_phone,
                    display_name=customer_display_name,
                    message_body=inbound_text,
                    intent=intent,
                    ticket_id=ticket_id,
                )
                # Sync opportunity if we have a ticket
                if ticket_id:
                    ghl_status = TIER_TO_GHL_STATUS.get(tier, "open")
                    await self._ghl.sync_opportunity(
                        ticket_id=ticket_id,
                        phone=customer_phone,
                        status=ghl_status,
                        subject=f"Sales Lead - {qual_data.get('need', 'General Inquiry')}",
                        customer_id=customer_id,
                        conversation_id=conversation_id,
                    )
            except Exception:
                logger.error("GHL sync failed for %s", customer_id, exc_info=True)

        return AgentRespondResponse(
            action=action,
            reply_text=reply_text,
            conversation_stage=new_stage.value,
            lead_score=score,
            qualification_tier=tier.value,
            handoff_triggered=handoff,
            ghl_update=ghl_update,
        )

    async def mark_outcome(
        self,
        *,
        customer_id: str,
        conversation_id: str,
        outcome: str,
        revenue_amount: float | None = None,
        close_reason: str | None = None,
        check_date: str | None = None,
    ) -> None:
        normalized = outcome.strip().lower()
        if normalized not in {"won", "lost", "stale"}:
            raise ValueError("outcome must be one of: won, lost, stale")

        event_type = {
            "won": "deal_won",
            "lost": "deal_lost",
            "stale": "deal_stale",
        }[normalized]
        idempotency_key = f"{customer_id}:{event_type}:{conversation_id}"
        if normalized == "stale":
            stale_check_date = check_date or datetime.now(UTC).date().isoformat()
            idempotency_key = f"{idempotency_key}:{stale_check_date}"

        await repo.record_conversation_outcome(
            self._pool,
            idempotency_key=idempotency_key,
            event_type=event_type,
            customer_id=customer_id,
            conversation_id=conversation_id,
            outcome=normalized,
            revenue_amount=revenue_amount,
            close_reason=close_reason,
            metadata={"source": "sales_agent"},
        )

    def _build_cached_response(self, cached: dict) -> AgentRespondResponse:
        return AgentRespondResponse(
            action="escalate" if cached.get("handoff_triggered") else "reply",
            reply_text=cached["generated_reply"],
            conversation_stage=cached["conversation_stage"],
            lead_score=cached.get("lead_score_snapshot", 0),
            qualification_tier="unqualified",
            handoff_triggered=cached.get("handoff_triggered", False),
        )

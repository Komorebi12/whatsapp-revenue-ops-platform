import logging

from fastapi import APIRouter, Header, HTTPException, Request, status

from app.ghl_client import GhlApiError, extract_contact_id_from_opportunity, map_ticket_status, summarize_message
from app.models import ContactSyncRequest, OpportunitySyncRequest, SyncResponse
from app.revenue_events import insert_revenue_event

router = APIRouter(tags=["sync"])
logger = logging.getLogger(__name__)


def _require_secret(sync_secret: str | None, expected_secret: str) -> None:
    if not sync_secret or sync_secret != expected_secret:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid sync secret")


@router.post("/sync/contact", response_model=SyncResponse)
async def sync_contact(
    payload: ContactSyncRequest,
    request: Request,
    x_sync_secret: str | None = Header(default=None),
) -> SyncResponse:
    settings = request.app.state.settings
    client = request.app.state.ghl_client
    _require_secret(x_sync_secret, settings.sync_auth_secret)

    try:
        contact_id, created = await client.upsert_contact(
            phone=payload.phone,
            display_name=payload.display_name,
            intent=payload.intent,
            timestamp_iso=payload.timestamp.isoformat(),
        )
        note_title = f"WhatsApp Ticket {payload.ticket_id}" if payload.ticket_id else "WhatsApp Message"
        note_id = await client.create_contact_note(
            contact_id,
            summarize_message(payload.message_body, payload.intent, payload.ticket_id),
            title=note_title,
        )
    except GhlApiError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc

    action = "created" if created else "updated"
    return SyncResponse(
        message=f"Contact {action} and note synced",
        contact_id=contact_id,
        note_id=note_id,
        created=created,
    )


@router.post("/sync/opportunity", response_model=SyncResponse)
async def sync_opportunity(
    payload: OpportunitySyncRequest,
    request: Request,
    x_sync_secret: str | None = Header(default=None),
) -> SyncResponse:
    settings = request.app.state.settings
    client = request.app.state.ghl_client
    revenue_pool = getattr(request.app.state, "revenue_pool", None)
    _require_secret(x_sync_secret, settings.sync_auth_secret)

    opportunity_name = payload.subject or f"WhatsApp Ticket {payload.ticket_id}"

    try:
        contact_id, _ = await client.upsert_contact(
            phone=payload.phone,
            display_name=None,
            intent="support_ticket",
            timestamp_iso=payload.timestamp.isoformat(),
            write_custom_fields=False,
        )
        stage_id, ghl_status = map_ticket_status(payload.status, settings)
        matches = await client.search_opportunities(contact_id=contact_id)
        exact_name_match = next(
            (
                item
                for item in matches
                if extract_contact_id_from_opportunity(item) in {None, contact_id}
                and (item.get("name") or "").strip() == opportunity_name
            ),
            None,
        )
        existing = exact_name_match or next(
            (
                item
                for item in matches
                if extract_contact_id_from_opportunity(item) in {None, contact_id}
            ),
            None,
        )
        if existing:
            previous_stage_id = (
                existing.get("pipelineStageId")
                or existing.get("pipeline_stage_id")
                or existing.get("stageId")
            )
            opportunity_id = await client.update_opportunity(
                opportunity_id=str(existing.get("id") or existing.get("_id")),
                contact_id=contact_id,
                name=opportunity_name,
                stage_id=stage_id,
                status=ghl_status,
            )
            created = False
            message = "Opportunity updated"
            if previous_stage_id != stage_id:
                await insert_revenue_event(
                    revenue_pool,
                    idempotency_key=f"{opportunity_id}:stage_advanced:{stage_id}",
                    event_type="stage_advanced",
                    customer_id=payload.customer_id,
                    conversation_id=payload.conversation_id,
                    opportunity_id=opportunity_id,
                    pipeline_stage=stage_id,
                    metadata={
                        "from_stage": previous_stage_id,
                        "to_stage": stage_id,
                        "ticket_id": payload.ticket_id,
                    },
                )
        else:
            opportunity_id, created = await client.create_opportunity(
                contact_id=contact_id,
                name=opportunity_name,
                stage_id=stage_id,
                status=ghl_status,
            )
            message = "Opportunity created"
            await insert_revenue_event(
                revenue_pool,
                idempotency_key=f"{payload.customer_id}:opportunity_created:{opportunity_id}",
                event_type="opportunity_created",
                customer_id=payload.customer_id,
                conversation_id=payload.conversation_id,
                opportunity_id=opportunity_id,
                pipeline_stage=stage_id,
                metadata={"ticket_id": payload.ticket_id},
            )
        if payload.status.strip().lower() == "abandoned":
            if payload.conversation_id is None:
                logger.warning(
                    "Skipping deal_lost revenue event for ticket %s: conversation_id is missing",
                    payload.ticket_id,
                )
            else:
                await insert_revenue_event(
                    revenue_pool,
                    idempotency_key=f"{payload.customer_id}:deal_lost:{payload.conversation_id}",
                    event_type="deal_lost",
                    customer_id=payload.customer_id,
                    conversation_id=payload.conversation_id,
                    opportunity_id=opportunity_id,
                    pipeline_stage=stage_id,
                    close_reason="abandoned",
                    metadata={"ticket_id": payload.ticket_id, "ghl_status": ghl_status},
                )
    except GhlApiError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc

    return SyncResponse(
        message=message,
        contact_id=contact_id,
        opportunity_id=opportunity_id,
        created=created,
    )

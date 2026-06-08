from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request

from app.models.requests import AgentRespondRequest
from app.models.responses import AgentRespondResponse

router = APIRouter(prefix="/agent", tags=["agent"])


def _require_secret(request: Request, header_value: str | None) -> None:
    expected = request.app.state.settings.agent_auth_secret
    if not header_value or header_value != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")


@router.post("/respond", response_model=AgentRespondResponse)
async def respond(body: AgentRespondRequest, request: Request) -> AgentRespondResponse:
    _require_secret(request, request.headers.get("X-Agent-Secret"))

    manager = request.app.state.conversation_manager
    return await manager.handle_message(
        customer_id=body.customer_id,
        customer_phone=body.customer_phone,
        customer_display_name=body.customer_display_name,
        message_id=body.message_id,
        inbound_text=body.inbound_text,
        intent=body.intent,
        ticket_id=body.ticket_id,
    )

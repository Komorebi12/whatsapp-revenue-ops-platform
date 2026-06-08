from datetime import UTC, datetime
import json
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request

app = FastAPI(title="ghl-mock-server", version="0.1.0")

CONTACTS_BY_PHONE: dict[str, dict] = {}
CONTACTS_BY_ID: dict[str, dict] = {}
NOTES: list[dict] = []
OPPORTUNITIES: dict[str, dict] = {}
REQUEST_LOG: list[dict] = []


def _now() -> str:
    return datetime.now(UTC).isoformat()


async def _record(request: Request, payload: dict | None = None) -> None:
    REQUEST_LOG.append(
        {
            "at": _now(),
            "method": request.method,
            "path": request.url.path,
            "query": dict(request.query_params),
            "payload": payload or {},
        }
    )
    if len(REQUEST_LOG) > 200:
        del REQUEST_LOG[: len(REQUEST_LOG) - 200]


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/requests")
async def list_requests() -> dict[str, list[dict]]:
    return {"requests": REQUEST_LOG}


@app.post("/contacts/upsert")
async def upsert_contact(payload: dict, request: Request) -> dict:
    await _record(request, payload)
    if not payload.get("locationId"):
        raise HTTPException(status_code=400, detail="locationId is required")
    phone = str(payload.get("phone") or "").strip()
    if not phone:
        raise HTTPException(status_code=400, detail="phone is required")

    existing = CONTACTS_BY_PHONE.get(phone)
    created = existing is None
    contact_id = existing["id"] if existing else f"mock-contact-{uuid4().hex[:12]}"
    contact = {
        "id": contact_id,
        "phone": phone,
        "name": payload.get("name"),
        "firstName": payload.get("firstName"),
        "source": payload.get("source"),
        "locationId": payload.get("locationId"),
        "customFields": payload.get("customFields") or [],
        "updatedAt": _now(),
    }
    CONTACTS_BY_PHONE[phone] = contact
    CONTACTS_BY_ID[contact_id] = contact
    return {"contact": contact, "new": created}


@app.post("/contacts/{contact_id}/notes")
async def create_contact_note(contact_id: str, payload: dict, request: Request) -> dict:
    await _record(request, payload)
    if contact_id not in CONTACTS_BY_ID:
        raise HTTPException(status_code=404, detail="contact not found")
    if not payload.get("body"):
        raise HTTPException(status_code=400, detail="body is required")
    note = {
        "id": f"mock-note-{uuid4().hex[:12]}",
        "contactId": contact_id,
        "title": payload.get("title"),
        "body": payload.get("body"),
        "createdAt": _now(),
    }
    NOTES.append(note)
    return {"note": note}


@app.get("/opportunities/search")
async def search_opportunities(request: Request) -> dict:
    await _record(request)
    contact_id = request.query_params.get("contact_id")
    pipeline_id = request.query_params.get("pipeline_id")
    items = list(OPPORTUNITIES.values())
    if contact_id:
        items = [item for item in items if item.get("contactId") == contact_id]
    if pipeline_id:
        items = [item for item in items if item.get("pipelineId") == pipeline_id]
    return {"opportunities": items}


@app.post("/opportunities/")
async def create_opportunity(payload: dict, request: Request) -> dict:
    await _record(request, payload)
    for field in ("locationId", "pipelineId", "pipelineStageId", "name", "contactId"):
        if not payload.get(field):
            raise HTTPException(status_code=400, detail=f"{field} is required")
    opportunity_id = f"mock-opportunity-{uuid4().hex[:12]}"
    opportunity = {
        "id": opportunity_id,
        "locationId": payload["locationId"],
        "pipelineId": payload["pipelineId"],
        "pipelineStageId": payload["pipelineStageId"],
        "name": payload["name"],
        "status": payload.get("status", "open"),
        "contactId": payload["contactId"],
        "monetaryValue": payload.get("monetaryValue", 0),
        "createdAt": _now(),
        "updatedAt": _now(),
    }
    OPPORTUNITIES[opportunity_id] = opportunity
    return {"opportunity": opportunity}


@app.put("/opportunities/{opportunity_id}")
async def update_opportunity(opportunity_id: str, payload: dict, request: Request) -> dict:
    await _record(request, payload)
    existing = OPPORTUNITIES.get(opportunity_id)
    if existing is None:
        raise HTTPException(status_code=404, detail="opportunity not found")
    existing.update(
        {
            "pipelineId": payload.get("pipelineId", existing.get("pipelineId")),
            "pipelineStageId": payload.get("pipelineStageId", existing.get("pipelineStageId")),
            "name": payload.get("name", existing.get("name")),
            "status": payload.get("status", existing.get("status")),
            "contactId": payload.get("contactId", existing.get("contactId")),
            "monetaryValue": payload.get("monetaryValue", existing.get("monetaryValue", 0)),
            "updatedAt": _now(),
        }
    )
    return {"opportunity": existing}


@app.post("/mock-gemini/chat/completions")
async def mock_chat_completions(payload: dict, request: Request) -> dict:
    await _record(request, payload)
    messages = payload.get("messages") or []
    user_text = ""
    for message in reversed(messages):
        if message.get("role") == "user":
            user_text = str(message.get("content") or "")
            break

    lowered = user_text.lower()
    extracted = {}
    if "50" in lowered or "users" in lowered or "employees" in lowered:
        extracted["company_size"] = "50 users"
    if "5000" in lowered or "$" in lowered or "budget" in lowered:
        extracted["budget"] = "$5000"
    if "product" in lowered or "interested" in lowered:
        extracted["need"] = "CRM automation"
    if "this month" in lowered or "asap" in lowered or "urgent" in lowered:
        extracted["timeline"] = "this month"

    demo_interest = any(
        phrase in lowered
        for phrase in (
            "interested in your product",
            "crm automation",
            "book a demo",
            "pricing",
        )
    )
    if demo_interest:
        extracted.setdefault("need", "CRM automation")
        extracted.setdefault("timeline", "this month")
        extracted.setdefault("budget", "$5000")
        extracted.setdefault("company_size", "50 users")

    content = {
        "reply_text": "Thanks, that helps. I can map this to a CRM automation workflow and qualify the next step.",
        "extracted_fields": extracted,
        "customer_sentiment": "positive",
        "suggest_stage_advance": bool(extracted),
        "suggest_handoff": False,
        "handoff_reason": None,
    }
    return {
        "id": f"mock-chatcmpl-{uuid4().hex[:12]}",
        "object": "chat.completion",
        "created": int(datetime.now(UTC).timestamp()),
        "model": payload.get("model") or "mock-gemini",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": json.dumps(content),
                },
                "finish_reason": "stop",
            }
        ],
    }

from datetime import datetime

from pydantic import BaseModel, Field
from pydantic import field_validator


def _normalize_phone(value: str) -> str:
    normalized = value.strip()
    if normalized.lower().startswith("whatsapp:"):
        normalized = normalized.split(":", 1)[1].strip()
    return normalized


class ContactSyncRequest(BaseModel):
    phone: str = Field(min_length=3)
    display_name: str | None = None
    message_body: str = Field(min_length=1)
    intent: str = Field(min_length=1)
    ticket_id: str | None = None
    timestamp: datetime

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, value: str) -> str:
        return _normalize_phone(value)


class OpportunitySyncRequest(BaseModel):
    ticket_id: str = Field(min_length=1)
    phone: str = Field(min_length=3)
    status: str = Field(min_length=1)
    subject: str | None = None
    timestamp: datetime
    customer_id: str | None = None
    conversation_id: str | None = None

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, value: str) -> str:
        return _normalize_phone(value)


class SyncResponse(BaseModel):
    ok: bool = True
    message: str
    contact_id: str | None = None
    note_id: str | None = None
    opportunity_id: str | None = None
    created: bool | None = None

from datetime import datetime

from pydantic import BaseModel, Field


class AgentRespondRequest(BaseModel):
    customer_id: str = Field(min_length=1)
    customer_phone: str = Field(min_length=3)
    customer_display_name: str | None = None
    message_id: str = Field(min_length=1)
    inbound_text: str = Field(min_length=1)
    intent: str = Field(min_length=1)
    intent_confidence: float = Field(ge=0.0, le=1.0)
    ticket_id: str | None = None
    timestamp: datetime | None = None

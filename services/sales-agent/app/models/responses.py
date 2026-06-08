from pydantic import BaseModel


class GhlUpdate(BaseModel):
    should_sync: bool = False
    pipeline_stage: str | None = None
    lead_score: int | None = None


class AgentRespondResponse(BaseModel):
    action: str  # "reply" or "escalate"
    reply_text: str
    conversation_stage: str
    lead_score: int = 0
    qualification_tier: str = "unqualified"
    handoff_triggered: bool = False
    ghl_update: GhlUpdate = GhlUpdate()


class ConversationDetail(BaseModel):
    conversation_id: str
    customer_id: str
    stage: str
    turn_count: int
    qualification_data: dict
    lead_score: int
    qualification_tier: str
    created_at: str
    updated_at: str


class LeadScoreEntry(BaseModel):
    customer_id: str
    conversation_id: str
    total_score: int
    qualification_tier: str
    score_breakdown: dict
    updated_at: str

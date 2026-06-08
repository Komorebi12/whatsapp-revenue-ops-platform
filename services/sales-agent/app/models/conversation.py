from enum import StrEnum


class ConversationStage(StrEnum):
    GREETING = "greeting"
    DISCOVERY = "discovery"
    QUALIFICATION = "qualification"
    RECOMMENDATION = "recommendation"
    CLOSING = "closing"
    HANDOFF = "handoff"
    COMPLETED = "completed"


class QualificationTier(StrEnum):
    UNQUALIFIED = "unqualified"
    COLD = "cold"
    WARM = "warm"
    HOT = "hot"
    QUALIFIED = "qualified"


class Sentiment(StrEnum):
    POSITIVE = "positive"
    NEUTRAL = "neutral"
    NEGATIVE = "negative"
    FRUSTRATED = "frustrated"


# Stages considered "active" (not terminal)
ACTIVE_STAGES = frozenset({
    ConversationStage.GREETING,
    ConversationStage.DISCOVERY,
    ConversationStage.QUALIFICATION,
    ConversationStage.RECOMMENDATION,
    ConversationStage.CLOSING,
})

# Allowed stage transitions
STAGE_ORDER = [
    ConversationStage.GREETING,
    ConversationStage.DISCOVERY,
    ConversationStage.QUALIFICATION,
    ConversationStage.RECOMMENDATION,
    ConversationStage.CLOSING,
    ConversationStage.COMPLETED,
]

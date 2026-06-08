import re

from app.models.conversation import ConversationStage, Sentiment


EXPLICIT_HANDOFF_PATTERNS = re.compile(
    r"^(0|human|agent|staff|person|operator|人工|客服|转人工|真人)$",
    re.IGNORECASE,
)

COMPLEX_TOPIC_PATTERNS = re.compile(
    r"(contract|legal|SLA|enterprise|custom integration|API access|合同|法律|定制)",
    re.IGNORECASE,
)

DOLLAR_PATTERN = re.compile(r"\$[\d,]+(?:k|K|万)?")


def should_handoff(
    inbound_text: str,
    stage: ConversationStage,
    turn_count: int,
    max_turns: int,
    lead_score: int,
    recent_sentiments: list[str],
    ai_suggest_handoff: bool,
) -> tuple[bool, str | None]:
    # 1. Explicit request
    stripped = inbound_text.strip()
    if EXPLICIT_HANDOFF_PATTERNS.match(stripped):
        return True, "customer_requested_human"

    # 2. Frustrated sentiment for 2 consecutive turns
    last_two = recent_sentiments[-2:]
    if len(last_two) == 2 and all(s == Sentiment.FRUSTRATED for s in last_two):
        return True, "consecutive_frustration"

    # 3. High-value deal: score >= 70 and mentions dollar amount
    if lead_score >= 70 and DOLLAR_PATTERN.search(inbound_text):
        return True, "high_value_deal_signal"

    # 4. Stuck in qualification too long
    if turn_count >= max_turns and stage in (
        ConversationStage.DISCOVERY,
        ConversationStage.QUALIFICATION,
    ):
        return True, "stuck_conversation"

    # 5. AI suggests handoff
    if ai_suggest_handoff:
        return True, "ai_suggested_handoff"

    # 6. Complex topic detected
    if COMPLEX_TOPIC_PATTERNS.search(inbound_text):
        return True, "complex_topic_detected"

    return False, None

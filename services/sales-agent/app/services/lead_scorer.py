import re

from app.config import Settings
from app.models.conversation import QualificationTier, Sentiment


def compute_score(
    qualification_data: dict,
    turn_count: int,
    recent_sentiments: list[str],
    inbound_text: str,
) -> tuple[int, dict]:
    breakdown: dict[str, int] = {}
    total = 0

    # Stated specific need (+20)
    need = qualification_data.get("need", "")
    if need:
        breakdown["stated_need"] = 20
        total += 20

    # Timeline
    timeline = qualification_data.get("timeline", "")
    if timeline:
        urgent_patterns = r"(asap|urgent|immediately|this week|this month|now|今天|马上|尽快)"
        if re.search(urgent_patterns, timeline, re.IGNORECASE):
            breakdown["urgent_timeline"] = 15
            total += 15
        else:
            breakdown["moderate_timeline"] = 10
            total += 10

    # Budget disclosed (+15)
    budget = qualification_data.get("budget", "")
    if budget:
        breakdown["budget_disclosed"] = 15
        total += 15

    # Company size provided (+10)
    company_size = qualification_data.get("company_size", "")
    if company_size:
        breakdown["company_size_provided"] = 10
        total += 10

    # Engagement: 3+ turns (+10)
    if turn_count >= 3:
        breakdown["engaged_3_turns"] = 10
        total += 10

    # Positive sentiment in last 2 turns (+10)
    last_two = recent_sentiments[-2:] if recent_sentiments else []
    if any(s == Sentiment.POSITIVE for s in last_two):
        breakdown["positive_sentiment"] = 10
        total += 10

    # Asked about pricing/demo (+10)
    pricing_patterns = r"(price|pricing|cost|demo|trial|how much|多少钱|价格|试用)"
    if re.search(pricing_patterns, inbound_text, re.IGNORECASE):
        breakdown["asked_pricing_demo"] = 10
        total += 10

    total = min(total, 100)
    return total, breakdown


def score_to_tier(score: int, settings: Settings) -> QualificationTier:
    if score >= settings.score_tier_qualified:
        return QualificationTier.QUALIFIED
    if score >= settings.score_tier_hot:
        return QualificationTier.HOT
    if score >= settings.score_tier_warm:
        return QualificationTier.WARM
    if score >= settings.score_tier_cold:
        return QualificationTier.COLD
    return QualificationTier.UNQUALIFIED

from app.models.conversation import ConversationStage
from app.prompts.templates import QUALIFICATION_FIELDS, STAGE_INSTRUCTIONS


def build_system_prompt(
    stage: ConversationStage,
    company_name: str,
    company_product_summary: str,
    qualification_data: dict,
    history: list[dict],
) -> str:
    parts: list[str] = []

    # Base persona
    parts.append(
        f"You are a friendly WhatsApp sales assistant for {company_name}. "
        f"{company_name} offers: {company_product_summary}.\n\n"
        "Rules:\n"
        "- Keep messages short and mobile-friendly (under 300 chars unless recommending).\n"
        "- Use line breaks for readability, not long paragraphs.\n"
        "- Be conversational, not corporate. Use casual language.\n"
        "- Ask ONE question at a time.\n"
        "- Always end with a question or clear call-to-action.\n"
        "- If the customer asks to speak to a human, set suggest_handoff to true.\n"
        "- Reply in the same language the customer uses."
    )

    # Stage-specific instructions
    stage_key = stage.value
    if stage_key in STAGE_INSTRUCTIONS:
        instruction = STAGE_INSTRUCTIONS[stage_key].format(company_name=company_name)
        parts.append(f"\n\nCURRENT STAGE: {stage_key}\n{instruction}")

    # Qualification status
    collected = {k: v for k, v in qualification_data.items() if v}
    missing = [f for f in QUALIFICATION_FIELDS if f not in collected]
    if collected:
        items = ", ".join(f"{k}={v}" for k, v in collected.items())
        parts.append(f"\n\nAlready collected: {items}")
    if missing:
        parts.append(f"Still need: {', '.join(missing)}")
    if not missing and stage in (ConversationStage.DISCOVERY, ConversationStage.QUALIFICATION):
        parts.append("All qualification fields collected — set suggest_stage_advance to true.")

    # Conversation history
    if history:
        parts.append("\n\nConversation so far:")
        for msg in history[-10:]:
            role_label = "Customer" if msg["role"] == "customer" else "You"
            parts.append(f"{role_label}: {msg['content']}")

    return "\n".join(parts)

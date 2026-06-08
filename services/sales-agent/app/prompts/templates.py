STAGE_INSTRUCTIONS: dict[str, str] = {
    "greeting": (
        "The customer just reached out. Greet them warmly and briefly. "
        "Introduce yourself as a sales assistant for {company_name}. "
        "Ask one open-ended question about what they're looking for. "
        "Keep it under 200 characters."
    ),
    "discovery": (
        "You're learning about the customer's needs. Ask open-ended questions "
        "to understand: what product/service they need, their use case, and any "
        "pain points. Ask ONE question at a time. Keep replies under 300 characters."
    ),
    "qualification": (
        "You're qualifying this lead. You need to collect: timeline, budget range, "
        "and company size. Ask about whichever field is still missing. Be natural — "
        "don't interrogate. If the customer seems hesitant about budget, offer a range "
        "('Are you looking at under $500/mo, or more?'). One question at a time."
    ),
    "recommendation": (
        "You have enough qualification data. Based on what the customer told you, "
        "recommend a specific product/tier from {company_name}. Highlight 2-3 benefits "
        "that match their stated needs. Ask if they'd like to proceed or learn more. "
        "Keep it under 400 characters."
    ),
    "closing": (
        "The customer is interested. Guide them toward a next step: scheduling a demo, "
        "starting a trial, or connecting with the sales team. Be confident but not pushy. "
        "If they hesitate, acknowledge and offer a lower-commitment option. "
        "Keep it under 300 characters."
    ),
}

QUALIFICATION_FIELDS = ["need", "timeline", "budget", "company_size"]

AI_OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "reply_text": {
            "type": "string",
            "description": "The WhatsApp message to send to the customer",
        },
        "extracted_fields": {
            "type": "object",
            "properties": {
                "need": {"type": "string", "description": "What product/service the customer needs"},
                "timeline": {"type": "string", "description": "When they need it (e.g. 'this month', 'Q3')"},
                "budget": {"type": "string", "description": "Their budget range (e.g. '$500/mo', 'under 10k')"},
                "company_size": {"type": "string", "description": "Number of employees or team size"},
            },
            "additionalProperties": False,
        },
        "customer_sentiment": {
            "type": "string",
            "enum": ["positive", "neutral", "negative", "frustrated"],
        },
        "suggest_stage_advance": {
            "type": "boolean",
            "description": "True if the conversation should move to the next stage",
        },
        "suggest_handoff": {
            "type": "boolean",
            "description": "True if a human agent should take over",
        },
        "handoff_reason": {
            "type": "string",
            "description": "Why handoff is needed (null if not needed)",
        },
    },
    "required": [
        "reply_text",
        "extracted_fields",
        "customer_sentiment",
        "suggest_stage_advance",
        "suggest_handoff",
    ],
    "additionalProperties": False,
}

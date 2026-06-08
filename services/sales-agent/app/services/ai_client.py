import json
import logging
import time
from dataclasses import dataclass

import httpx

from app.prompts.templates import AI_OUTPUT_SCHEMA

logger = logging.getLogger(__name__)


class AiClientError(Exception):
    pass


@dataclass
class AiResponse:
    reply_text: str
    extracted_fields: dict
    customer_sentiment: str
    suggest_stage_advance: bool
    suggest_handoff: bool
    handoff_reason: str | None
    raw_response: dict
    latency_ms: int


FALLBACK_REPLY = (
    "Thanks for your message! Let me look into this and get back to you shortly. "
    "Reply 0 anytime for human support."
)


class AiClient:
    def __init__(self, api_key: str, base_url: str, model: str, timeout: int = 10):
        self._model = model
        self._timeout = timeout
        self._client = httpx.AsyncClient(
            base_url=base_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            timeout=httpx.Timeout(timeout, connect=5.0),
        )

    async def generate(self, system_prompt: str, user_message: str) -> AiResponse:
        start = time.monotonic()
        payload = {
            "model": self._model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            "temperature": 0.7,
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "sales_agent_response",
                    "strict": True,
                    "schema": AI_OUTPUT_SCHEMA,
                },
            },
        }

        try:
            resp = await self._client.post("/chat/completions", json=payload)
            resp.raise_for_status()
            data = resp.json()
            content_str = data["choices"][0]["message"]["content"]
            parsed = json.loads(content_str)
            latency = int((time.monotonic() - start) * 1000)

            return AiResponse(
                reply_text=parsed.get("reply_text", FALLBACK_REPLY),
                extracted_fields=parsed.get("extracted_fields", {}),
                customer_sentiment=parsed.get("customer_sentiment", "neutral"),
                suggest_stage_advance=parsed.get("suggest_stage_advance", False),
                suggest_handoff=parsed.get("suggest_handoff", False),
                handoff_reason=parsed.get("handoff_reason"),
                raw_response=data,
                latency_ms=latency,
            )
        except (httpx.HTTPError, json.JSONDecodeError, KeyError, IndexError) as exc:
            latency = int((time.monotonic() - start) * 1000)
            logger.error("AI generation failed: %s", exc)
            return AiResponse(
                reply_text=FALLBACK_REPLY,
                extracted_fields={},
                customer_sentiment="neutral",
                suggest_stage_advance=False,
                suggest_handoff=False,
                handoff_reason=None,
                raw_response={"error": str(exc)},
                latency_ms=latency,
            )

    async def close(self) -> None:
        await self._client.aclose()

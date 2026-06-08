import logging
from datetime import UTC, datetime

import httpx

logger = logging.getLogger(__name__)


def _timestamp_or_now(timestamp: str | None) -> str:
    return timestamp or datetime.now(UTC).isoformat()


class GhlSyncClient:
    def __init__(self, base_url: str, auth_secret: str):
        self._client = httpx.AsyncClient(
            base_url=base_url,
            headers={"X-Sync-Secret": auth_secret},
            timeout=httpx.Timeout(10.0, connect=5.0),
        )

    async def sync_contact(
        self,
        phone: str,
        display_name: str | None,
        message_body: str,
        intent: str,
        ticket_id: str | None = None,
        timestamp: str | None = None,
    ) -> dict | None:
        payload = {
            "phone": phone,
            "display_name": display_name or "WhatsApp User",
            "message_body": message_body,
            "intent": intent,
            "timestamp": _timestamp_or_now(timestamp),
        }
        if ticket_id:
            payload["ticket_id"] = ticket_id
        try:
            resp = await self._client.post("/sync/contact", json=payload)
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as exc:
            logger.error("GHL contact sync failed: %s", exc)
            return None

    async def sync_opportunity(
        self,
        ticket_id: str,
        phone: str,
        status: str,
        subject: str | None = None,
        timestamp: str | None = None,
        customer_id: str | None = None,
        conversation_id: str | None = None,
    ) -> dict | None:
        payload = {
            "ticket_id": ticket_id,
            "phone": phone,
            "status": status,
            "timestamp": _timestamp_or_now(timestamp),
        }
        if subject:
            payload["subject"] = subject
        if customer_id:
            payload["customer_id"] = customer_id
        if conversation_id:
            payload["conversation_id"] = conversation_id
        try:
            resp = await self._client.post("/sync/opportunity", json=payload)
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as exc:
            logger.error("GHL opportunity sync failed: %s", exc)
            return None

    async def close(self) -> None:
        await self._client.aclose()

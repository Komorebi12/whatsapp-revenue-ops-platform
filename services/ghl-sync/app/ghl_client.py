import asyncio
import time
from collections import deque
from collections.abc import Sequence
from typing import Any

import httpx

from app.config import Settings


class GhlApiError(RuntimeError):
    pass


class SlidingWindowRateLimiter:
    def __init__(self, max_requests: int, window_seconds: float) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._timestamps: deque[float] = deque()
        self._lock = asyncio.Lock()

    async def acquire(self) -> None:
        while True:
            async with self._lock:
                now = time.monotonic()
                while self._timestamps and now - self._timestamps[0] >= self.window_seconds:
                    self._timestamps.popleft()

                if len(self._timestamps) < self.max_requests:
                    self._timestamps.append(now)
                    return

                sleep_for = self.window_seconds - (now - self._timestamps[0])

            await asyncio.sleep(max(sleep_for, 0.01))


class GhlClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._client = httpx.AsyncClient(
            base_url=settings.ghl_api_base_url,
            timeout=httpx.Timeout(30.0),
            headers={
                "Authorization": f"Bearer {settings.ghl_api_token}",
                "Version": settings.ghl_api_version,
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        self._limiter = SlidingWindowRateLimiter(max_requests=90, window_seconds=10.0)

    async def close(self) -> None:
        await self._client.aclose()

    async def _request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        retries = 4
        last_error: Exception | None = None

        for attempt in range(retries):
            await self._limiter.acquire()
            try:
                response = await self._client.request(method, path, params=params, json=json)
            except httpx.HTTPError as exc:
                last_error = exc
                await asyncio.sleep(0.5 * (2**attempt))
                continue

            if response.status_code in {429, 500, 502, 503, 504}:
                retry_after = response.headers.get("Retry-After")
                if retry_after:
                    try:
                        await asyncio.sleep(float(retry_after))
                    except ValueError:
                        await asyncio.sleep(0.5 * (2**attempt))
                else:
                    await asyncio.sleep(0.5 * (2**attempt))
                last_error = GhlApiError(f"GHL temporary error {response.status_code}: {response.text}")
                continue

            if response.is_error:
                raise GhlApiError(f"GHL request failed {response.status_code}: {response.text}")

            if not response.content:
                return {}

            return response.json()

        raise GhlApiError(f"GHL request exhausted retries: {last_error}")

    async def upsert_contact(
        self,
        *,
        phone: str,
        display_name: str | None,
        intent: str,
        timestamp_iso: str,
        write_custom_fields: bool = True,
    ) -> tuple[str, bool]:
        payload = {
            "locationId": self.settings.ghl_location_id,
            "phone": phone,
            "name": display_name or "WhatsApp User",
            "firstName": display_name or "WhatsApp",
            "source": self.settings.sync_source_system,
        }
        if write_custom_fields:
            custom_field: dict[str, Any] = {
                "key": self.settings.ghl_intent_field_key,
                "field_value": intent,
            }
            if self.settings.ghl_intent_field_id:
                custom_field["id"] = self.settings.ghl_intent_field_id
            payload["customFields"] = [custom_field]

        data = await self._request("POST", "/contacts/upsert", json=payload)
        contact = data.get("contact") or {}
        contact_id = (
            contact.get("id")
            or contact.get("_id")
            or data.get("contactId")
            or data.get("id")
        )
        if not contact_id:
            raise GhlApiError(f"Could not determine contact id from upsert response: {data}")

        created = bool(data.get("new", False))
        return str(contact_id), created

    async def create_contact_note(self, contact_id: str, body: str, title: str | None = None) -> str | None:
        payload = {"body": body}
        if title:
            payload["title"] = title
        data = await self._request("POST", f"/contacts/{contact_id}/notes", json=payload)
        note = data.get("note") or {}
        return note.get("id") or note.get("_id") or data.get("id")

    async def search_opportunities(self, *, contact_id: str) -> list[dict[str, Any]]:
        params = {
            "location_id": self.settings.ghl_location_id,
            "pipeline_id": self.settings.ghl_pipeline_id,
            "contact_id": contact_id,
            "limit": 100,
        }
        data = await self._request("GET", "/opportunities/search", params=params)
        return data.get("opportunities") or []

    async def create_opportunity(
        self,
        *,
        contact_id: str,
        name: str,
        stage_id: str,
        status: str,
    ) -> tuple[str, bool]:
        payload = {
            "pipelineId": self.settings.ghl_pipeline_id,
            "locationId": self.settings.ghl_location_id,
            "name": name,
            "pipelineStageId": stage_id,
            "status": status,
            "contactId": contact_id,
            "monetaryValue": 0,
        }
        data = await self._request("POST", "/opportunities/", json=payload)
        opp = data.get("opportunity") or {}
        opportunity_id = opp.get("id") or opp.get("_id") or data.get("id")
        if not opportunity_id:
            raise GhlApiError(f"Could not determine opportunity id from create response: {data}")
        return str(opportunity_id), True

    async def update_opportunity(
        self,
        *,
        opportunity_id: str,
        contact_id: str,
        name: str,
        stage_id: str,
        status: str,
    ) -> str:
        payload = {
            "pipelineId": self.settings.ghl_pipeline_id,
            "name": name,
            "pipelineStageId": stage_id,
            "status": status,
            "contactId": contact_id,
            "monetaryValue": 0,
        }
        data = await self._request("PUT", f"/opportunities/{opportunity_id}", json=payload)
        opp = data.get("opportunity") or {}
        updated_id = opp.get("id") or opp.get("_id") or data.get("id") or opportunity_id
        return str(updated_id)


def summarize_message(message_body: str, intent: str, ticket_id: str | None = None) -> str:
    compact = " ".join(message_body.split()).strip()
    if ticket_id:
        return f'[Auto] Latest message: "{compact}" | Intent: {intent} | Ticket: #{ticket_id}'
    return f'[Auto] Latest message: "{compact}" | Intent: {intent}'


def map_ticket_status(status: str, settings: Settings) -> tuple[str, str]:
    normalized = status.strip().lower()
    if normalized == "open":
        return settings.ghl_stage_lead_capture_id, "open"
    if normalized == "awaiting_staff":
        return settings.ghl_stage_qualification_id, "open"
    if normalized in {"resolved", "closed"}:
        return settings.ghl_stage_won_id, "won"
    if normalized == "abandoned":
        return settings.ghl_stage_lost_id, "lost"
    raise GhlApiError(f"Unsupported ticket status for GHL mapping: {status}")


def extract_contact_id_from_opportunity(item: dict[str, Any]) -> str | None:
    candidates: Sequence[Any] = (
        item.get("contactId"),
        item.get("contact_id"),
        (item.get("contact") or {}).get("id"),
    )
    for candidate in candidates:
        if candidate:
            return str(candidate)
    return None

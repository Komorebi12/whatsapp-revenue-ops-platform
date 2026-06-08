from fastapi import APIRouter, Request

from app.db import repositories as repo

router = APIRouter(prefix="/agent", tags=["admin"])


@router.get("/conversations")
async def list_conversations(
    request: Request, limit: int = 50, offset: int = 0
) -> list[dict]:
    pool = request.app.state.pool
    rows = await repo.list_conversations(pool, limit=limit, offset=offset)
    for row in rows:
        for key in row:
            val = row[key]
            if hasattr(val, "isoformat"):
                row[key] = val.isoformat()
    return rows


@router.get("/lead-scores")
async def list_lead_scores(
    request: Request, limit: int = 50, offset: int = 0
) -> list[dict]:
    pool = request.app.state.pool
    rows = await repo.list_lead_scores(pool, limit=limit, offset=offset)
    for row in rows:
        for key in row:
            val = row[key]
            if hasattr(val, "isoformat"):
                row[key] = val.isoformat()
    return rows

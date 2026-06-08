import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import get_settings
from app.database import close_pool, init_pool
from app.routers.admin import router as admin_router
from app.routers.agent import router as agent_router
from app.services.ai_client import AiClient
from app.services.conversation_manager import ConversationManager
from app.services.ghl_sync_client import GhlSyncClient


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO))

    pool = await init_pool(settings.database_url)
    ai_client = AiClient(
        api_key=settings.gemini_api_key,
        base_url=settings.gemini_base_url,
        model=settings.gemini_model,
        timeout=settings.ai_timeout_seconds,
    )
    ghl_client = GhlSyncClient(
        base_url=settings.ghl_sync_base_url,
        auth_secret=settings.ghl_sync_auth_secret,
    )

    app.state.settings = settings
    app.state.pool = pool
    app.state.conversation_manager = ConversationManager(
        pool=pool,
        ai_client=ai_client,
        ghl_client=ghl_client,
        settings=settings,
    )

    try:
        yield
    finally:
        await ai_client.close()
        await ghl_client.close()
        await close_pool()


app = FastAPI(title="sales-agent", version="0.1.0", lifespan=lifespan)
app.include_router(agent_router)
app.include_router(admin_router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import get_settings
from app.ghl_client import GhlClient
from app.revenue_events import close_revenue_pool, init_revenue_pool
from app.routers.sync import router as sync_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO))
    app.state.settings = settings
    app.state.ghl_client = GhlClient(settings)
    app.state.revenue_pool = await init_revenue_pool(settings.revenue_database_url)
    try:
        yield
    finally:
        await close_revenue_pool(app.state.revenue_pool)
        await app.state.ghl_client.close()


app = FastAPI(title="ghl-sync", version="0.1.0", lifespan=lifespan)
app.include_router(sync_router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}

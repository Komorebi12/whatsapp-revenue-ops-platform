from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

from app.config import Settings, get_settings
from app.models.schemas import CollectionStatus
from app.routers import chat, upload
from app.services.vector_store import QdrantVectorStore, VectorStoreError

app = FastAPI(
    title="RAG Knowledge Base Demo",
    description="Upload text PDFs, store chunks in Qdrant, and ask cited questions with Gemini.",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(upload.router)
app.include_router(chat.router)


@app.get("/health")
def health(settings: Settings = Depends(get_settings)) -> dict[str, object]:
    return {
        "status": "ok",
        "mock_mode": settings.use_mock,
        "gemini_configured": settings.has_gemini_credentials,
        "qdrant_configured": settings.has_qdrant_credentials,
        "collection": settings.qdrant_collection,
    }


@app.get("/collection", response_model=CollectionStatus)
def collection_status(settings: Settings = Depends(get_settings)) -> CollectionStatus:
    try:
        return QdrantVectorStore(settings).collection_status()
    except VectorStoreError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

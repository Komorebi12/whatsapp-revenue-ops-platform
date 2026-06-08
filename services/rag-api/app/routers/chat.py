from fastapi import APIRouter, Depends, HTTPException, status

from app.config import Settings, get_settings
from app.models.schemas import ChatRequest, ChatResponse
from app.services.embedder import EmbeddingError
from app.services.llm import LlmError
from app.services import mock_rag
from app.services.rag import RagService
from app.services.vector_store import VectorStoreError

router = APIRouter(tags=["chat"])


@router.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest, settings: Settings = Depends(get_settings)) -> ChatResponse:
    if settings.use_mock:
        return mock_rag.answer_question(
            question=request.question,
            filename=request.filename,
            history=request.history,
        )

    try:
        return RagService(settings).ask(
            question=request.question,
            filename=request.filename,
            history=request.history,
        )
    except EmbeddingError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
    except LlmError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
    except VectorStoreError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

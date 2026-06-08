from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from app.config import Settings, get_settings
from app.models.schemas import UploadResponse
from app.services.embedder import EmbeddingError, GeminiEmbedder
from app.services import mock_rag
from app.services.pdf_parser import PdfParsingError, parse_pdf_to_chunks
from app.services.vector_store import QdrantVectorStore, VectorStoreError

router = APIRouter(prefix="/documents", tags=["documents"])


@router.post("/upload", response_model=UploadResponse)
def upload_document(
    file: UploadFile = File(...),
    settings: Settings = Depends(get_settings),
) -> UploadResponse:
    filename = file.filename or "uploaded.pdf"
    if Path(filename).suffix.lower() != ".pdf":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only single-column text PDFs are supported in this demo.",
        )

    if settings.use_mock:
        return mock_rag.upload_document(filename)

    try:
        file_bytes = file.file.read()
        pages, chunks = parse_pdf_to_chunks(file_bytes, filename, settings)
        vectors = GeminiEmbedder(settings).embed_texts([chunk.text for chunk in chunks])
        stored_count = QdrantVectorStore(settings).upsert_chunks(chunks, vectors)
    except PdfParsingError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except EmbeddingError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
    except VectorStoreError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    return UploadResponse(
        filename=filename,
        pages=pages,
        chunks=stored_count,
        message="Document processed and stored successfully.",
    )


@router.delete("/collection", status_code=status.HTTP_204_NO_CONTENT)
def reset_collection(settings: Settings = Depends(get_settings)) -> None:
    try:
        QdrantVectorStore(settings).reset_collection()
    except VectorStoreError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

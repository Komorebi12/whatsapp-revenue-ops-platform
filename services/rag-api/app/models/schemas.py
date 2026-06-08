from pydantic import BaseModel, Field


class DocumentChunk(BaseModel):
    text: str
    filename: str
    page: int = Field(ge=1)
    chunk_index: int = Field(ge=0)


class UploadResponse(BaseModel):
    filename: str
    pages: int
    chunks: int
    message: str


class ChatRequest(BaseModel):
    question: str = Field(min_length=1)
    filename: str | None = None
    history: list[dict[str, str]] = Field(default_factory=list)


class SourceChunk(BaseModel):
    text: str
    filename: str
    page: int
    chunk_index: int
    score: float | None = None


class ChatResponse(BaseModel):
    answer: str
    sources: list[SourceChunk]


class CollectionStatus(BaseModel):
    collection: str
    vectors: int | None = None
    status: str

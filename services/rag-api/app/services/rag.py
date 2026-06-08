from app.config import Settings
from app.models.schemas import ChatResponse
from app.services.embedder import GeminiEmbedder
from app.services.llm import GeminiLlm, build_chat_response
from app.services.vector_store import QdrantVectorStore


class RagService:
    def __init__(
        self,
        settings: Settings,
        embedder: GeminiEmbedder | None = None,
        vector_store: QdrantVectorStore | None = None,
        llm: GeminiLlm | None = None,
    ):
        self.settings = settings
        self.embedder = embedder or GeminiEmbedder(settings)
        self.vector_store = vector_store or QdrantVectorStore(settings)
        self.llm = llm or GeminiLlm(settings)

    def ask(self, question: str, filename: str | None = None, history: list[dict[str, str]] | None = None) -> ChatResponse:
        query_vector = self.embedder.embed_text(question)
        sources = self.vector_store.search(
            query_vector=query_vector,
            top_k=self.settings.top_k,
            filename=filename,
        )
        answer = self.llm.answer(question=question, sources=sources, history=history or [])
        return build_chat_response(answer=answer, sources=sources)

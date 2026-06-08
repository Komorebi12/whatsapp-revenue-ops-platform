import time
from collections.abc import Iterable

from google import genai
from google.genai import types

from app.config import Settings


class EmbeddingError(RuntimeError):
    pass


class GeminiEmbedder:
    def __init__(self, settings: Settings):
        if not settings.has_gemini_credentials:
            raise EmbeddingError("GEMINI_API_KEY is required for embedding generation.")

        self.settings = settings
        self.client = genai.Client(api_key=settings.gemini_api_key)

    def embed_text(self, text: str) -> list[float]:
        embeddings = self.embed_texts([text], task_type="RETRIEVAL_QUERY")
        return embeddings[0]

    def embed_texts(self, texts: list[str], task_type: str = "RETRIEVAL_DOCUMENT") -> list[list[float]]:
        if not texts:
            return []

        vectors: list[list[float]] = []
        batches = list(_batched(texts, self.settings.embedding_batch_size))

        for index, batch in enumerate(batches):
            vectors.extend(self._embed_batch(batch, task_type=task_type))
            if index < len(batches) - 1:
                time.sleep(self.settings.embedding_batch_sleep_seconds)

        return vectors

    def _embed_batch(self, texts: list[str], task_type: str) -> list[list[float]]:
        last_error: Exception | None = None

        for attempt in range(3):
            try:
                response = self.client.models.embed_content(
                    model=self.settings.embedding_model,
                    contents=texts,
                    config=types.EmbedContentConfig(
                        task_type=task_type,
                        output_dimensionality=self.settings.embedding_dimension,
                    ),
                )
                return [_extract_embedding_values(item) for item in response.embeddings or []]
            except Exception as exc:
                last_error = exc
                time.sleep(2**attempt)

        raise EmbeddingError(f"Gemini embedding failed after retries: {last_error}") from last_error


def _extract_embedding_values(embedding) -> list[float]:
    values = getattr(embedding, "values", None)
    if values is None and isinstance(embedding, dict):
        values = embedding.get("values")
    if not values:
        raise EmbeddingError("Gemini returned an empty embedding.")
    return [float(value) for value in values]


def _batched(items: list[str], batch_size: int) -> Iterable[list[str]]:
    safe_batch_size = max(1, batch_size)
    for start in range(0, len(items), safe_batch_size):
        yield items[start : start + safe_batch_size]

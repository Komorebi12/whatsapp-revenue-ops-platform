from uuid import uuid5, NAMESPACE_URL

from qdrant_client import QdrantClient, models

from app.config import Settings
from app.models.schemas import CollectionStatus, DocumentChunk, SourceChunk


class VectorStoreError(RuntimeError):
    pass


class QdrantVectorStore:
    def __init__(self, settings: Settings):
        if not settings.has_qdrant_credentials:
            raise VectorStoreError("QDRANT_URL and QDRANT_API_KEY are required for vector storage.")

        self.settings = settings
        self.collection_name = settings.qdrant_collection
        self.client = QdrantClient(url=str(settings.qdrant_url), api_key=settings.qdrant_api_key)

    def ensure_collection(self) -> None:
        try:
            collection_exists = self.client.collection_exists(self.collection_name)
            if not collection_exists:
                self.client.create_collection(
                    collection_name=self.collection_name,
                    vectors_config=models.VectorParams(
                        size=self.settings.embedding_dimension,
                        distance=models.Distance.COSINE,
                    ),
                )
        except Exception as exc:
            raise VectorStoreError(f"Qdrant collection setup failed: {exc}") from exc

        self._ensure_filename_index()

    def _ensure_filename_index(self) -> None:
        try:
            self.client.create_payload_index(
                collection_name=self.collection_name,
                field_name="filename",
                field_schema=models.PayloadSchemaType.KEYWORD,
                wait=True,
            )
        except Exception as exc:
            if "already exists" in str(exc).lower():
                return
            raise VectorStoreError(f"Qdrant filename index setup failed: {exc}") from exc

    def upsert_chunks(self, chunks: list[DocumentChunk], vectors: list[list[float]]) -> int:
        if len(chunks) != len(vectors):
            raise VectorStoreError("Chunk count and vector count do not match.")

        self.ensure_collection()
        points = [
            models.PointStruct(
                id=_chunk_id(chunk),
                vector=vector,
                payload=chunk.model_dump(),
            )
            for chunk, vector in zip(chunks, vectors, strict=True)
        ]

        if points:
            try:
                self.client.upsert(collection_name=self.collection_name, points=points, wait=True)
            except Exception as exc:
                raise VectorStoreError(f"Qdrant upsert failed: {exc}") from exc

        return len(points)

    def collection_status(self) -> CollectionStatus:
        try:
            if not self.client.collection_exists(self.collection_name):
                return CollectionStatus(collection=self.collection_name, vectors=0, status="missing")

            info = self.client.get_collection(self.collection_name)
        except Exception as exc:
            raise VectorStoreError(f"Qdrant collection status failed: {exc}") from exc

        vectors_count = getattr(info, "vectors_count", None)
        if vectors_count is None:
            vectors_count = getattr(info, "points_count", None)

        return CollectionStatus(
            collection=self.collection_name,
            vectors=vectors_count,
            status=str(getattr(info, "status", "ok")),
        )

    def reset_collection(self) -> None:
        try:
            if self.client.collection_exists(self.collection_name):
                self.client.delete_collection(self.collection_name)
        except Exception as exc:
            raise VectorStoreError(f"Qdrant collection reset failed: {exc}") from exc

        self.ensure_collection()

    def search(
        self,
        query_vector: list[float],
        top_k: int,
        filename: str | None = None,
    ) -> list[SourceChunk]:
        self.ensure_collection()
        try:
            results = self.client.query_points(
                collection_name=self.collection_name,
                query=query_vector,
                query_filter=build_filename_filter(filename),
                limit=top_k,
                with_payload=True,
            )
        except Exception as exc:
            raise VectorStoreError(f"Qdrant search failed: {exc}") from exc

        return [point_to_source_chunk(point) for point in results.points]


def build_filename_filter(filename: str | None) -> models.Filter | None:
    if not filename:
        return None
    return models.Filter(
        must=[
            models.FieldCondition(
                key="filename",
                match=models.MatchValue(value=filename),
            )
        ]
    )


def point_to_source_chunk(point) -> SourceChunk:
    payload = point.payload or {}
    return SourceChunk(
        text=str(payload.get("text", "")),
        filename=str(payload.get("filename", "")),
        page=int(payload.get("page", 0) or 0),
        chunk_index=int(payload.get("chunk_index", 0) or 0),
        score=float(point.score) if getattr(point, "score", None) is not None else None,
    )


def _chunk_id(chunk: DocumentChunk) -> str:
    return str(uuid5(NAMESPACE_URL, f"{chunk.filename}:{chunk.page}:{chunk.chunk_index}:{chunk.text[:64]}"))

from functools import lru_cache
from pathlib import Path

from pydantic import Field, HttpUrl
from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=str(_ENV_FILE), env_file_encoding="utf-8", extra="ignore")

    gemini_api_key: str = Field(default="", alias="GEMINI_API_KEY")
    mock_mode: bool = Field(default=False, alias="MOCK_MODE")
    qdrant_url: HttpUrl | str = Field(default="", alias="QDRANT_URL")
    qdrant_api_key: str = Field(default="", alias="QDRANT_API_KEY")
    qdrant_collection: str = Field(default="default", alias="QDRANT_COLLECTION")
    embedding_model: str = Field(default="gemini-embedding-001", alias="EMBEDDING_MODEL")
    embedding_dimension: int = Field(default=3072, alias="EMBEDDING_DIMENSION")
    llm_model: str = Field(default="gemini-2.5-flash", alias="LLM_MODEL")
    chunk_size: int = Field(default=500, alias="CHUNK_SIZE")
    chunk_overlap: int = Field(default=100, alias="CHUNK_OVERLAP")
    embedding_batch_size: int = Field(default=20, alias="EMBEDDING_BATCH_SIZE")
    embedding_batch_sleep_seconds: float = Field(default=4, alias="EMBEDDING_BATCH_SLEEP_SECONDS")
    top_k: int = Field(default=5, alias="TOP_K")

    @property
    def has_gemini_credentials(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def use_mock(self) -> bool:
        return self.mock_mode and not self.has_gemini_credentials

    @property
    def has_qdrant_credentials(self) -> bool:
        return bool(self.qdrant_url and self.qdrant_api_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()

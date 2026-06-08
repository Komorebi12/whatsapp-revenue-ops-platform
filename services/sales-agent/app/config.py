from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Gemini
    gemini_api_key: str = Field(alias="GEMINI_API_KEY")
    gemini_model: str = Field(default="gemini-flash-latest", alias="GEMINI_MODEL")
    gemini_base_url: str = Field(
        default="https://generativelanguage.googleapis.com/v1beta/openai",
        alias="GEMINI_BASE_URL",
    )

    # Postgres
    database_url: str = Field(alias="DATABASE_URL")

    # GHL Sync
    ghl_sync_base_url: str = Field(default="http://127.0.0.1:8010", alias="GHL_SYNC_BASE_URL")
    ghl_sync_auth_secret: str = Field(alias="GHL_SYNC_AUTH_SECRET")

    # Service
    agent_port: int = Field(default=8020, alias="AGENT_PORT")
    agent_auth_secret: str = Field(alias="AGENT_AUTH_SECRET")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")

    # Scoring thresholds
    score_tier_cold: int = Field(default=20, alias="SCORE_TIER_COLD")
    score_tier_warm: int = Field(default=40, alias="SCORE_TIER_WARM")
    score_tier_hot: int = Field(default=60, alias="SCORE_TIER_HOT")
    score_tier_qualified: int = Field(default=80, alias="SCORE_TIER_QUALIFIED")

    # Conversation limits
    max_turns_before_handoff: int = Field(default=12, alias="MAX_TURNS_BEFORE_HANDOFF")
    max_context_messages: int = Field(default=10, alias="MAX_CONTEXT_MESSAGES")
    ai_timeout_seconds: int = Field(default=10, alias="AI_TIMEOUT_SECONDS")

    # Company context
    company_name: str = Field(default="Demo Corp", alias="COMPANY_NAME")
    company_product_summary: str = Field(
        default="CRM and automation solutions for SMBs",
        alias="COMPANY_PRODUCT_SUMMARY",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()

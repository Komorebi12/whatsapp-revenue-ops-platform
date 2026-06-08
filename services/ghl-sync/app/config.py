from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    ghl_api_token: str = Field(alias="GHL_API_TOKEN")
    ghl_location_id: str = Field(alias="GHL_LOCATION_ID")
    ghl_pipeline_id: str = Field(alias="GHL_PIPELINE_ID")
    ghl_stage_lead_capture_id: str = Field(alias="GHL_STAGE_LEAD_CAPTURE_ID")
    ghl_stage_qualification_id: str = Field(alias="GHL_STAGE_QUALIFICATION_ID")
    ghl_stage_won_id: str = Field(alias="GHL_STAGE_WON_ID")
    ghl_stage_lost_id: str = Field(alias="GHL_STAGE_LOST_ID")
    ghl_intent_field_key: str = Field(alias="GHL_INTENT_FIELD_KEY")
    ghl_intent_field_id: str | None = Field(default=None, alias="GHL_INTENT_FIELD_ID")
    ghl_api_base_url: str = Field(
        default="https://services.leadconnectorhq.com", alias="GHL_API_BASE_URL"
    )
    ghl_api_version: str = Field(default="2021-07-28", alias="GHL_API_VERSION")
    sync_auth_secret: str = Field(alias="SYNC_AUTH_SECRET")
    sync_source_system: str = Field(default="whatsapp_mvp", alias="SYNC_SOURCE_SYSTEM")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    revenue_database_url: str | None = Field(default=None, alias="DATABASE_URL")


@lru_cache
def get_settings() -> Settings:
    return Settings()

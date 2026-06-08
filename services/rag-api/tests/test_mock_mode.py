from io import BytesIO

from app.config import Settings
from app.models.schemas import ChatResponse
from app.routers.chat import chat
from app.routers.upload import upload_document
from app.models.schemas import ChatRequest, SourceChunk


class DummyUpload:
    def __init__(self, filename: str = "demo-company-policy.pdf"):
        self.filename = filename
        self.file = BytesIO(b"%PDF-1.4 mock bytes")


def mock_settings(**overrides) -> Settings:
    values = {
        "MOCK_MODE": True,
        "GEMINI_API_KEY": "",
        "QDRANT_URL": "http://qdrant:6333",
        "QDRANT_API_KEY": "local-dev-dummy-key",
        "QDRANT_COLLECTION": "whatsapp_demo_knowledge",
    }
    values.update(overrides)
    return Settings(**values)


def test_settings_use_mock_only_when_mock_mode_enabled_and_gemini_key_missing():
    assert mock_settings().use_mock is True
    assert mock_settings(GEMINI_API_KEY="real-key").use_mock is False
    assert mock_settings(MOCK_MODE=False).use_mock is False


def test_chat_returns_deterministic_mock_answer_without_gemini_key():
    response = chat(
        ChatRequest(question="What is your return policy?"),
        settings=mock_settings(),
    )

    assert response.answer
    assert "mock" in response.answer.lower()
    assert response.sources
    assert response.sources[0].filename == "demo-company-policy.pdf"


def test_upload_returns_deterministic_mock_response_without_parsing_pdf_or_gemini_key():
    response = upload_document(
        file=DummyUpload(),
        settings=mock_settings(),
    )

    assert response.filename == "demo-company-policy.pdf"
    assert response.pages >= 1
    assert response.chunks >= 1
    assert "mock" in response.message.lower()


def test_chat_uses_real_service_branch_when_gemini_key_exists(monkeypatch):
    calls = []

    class FakeRagService:
        def __init__(self, settings):
            calls.append(settings)

        def ask(self, question, filename=None, history=None):
            return ChatResponse(
                answer="real branch",
                sources=[
                    SourceChunk(
                        text="real source",
                        filename="real.pdf",
                        page=1,
                        chunk_index=0,
                    )
                ],
            )

    monkeypatch.setattr("app.routers.chat.RagService", FakeRagService)

    response = chat(
        ChatRequest(question="What is your return policy?"),
        settings=mock_settings(GEMINI_API_KEY="real-key"),
    )

    assert response.answer == "real branch"
    assert len(calls) == 1

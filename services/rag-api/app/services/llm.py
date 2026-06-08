from google import genai

from app.config import Settings
from app.models.schemas import ChatResponse, SourceChunk


class LlmError(RuntimeError):
    pass


class GeminiLlm:
    def __init__(self, settings: Settings):
        if not settings.has_gemini_credentials:
            raise LlmError("GEMINI_API_KEY is required for answer generation.")

        self.settings = settings
        self.client = genai.Client(api_key=settings.gemini_api_key)

    def answer(self, question: str, sources: list[SourceChunk], history: list[dict[str, str]] | None = None) -> str:
        prompt = build_rag_prompt(question=question, sources=sources, history=history or [])
        try:
            response = self.client.models.generate_content(
                model=self.settings.llm_model,
                contents=prompt,
            )
        except Exception as exc:
            raise LlmError(f"Gemini generation failed: {exc}") from exc

        answer_text = (getattr(response, "text", "") or "").strip()
        if not answer_text:
            return "I cannot answer from the available document context."

        return answer_text


def build_rag_prompt(question: str, sources: list[SourceChunk], history: list[dict[str, str]]) -> str:
    history_text = _format_history(history)
    context_text = "\n\n".join(_format_source_for_prompt(source, index) for index, source in enumerate(sources, start=1))

    return f"""You are a document question-answering assistant.
Answer only from the provided document excerpts. If the excerpts do not contain enough information, say you do not know.
When you use a source, cite it inline with [filename page N].
Keep the answer concise and practical.

Recent conversation:
{history_text}

Document excerpts:
{context_text or "No relevant excerpts were found."}

Question: {question}
Answer:"""


def build_chat_response(answer: str, sources: list[SourceChunk]) -> ChatResponse:
    return ChatResponse(answer=answer, sources=sources)


def _format_source_for_prompt(source: SourceChunk, index: int) -> str:
    return (
        f"Excerpt {index}: [{source.filename} page {source.page}, chunk {source.chunk_index}]\n"
        f"{source.text}"
    )


def _format_history(history: list[dict[str, str]]) -> str:
    if not history:
        return "None."

    normalized = []
    for item in history[-5:]:
        role = item.get("role", "user")
        content = item.get("content", "").strip()
        if content:
            normalized.append(f"{role}: {content}")

    return "\n".join(normalized) if normalized else "None."

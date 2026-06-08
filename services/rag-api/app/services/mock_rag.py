from app.models.schemas import ChatResponse, SourceChunk, UploadResponse

DEMO_POLICY_FILENAME = "demo-company-policy.pdf"


def answer_question(question: str, filename: str | None = None, history: list[dict[str, str]] | None = None) -> ChatResponse:
    requested_file = filename or DEMO_POLICY_FILENAME
    source = SourceChunk(
        text=(
            "Mock policy excerpt: demo customers can request a return within 30 days, "
            "and priority support questions should be routed to the operations team."
        ),
        filename=requested_file,
        page=1,
        chunk_index=0,
        score=1.0,
    )
    answer = (
        "Mock RAG answer: based on demo-company-policy.pdf, customers can request a return "
        "within 30 days. This deterministic response is used for the mock-first demo; "
        "configure GEMINI_API_KEY for real document retrieval and generation."
    )
    return ChatResponse(answer=answer, sources=[source])


def upload_document(filename: str) -> UploadResponse:
    return UploadResponse(
        filename=filename or DEMO_POLICY_FILENAME,
        pages=1,
        chunks=1,
        message="Mock RAG upload accepted; no embedding or vector storage was performed.",
    )

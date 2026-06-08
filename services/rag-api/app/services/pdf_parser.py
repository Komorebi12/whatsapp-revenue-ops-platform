from collections import defaultdict
from pathlib import Path

import pymupdf
from langchain_text_splitters import RecursiveCharacterTextSplitter

from app.config import Settings
from app.models.schemas import DocumentChunk


class PdfParsingError(ValueError):
    pass


def extract_pages_from_pdf(file_bytes: bytes) -> list[tuple[int, str]]:
    if not file_bytes:
        raise PdfParsingError("The uploaded PDF is empty.")

    try:
        with pymupdf.open(stream=file_bytes, filetype="pdf") as document:
            pages = [(page.number + 1, page.get_text("text").strip()) for page in document]
    except Exception as exc:
        raise PdfParsingError("Unable to read this PDF. Please upload a text-based PDF.") from exc

    non_empty_pages = [(page_number, text) for page_number, text in pages if text]
    if not non_empty_pages:
        raise PdfParsingError(
            "No extractable text was found. Scanned PDFs need OCR, which is outside this demo scope."
        )

    return non_empty_pages


def extract_pages_from_pdf_path(path: str | Path) -> list[tuple[int, str]]:
    file_bytes = Path(path).read_bytes()
    return extract_pages_from_pdf(file_bytes)


def split_pages_into_chunks(
    pages: list[tuple[int, str]],
    filename: str,
    settings: Settings,
) -> list[DocumentChunk]:
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=settings.chunk_size,
        chunk_overlap=settings.chunk_overlap,
    )

    chunks: list[DocumentChunk] = []
    page_counters: dict[int, int] = defaultdict(int)

    for page_number, text in pages:
        for chunk_text in splitter.split_text(text):
            normalized = " ".join(chunk_text.split())
            if not normalized:
                continue

            chunks.append(
                DocumentChunk(
                    text=normalized,
                    filename=filename,
                    page=page_number,
                    chunk_index=len(chunks),
                )
            )
            page_counters[page_number] += 1

    if not chunks:
        raise PdfParsingError("The PDF text was extracted, but no usable chunks were produced.")

    return chunks


def parse_pdf_to_chunks(file_bytes: bytes, filename: str, settings: Settings) -> tuple[int, list[DocumentChunk]]:
    pages = extract_pages_from_pdf(file_bytes)
    chunks = split_pages_into_chunks(pages, filename, settings)
    return len(pages), chunks


def parse_uploaded_file(uploaded_file, settings: Settings) -> tuple[int, list[DocumentChunk]]:
    suffix = Path(uploaded_file.filename or "").suffix.lower()
    if suffix != ".pdf":
        raise PdfParsingError("Only single-column text PDFs are supported in this demo.")

    return parse_pdf_to_chunks(uploaded_file.file.read(), uploaded_file.filename, settings)

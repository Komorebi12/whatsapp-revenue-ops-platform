#!/usr/bin/env bash
set -euo pipefail

rag_api_base_url="${RAG_API_BASE_URL:-http://localhost:8000}"
seed_dir="${1:-$(cd "$(dirname "$0")/.." && pwd)/deploy/rag-seed}"

shopt -s nullglob
pdfs=("$seed_dir"/*.pdf)
if [[ "${#pdfs[@]}" -eq 0 ]]; then
  echo "No PDF seed files found in $seed_dir" >&2
  exit 1
fi

for pdf in "${pdfs[@]}"; do
  echo "Uploading RAG seed: $(basename "$pdf")"
  curl -fsS -X POST "$rag_api_base_url/documents/upload" -F "file=@${pdf}"
  echo
  sleep 3
done

echo "RAG seed complete"
curl -fsS "$rag_api_base_url/collection"
echo

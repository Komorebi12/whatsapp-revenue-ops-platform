param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Assert-FileContains {
  param(
    [string]$Path,
    [string]$Pattern,
    [string]$Description
  )

  $fullPath = Join-Path $projectRoot $Path
  if (-not (Test-Path $fullPath)) {
    throw "Missing file for ${Description}: $Path"
  }

  $content = Get-Content -Raw -Path $fullPath
  if ($content -notmatch $Pattern) {
    throw "Missing expected content for ${Description}: $Pattern in $Path"
  }
}

Assert-FileContains 'deploy/docker/rag-api.Dockerfile' 'FROM python:3\.11-slim' 'rag-api slim base image'
Assert-FileContains 'deploy/docker-compose.yml' 'qdrant/qdrant:v1\.18\.0' 'qdrant pinned image'
Assert-FileContains 'deploy/docker-compose.yml' 'QDRANT_URL: http://qdrant:6333' 'rag-api qdrant URL'
Assert-FileContains 'deploy/docker-compose.yml' 'GEMINI_API_KEY: \$\{GEMINI_API_KEY:-\}' 'rag-api key env placeholder'
Assert-FileContains 'deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json' 'Route Intent' 'n8n route intent node'
Assert-FileContains 'deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json' 'RAG Knowledge API' 'n8n rag branch'
Assert-FileContains 'deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json' '"timeout"\s*:\s*(30000|45000)' 'rag HTTP timeout'
Assert-FileContains 'scripts/seed-rag-knowledge.ps1' 'Start-Sleep' 'seed rate limit'
Assert-FileContains 'scripts/simulate-rag-query.ps1' 'Start-Sleep' 'demo rate limit'
Assert-FileContains 'README.md' 'RAG Path: Mock By Default' 'public RAG quickstart docs'
Assert-FileContains 'docs/case-study.md' 'RAG path' 'public RAG case study'

Write-Host 'phase2 static checks ok'

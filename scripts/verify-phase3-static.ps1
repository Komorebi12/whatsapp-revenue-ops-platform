$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Assert-FileContains {
  param(
    [string]$Path,
    [string]$Pattern,
    [string]$Description
  )
  $content = Get-Content -Raw -Path $Path
  if ($content -notmatch $Pattern) {
    throw "Missing $Description in $Path"
  }
}

function Assert-FileNotContains {
  param(
    [string]$Path,
    [string]$Pattern,
    [string]$Description
  )
  $content = Get-Content -Raw -Path $Path
  if ($content -match $Pattern) {
    throw "Unexpected $Description in $Path"
  }
}

Assert-FileContains 'deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json' 'Format RAG Response' 'RAG fallback formatter'
Assert-FileContains 'deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json' 'Format Sales Response' 'sales fallback formatter'
Assert-FileContains 'deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json' '\$env\.AGENT_AUTH_SECRET' 'agent env secret expression'
Assert-FileNotContains 'deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json' 'mock-agent-secret' 'hardcoded agent secret'

Assert-FileContains 'deploy/n8n/workflows/wf_console_staff_reply.json' 'Console Reply Authorized' 'console env auth node'
Assert-FileContains 'deploy/n8n/workflows/wf_console_staff_reply.json' '\$env\.MVP_REPLY_WEBHOOK_SECRET' 'console env secret expression'
Assert-FileContains 'deploy/n8n/workflows/wf_console_staff_reply.json' 'queryReplacement' 'Postgres query parameters'
Assert-FileNotContains 'deploy/n8n/workflows/wf_console_staff_reply.json' 'mock-console-secret' 'hardcoded console secret'
Assert-FileNotContains 'deploy/n8n/workflows/wf_console_staff_reply.json' 'sqlString' 'SQL string escaping helper'

Assert-FileContains 'deploy/docker/rag-api.Dockerfile' 'rag-api-requirements\.txt' 'pinned RAG requirements install'
Assert-FileContains 'deploy/docker/rag-api-requirements.txt' 'fastapi==' 'pinned fastapi'
Assert-FileContains 'deploy/.env.example' 'AGENT_AUTH_SECRET=' 'env variable inventory'
Assert-FileContains 'deploy/.env.mock' 'MOCK_MODE=true' 'mock-first env file'
Assert-FileContains 'deploy/.env.real.example' 'MOCK_MODE=false' 'real integration env template'
Assert-FileContains 'scripts/health-check.ps1' "Level 'ready'" 'diagnostic health levels'
Assert-FileContains 'scripts/demo-reset.ps1' 'Type RESET to proceed' 'interactive reset confirmation'

Write-Host 'phase3 static checks ok'

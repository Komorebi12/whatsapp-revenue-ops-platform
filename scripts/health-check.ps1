param(
  [switch]$IncludeOperatorConsole,
  [switch]$RequireRagReady,
  [string]$ProjectName = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $projectRoot 'deploy')

function Write-Check {
  param(
    [string]$Name,
    [string]$Level,
    [string]$Status,
    [string]$Detail = ''
  )

  $suffix = if ($Detail) { " - $Detail" } else { '' }
  Write-Host "$Name [$Level]: $Status$suffix"
}

function Test-Http {
  param(
    [string]$Name,
    [string]$Uri,
    [string]$Level = 'alive'
  )

  try {
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 5
    Write-Check -Name $Name -Level $Level -Status 'ok' -Detail "http $($response.StatusCode)"
  }
  catch {
    Write-Check -Name $Name -Level $Level -Status 'failed' -Detail $_.Exception.Message
    throw
  }
}

function Invoke-Compose {
  param(
    [string[]]$CommandArgs
  )

  $composeArgs = @('compose')
  if ($ProjectName) {
    $composeArgs += @('-p', $ProjectName)
  }
  $composeArgs += $CommandArgs

  & docker @composeArgs
}

Test-Http -Name 'ghl-mock' -Uri 'http://localhost:8090/health'
Test-Http -Name 'sales-agent' -Uri 'http://localhost:8020/health'
Test-Http -Name 'ghl-sync' -Uri 'http://localhost:8010/health'
Test-Http -Name 'qdrant' -Uri 'http://localhost:6333/'
Test-Http -Name 'rag-api' -Uri 'http://localhost:8000/health'
Test-Http -Name 'n8n' -Uri 'http://localhost:5678/healthz'

if ($IncludeOperatorConsole) {
  Test-Http -Name 'operator-console' -Uri 'http://localhost:3000/sign-in'
}

Invoke-Compose @('exec', '-T', 'postgres', 'pg_isready', '-U', 'postgres', '-d', 'revenue_ops') | Out-Null
Write-Check -Name 'postgres revenue_ops' -Level 'alive' -Status 'ok'

Invoke-Compose @('exec', '-T', 'postgres', 'pg_isready', '-U', 'postgres', '-d', 'n8n_metadata') | Out-Null
Write-Check -Name 'postgres n8n_metadata' -Level 'alive' -Status 'ok'

$n8nTablesInRevenueOps = Invoke-Compose @('exec', '-T', 'postgres', 'psql', '-U', 'postgres', '-d', 'revenue_ops', '-tAc', "select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('workflow_entity', 'execution_entity', 'credentials_entity');")
if ([int]$n8nTablesInRevenueOps.Trim() -ne 0) {
  throw "n8n metadata tables found in revenue_ops"
}
Write-Check -Name 'postgres revenue_ops isolation' -Level 'ready' -Status 'ok'

$workflowCount = Invoke-Compose @('exec', '-T', 'postgres', 'psql', '-U', 'postgres', '-d', 'n8n_metadata', '-tAc', "select count(*) from workflow_entity where name in ('wf_phase1a_whatsapp_inbound', 'wf_console_staff_reply');")
if ([int]$workflowCount.Trim() -lt 2) {
  throw "expected workflows were not imported into n8n_metadata"
}
Write-Check -Name 'n8n workflows' -Level 'configured' -Status 'ok' -Detail "count=$($workflowCount.Trim())"

$ragHealth = Invoke-RestMethod -Method Get -Uri 'http://localhost:8000/health'
if (-not $ragHealth.qdrant_configured) {
  throw 'rag-api Qdrant dependency is not configured'
}
Write-Check -Name 'rag-api dependencies' -Level 'configured' -Status 'ok' -Detail "collection=$($ragHealth.collection) gemini=$($ragHealth.gemini_configured)"

if ($RequireRagReady) {
  if (-not $ragHealth.gemini_configured) {
    throw 'rag-api Gemini dependency is not configured'
  }

  $ragCollection = Invoke-RestMethod -Method Get -Uri 'http://localhost:8000/collection'
  if ([int]$ragCollection.vectors -le 0) {
    throw "rag collection has no vectors"
  }
  Write-Check -Name 'rag collection' -Level 'ready' -Status 'ok' -Detail "$($ragCollection.collection) vectors=$($ragCollection.vectors)"
}
else {
  Write-Check -Name 'rag collection' -Level 'ready' -Status 'skipped' -Detail 'use -RequireRagReady after seeding real RAG'
}

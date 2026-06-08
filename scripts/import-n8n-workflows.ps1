param(
  [switch]$NoActivate,
  [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $projectRoot 'deploy')

$credentialDir = Join-Path $projectRoot 'deploy\n8n\credentials'
if (Test-Path $credentialDir) {
  docker compose exec -T n8n n8n import:credentials --separate --input=/credentials
  if ($LASTEXITCODE -ne 0) {
    throw 'n8n credential import failed'
  }
}

docker compose exec -T n8n n8n import:workflow --separate --input=/workflows
if ($LASTEXITCODE -ne 0) {
  throw 'n8n workflow import failed'
}

if (-not $NoActivate) {
  $workflowDir = Join-Path $projectRoot 'deploy\n8n\workflows'
  Get-ChildItem -Path $workflowDir -Filter '*.json' | ForEach-Object {
    $workflow = Get-Content -Raw -Path $_.FullName | ConvertFrom-Json
    $workflowId = $workflow.id
    docker compose exec -T n8n n8n publish:workflow --id=$workflowId
    if ($LASTEXITCODE -ne 0) {
      throw "n8n workflow publish failed: $workflowId"
    }
  }
}

if (-not $NoRestart) {
  docker compose restart n8n
  if ($LASTEXITCODE -ne 0) {
    throw 'n8n restart failed'
  }
}

Write-Host 'n8n workflows imported'

param(
  [switch]$Force,
  [switch]$SkipBuild,
  [switch]$SkipRagSeed
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$deployDir = Join-Path $projectRoot 'deploy'

if (-not $Force) {
  Write-Host 'This will run docker compose down -v and remove local demo volumes.'
  $answer = Read-Host 'Continue? Type RESET to proceed'
  if ($answer -ne 'RESET') {
    Write-Host 'Demo reset cancelled.'
    exit 0
  }
}

Set-Location $deployDir
docker compose down -v
if ($LASTEXITCODE -ne 0) {
  throw 'docker compose down -v failed'
}

$upArgs = @('compose', 'up', '-d')
if (-not $SkipBuild) {
  $upArgs += '--build'
}
docker @upArgs
if ($LASTEXITCODE -ne 0) {
  throw 'docker compose up failed'
}

foreach ($target in @(
  @{ Name = 'rag-api'; Uri = 'http://localhost:8000/health' },
  @{ Name = 'n8n'; Uri = 'http://localhost:5678/healthz' }
)) {
  $ready = $false
  for ($attempt = 1; $attempt -le 40; $attempt++) {
    try {
      Invoke-WebRequest -Uri $target.Uri -UseBasicParsing -TimeoutSec 5 | Out-Null
      Write-Host "$($target.Name) ready"
      $ready = $true
      break
    }
    catch {
      Start-Sleep -Seconds 3
    }
  }
  if (-not $ready) {
    throw "$($target.Name) was not ready after waiting"
  }
}

if (-not $SkipRagSeed) {
  & (Join-Path $projectRoot 'scripts\seed-rag-knowledge.ps1')
}

& (Join-Path $projectRoot 'scripts\health-check.ps1')

$ragResponse = & (Join-Path $projectRoot 'scripts\simulate-rag-query.ps1') -Message 'What is your return policy?'
Write-Host 'RAG query smoke test: ok'

$salesMessageId = [guid]::NewGuid().ToString()
$salesResponse = & (Join-Path $projectRoot 'scripts\simulate-message.ps1') -Message 'I want pricing for your CRM automation product' -MessageId $salesMessageId
Write-Host 'Sales query smoke test: ok'

Write-Host 'Demo reset complete.'

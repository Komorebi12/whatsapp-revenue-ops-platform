param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [switch]$SkipK6Archive
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path

function Join-Root {
  param([string]$Path)
  return (Join-Path $resolvedRoot $Path)
}

function Assert-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath (Join-Root $Path) -PathType Leaf)) {
    throw "Missing required load-test asset: $Path"
  }
}

function Assert-Content {
  param(
    [string]$Path,
    [string]$Needle,
    [string]$Description
  )

  $content = Get-Content -Raw -LiteralPath (Join-Root $Path)
  if (-not $content.Contains($Needle)) {
    throw "$Path does not contain $Description ('$Needle')."
  }
}

$requiredFiles = @(
  'load/k6/lib/options.js',
  'load/k6/rag-chat.js',
  'load/k6/sales-agent.js',
  'load/k6/n8n-inbound.js',
  'load/results/.gitkeep',
  'scripts/run-load-tests.ps1',
  'scripts/run-load-tests.sh',
  'scripts/smoke-load-k8s.ps1',
  'scripts/smoke-load-k8s.sh',
  'docs/load-test-findings.md'
)

foreach ($file in $requiredFiles) {
  Assert-File $file
}

Assert-Content '.gitignore' 'load/results/*' 'raw load-result ignore rule'
Assert-Content '.gitignore' '!load/results/.gitkeep' 'load results keepfile exception'
Assert-Content '.gitignore' '*.tar' 'k6 archive ignore rule'
Assert-Content '.github/workflows/ci.yml' 'k6 archive' 'k6 archive static gate'
Assert-Content 'docs/public-release-manifest.md' 'docs/load-test-findings.md' 'load findings include'
Assert-Content 'docs/public-release-manifest.md' 'load/k6/**' 'load k6 include'
Assert-Content 'scripts/verify-standalone-release.ps1' 'docs/load-test-findings.md' 'standalone scan coverage for load findings'

foreach ($script in @('load/k6/rag-chat.js', 'load/k6/sales-agent.js', 'load/k6/n8n-inbound.js')) {
  Assert-Content $script 'handleSummary' "k6 handleSummary export in $script"
  Assert-Content $script 'check(' "k6 response checks in $script"
}

Assert-Content 'scripts/run-load-tests.ps1' 'execution_entity' 'n8n execution_entity evidence'
Assert-Content 'scripts/run-load-tests.ps1' 'redis-cli' 'Redis key discovery'
Assert-Content 'scripts/run-load-tests.ps1' '--scan' 'dynamic Redis SCAN discovery'
Assert-Content 'scripts/run-load-tests.ps1' 'Warm-up' 'warm-up run'
Assert-Content 'scripts/run-load-tests.ps1' 'Median' 'median reporting'
Assert-Content 'scripts/run-load-tests.ps1' 'console/reply' 'console reply queue smoke'
Assert-Content 'scripts/smoke-queue-mode.ps1' 'execution_entity' 'queue smoke n8n execution evidence'
Assert-Content 'scripts/smoke-queue-mode.ps1' 'console/reply' 'queue smoke console reply path'
Assert-Content 'scripts/smoke-load-k8s.ps1' 'restartCount' 'K8s restart-count gate'

if (-not $SkipK6Archive) {
  $k6 = Get-Command k6 -ErrorAction SilentlyContinue
  if ($null -eq $k6) {
    throw 'k6 was not found on PATH. Install k6 or rerun with -SkipK6Archive for offline structure checks.'
  }

  $archiveDir = Join-Path ([System.IO.Path]::GetTempPath()) ('revenueops-k6-archive-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
  try {
    foreach ($script in @('rag-chat', 'sales-agent', 'n8n-inbound')) {
      $archivePath = Join-Path $archiveDir "$script.tar"
      & k6 archive (Join-Root "load/k6/$script.js") -O $archivePath
      if ($LASTEXITCODE -ne 0) {
        throw "k6 archive failed for load/k6/$script.js"
      }
    }
  }
  finally {
    Remove-Item -LiteralPath $archiveDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host 'Load-test assets: ok'

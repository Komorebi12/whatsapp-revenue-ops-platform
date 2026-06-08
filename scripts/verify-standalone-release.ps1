param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$requiredPaths = @(
  'services/sales-agent/app',
  'services/sales-agent/requirements.txt',
  'services/ghl-sync/app',
  'services/ghl-sync/requirements.txt',
  'services/rag-api/app',
  'services/rag-api/requirements.txt',
  'apps/operator-console/package.json',
  'apps/operator-console/pnpm-lock.yaml'
)

$missing = @()
foreach ($relativePath in $requiredPaths) {
  if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot $relativePath))) {
    $missing += $relativePath
  }
}

if ($missing.Count -gt 0) {
  throw "Standalone release is missing required paths: $($missing -join ', ')"
}

$forbiddenPatterns = @(
  'whatsapp-ai-sales-agent',
  'whatsapp-ghl-sync',
  'rag-knowledge-base',
  'whatsapp-support-mvp',
  'whatsapp-support-operator-console',
  'context: ../..'
)

$scanFiles = @(
  'README.md',
  'deploy/docker-compose.yml',
  'deploy/docker/sales-agent.Dockerfile',
  'deploy/docker/ghl-sync.Dockerfile',
  'deploy/docker/rag-api.Dockerfile',
  'deploy/docker/operator-console.Dockerfile',
  'deploy/init-db/00_schema.sql',
  'docs/architecture.md',
  'docs/case-study.md',
  'docs/data-model.md',
  'docs/public-release-manifest.md',
  'docs/portfolio/claims-ledger.md',
  'docs/portfolio/upwork-listing.md',
  'mock/ghl-mock-server/README.md'
)

$violations = @()
foreach ($relativeFile in $scanFiles) {
  $path = Join-Path $resolvedRoot $relativeFile
  if (-not (Test-Path -LiteralPath $path)) {
    $violations += "$relativeFile missing"
    continue
  }
  $content = Get-Content -LiteralPath $path -Raw
  foreach ($pattern in $forbiddenPatterns) {
    if ($content.Contains($pattern)) {
      $violations += "$relativeFile contains '$pattern'"
    }
  }
}

if ($violations.Count -gt 0) {
  throw "Standalone release still depends on monorepo paths: $($violations -join '; ')"
}

Write-Host "Standalone release structure: ok"

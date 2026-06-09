param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path

function Get-RelativePath {
  param(
    [string]$BasePath,
    [string]$Path
  )

  $baseUri = New-Object System.Uri(($BasePath.TrimEnd('\') + '\'))
  $pathUri = New-Object System.Uri($Path)
  return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}
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
  'docs/proposal-packet/proof-points.md',
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

$publicDenylist = @(
  ([string]([char]0x591a) + [string]([char]0x0041) + [string]([char]0x0049) + [string]([char]0x534f) + [string]([char]0x4f5c)),
  ('Phase 2 ' + 'MVP'),
  ('Phase ' + '3'),
  ('phase' + '1b')
)

$textExtensions = @(
  '.css',
  '.js',
  '.json',
  '.md',
  '.mjs',
  '.ps1',
  '.sh',
  '.sql',
  '.svg',
  '.ts',
  '.tsx',
  '.txt',
  '.yml'
)

$denylistViolations = @()
Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File |
  Where-Object {
    $relative = (Get-RelativePath -BasePath $resolvedRoot -Path $_.FullName).Replace('\', '/')
    $textExtensions -contains $_.Extension.ToLowerInvariant() -and
      -not $relative.StartsWith('ai/') -and
      -not $relative.StartsWith('work/') -and
      -not $relative.StartsWith('docs/assets/') -and
      -not $relative.StartsWith('docs/phase-plan.md') -and
      -not $relative.StartsWith('docs/codex-boundaries.md') -and
      -not $relative.StartsWith('docs/gemini-checklist.md') -and
      -not $relative.StartsWith('docs/demo-script.md') -and
      -not $relative.StartsWith('docs/portfolio/recording-guide.md')
  } |
  ForEach-Object {
    $relative = (Get-RelativePath -BasePath $resolvedRoot -Path $_.FullName).Replace('\', '/')
    $content = Get-Content -LiteralPath $_.FullName -Raw
    foreach ($pattern in $publicDenylist) {
      if ($content.Contains($pattern)) {
        $denylistViolations += "$relative contains '$pattern'"
      }
    }
  }

if ($denylistViolations.Count -gt 0) {
  throw "Public release naming/provenance denylist failed: $($denylistViolations -join '; ')"
}

Write-Host "Standalone release structure: ok"

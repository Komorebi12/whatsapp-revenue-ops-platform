param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [switch]$SkipClientDryRun
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$k8sBase = Join-Path $resolvedRoot 'deploy/k8s/base'

function Get-RelativePath {
  param(
    [string]$BasePath,
    [string]$Path
  )

  $baseUri = New-Object System.Uri(($BasePath.TrimEnd('\') + '\'))
  $pathUri = New-Object System.Uri($Path)
  return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Assert-Path {
  param([string]$RelativePath)

  $path = Join-Path $resolvedRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required K8s path: $RelativePath"
  }
}

function Assert-Contains {
  param(
    [string]$RelativePath,
    [string]$Pattern,
    [string]$Description
  )

  $path = Join-Path $resolvedRoot $RelativePath
  $content = Get-Content -LiteralPath $path -Raw
  if ($content -notmatch $Pattern) {
    throw "$RelativePath did not contain expected $Description"
  }
}

function Assert-NotContains {
  param(
    [string]$RelativePath,
    [string]$Pattern,
    [string]$Description
  )

  $path = Join-Path $resolvedRoot $RelativePath
  $content = Get-Content -LiteralPath $path -Raw
  if ($content -match $Pattern) {
    throw "$RelativePath unexpectedly contained $Description"
  }
}

function Assert-SameHash {
  param(
    [string]$SourceRelativePath,
    [string]$MirrorRelativePath
  )

  $sourcePath = Join-Path $resolvedRoot $SourceRelativePath
  $mirrorPath = Join-Path $resolvedRoot $MirrorRelativePath
  Assert-Path $SourceRelativePath
  Assert-Path $MirrorRelativePath

  $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
  $mirrorHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $mirrorPath).Hash
  if ($sourceHash -ne $mirrorHash) {
    throw "K8s asset mirror drifted: $MirrorRelativePath no longer matches $SourceRelativePath"
  }
}

$requiredPaths = @(
  'deploy/k8s/base/kustomization.yaml',
  'deploy/k8s/base/namespace.yaml',
  'deploy/k8s/base/configmap-app.yaml',
  'deploy/k8s/base/secret.mock.yaml',
  'deploy/k8s/base/secret.example.yaml',
  'deploy/k8s/base/postgres.yaml',
  'deploy/k8s/base/redis.yaml',
  'deploy/k8s/base/qdrant.yaml',
  'deploy/k8s/base/n8n-main.yaml',
  'deploy/k8s/base/n8n-webhook.yaml',
  'deploy/k8s/base/n8n-worker.yaml',
  'deploy/k8s/base/sales-agent.yaml',
  'deploy/k8s/base/ghl-sync.yaml',
  'deploy/k8s/base/ghl-mock.yaml',
  'deploy/k8s/base/rag-api.yaml',
  'deploy/k8s/base/ingress.yaml',
  'deploy/k8s/overlays/console/kustomization.yaml',
  'deploy/k8s/overlays/console/operator-console.yaml',
  'deploy/k8s/kind/kind-config.yaml',
  'docs/deploy-k8s.md'
)

foreach ($relativePath in $requiredPaths) {
  Assert-Path $relativePath
}

$assetPairs = @(
  @('deploy/init-db/00_schema.sql', 'deploy/k8s/base/assets/init-db/00_schema.sql'),
  @('deploy/init-db/01_seed.sql', 'deploy/k8s/base/assets/init-db/01_seed.sql'),
  @('deploy/init-db/02_n8n_metadata.sql', 'deploy/k8s/base/assets/init-db/02_n8n_metadata.sql'),
  @('deploy/n8n/bootstrap-entrypoint.sh', 'deploy/k8s/base/assets/n8n/bootstrap-entrypoint.sh'),
  @('deploy/n8n/workflows/wf_phase1a_whatsapp_inbound.json', 'deploy/k8s/base/assets/n8n/workflows/wf_phase1a_whatsapp_inbound.json'),
  @('deploy/n8n/workflows/wf_console_staff_reply.json', 'deploy/k8s/base/assets/n8n/workflows/wf_console_staff_reply.json'),
  @('deploy/n8n/credentials/phase1c_revenue_ops_postgres.json', 'deploy/k8s/base/assets/n8n/credentials/phase1c_revenue_ops_postgres.json')
)

foreach ($pair in $assetPairs) {
  Assert-SameHash -SourceRelativePath $pair[0] -MirrorRelativePath $pair[1]
}

$initDbSize = (
  Get-ChildItem -LiteralPath (Join-Path $resolvedRoot 'deploy/k8s/base/assets/init-db') -File |
    Measure-Object -Property Length -Sum
).Sum
if ($initDbSize -ge 1MB) {
  throw "K8s init-db ConfigMap assets are $initDbSize bytes, at or above the 1 MiB ConfigMap safety limit."
}

Assert-Contains 'deploy/k8s/base/n8n-webhook.yaml' 'args:\s*\r?\n\s*-\s*webhook' 'args: ["webhook"]'
Assert-Contains 'deploy/k8s/base/n8n-worker.yaml' 'args:\s*\r?\n\s*-\s*worker' 'args: ["worker"]'
Assert-NotContains 'deploy/k8s/base/n8n-webhook.yaml' '^\s*command:' 'K8s command override'
Assert-NotContains 'deploy/k8s/base/n8n-worker.yaml' '^\s*command:' 'K8s command override'
Assert-Contains 'deploy/k8s/base/kustomization.yaml' 'secretGenerator:\s*\r?\n\s*-\s*name:\s*n8n-credentials' 'n8n credential secretGenerator'
Assert-Contains 'deploy/k8s/base/assets/n8n/credentials/phase1c_revenue_ops_postgres.json' '"id": "phase1c_revenue_ops_postgres"' 'mock n8n Postgres credential id'

foreach ($relativePath in @(
  'deploy/k8s/base/postgres.yaml',
  'deploy/k8s/base/qdrant.yaml',
  'deploy/k8s/base/n8n-main.yaml',
  'deploy/k8s/base/n8n-webhook.yaml'
)) {
  Assert-Contains $relativePath 'strategy:\s*\r?\n\s*type:\s*Recreate' 'strategy: type: Recreate'
}
Assert-NotContains 'deploy/k8s/base/n8n-worker.yaml' 'strategy:\s*\r?\n\s*type:\s*Recreate' 'worker Recreate rollout strategy'

Assert-Contains 'deploy/k8s/base/redis.yaml' 'image:\s*redis:7\.2-alpine' 'Redis 7.2 image pin'
Assert-NotContains 'deploy/k8s/base/kustomization.yaml' 'secret\.example\.yaml' 'secret.example.yaml in the applied base'

$renderedPath = Join-Path ([System.IO.Path]::GetTempPath()) ('revenueops-k8s-{0}.yaml' -f ([guid]::NewGuid().ToString('N')))
try {
  $rendered = & kubectl kustomize $k8sBase
  if ($LASTEXITCODE -ne 0) {
    throw "kubectl kustomize deploy/k8s/base failed with exit code $LASTEXITCODE"
  }

  $rendered | Set-Content -LiteralPath $renderedPath -Encoding UTF8
  $renderedText = $rendered -join "`n"

  foreach ($name in @(
    'postgres',
    'redis',
    'qdrant',
    'n8n',
    'n8n-webhook',
    'n8n-worker',
    'sales-agent',
    'ghl-sync',
    'ghl-mock',
    'rag-api'
  )) {
    if ($renderedText -notmatch "(?m)^\s*name:\s*$([regex]::Escape($name))\s*$") {
      throw "Rendered K8s base did not include resource name '$name'."
    }
  }

  if (-not $SkipClientDryRun) {
    $canReachCluster = $false
    try {
      & kubectl version --request-timeout=5s | Out-Null
      if ($LASTEXITCODE -eq 0) {
        $canReachCluster = $true
      }
    }
    catch {
      $canReachCluster = $false
    }

    if ($canReachCluster) {
      & kubectl apply --dry-run=client --validate=false -f $renderedPath | Out-Null
      if ($LASTEXITCODE -ne 0) {
        throw "kubectl apply --dry-run=client failed with exit code $LASTEXITCODE"
      }
    }
    else {
      Write-Host "Skipping kubectl client dry-run because no Kubernetes API server is reachable."
    }
  }
}
finally {
  if (Test-Path -LiteralPath $renderedPath) {
    Remove-Item -LiteralPath $renderedPath -Force
  }
}

Write-Host "K8s manifest static checks: ok"

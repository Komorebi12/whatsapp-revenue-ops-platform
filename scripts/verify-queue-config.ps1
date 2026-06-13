param(
  [string]$ProjectName = 'revenueops-queue-config',
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$composeFile = Join-Path $resolvedRoot 'deploy/docker-compose.yml'
$queueComposeFile = Join-Path $resolvedRoot 'deploy/docker-compose.queue.yml'
$envFile = Join-Path $resolvedRoot 'deploy/.env.mock'

function Invoke-ComposeConfigJson {
  $composeArgs = @(
    'compose',
    '-p', $ProjectName,
    '--env-file', $envFile,
    '-f', $composeFile,
    '-f', $queueComposeFile,
    'config',
    '--format', 'json'
  )

  $output = & docker @composeArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker $($composeArgs -join ' ') failed with exit code $LASTEXITCODE"
  }

  return ($output -join "`n") | ConvertFrom-Json
}

function Get-Service {
  param(
    [object]$Config,
    [string]$Name
  )

  if (-not ($Config.services.PSObject.Properties.Name -contains $Name)) {
    throw "Rendered Compose config is missing service '$Name'."
  }

  return $Config.services.$Name
}

function Get-EnvironmentMap {
  param(
    [object]$Service,
    [string]$ServiceName
  )

  if (-not $Service.environment) {
    throw "Service '$ServiceName' has no rendered environment block."
  }

  return $Service.environment
}

function Get-EnvValue {
  param(
    [object]$Environment,
    [string]$Key,
    [string]$ServiceName
  )

  if (-not ($Environment.PSObject.Properties.Name -contains $Key)) {
    throw "Service '$ServiceName' is missing environment variable '$Key'."
  }

  return [string]$Environment.$Key
}

function Assert-EqualEnv {
  param(
    [object]$MainEnv,
    [object]$WebhookEnv,
    [object]$WorkerEnv,
    [string[]]$Keys
  )

  foreach ($key in $Keys) {
    $mainValue = Get-EnvValue -Environment $MainEnv -Key $key -ServiceName 'n8n'
    $webhookValue = Get-EnvValue -Environment $WebhookEnv -Key $key -ServiceName 'n8n-webhook'
    $workerValue = Get-EnvValue -Environment $WorkerEnv -Key $key -ServiceName 'n8n-worker'

    if ($mainValue -ne $webhookValue -or $mainValue -ne $workerValue) {
      throw "Queue env drift for '$key': n8n='$mainValue', n8n-webhook='$webhookValue', n8n-worker='$workerValue'."
    }
  }
}

function Assert-EnvValue {
  param(
    [object]$Environment,
    [string]$ServiceName,
    [string]$Key,
    [string]$Expected
  )

  $actual = Get-EnvValue -Environment $Environment -Key $Key -ServiceName $ServiceName
  if ($actual -ne $Expected) {
    throw "Service '$ServiceName' expected '$Key=$Expected' but rendered '$Key=$actual'."
  }
}

function Assert-VolumeTarget {
  param(
    [object]$Service,
    [string]$ServiceName,
    [string]$Source,
    [string]$Target
  )

  $matches = @($Service.volumes | Where-Object {
      $_.source -eq $Source -and $_.target -eq $Target
    })

  if ($matches.Count -lt 1) {
    throw "Service '$ServiceName' is missing volume '${Source}:${Target}'."
  }
}

$config = Invoke-ComposeConfigJson
$n8n = Get-Service -Config $config -Name 'n8n'
$webhook = Get-Service -Config $config -Name 'n8n-webhook'
$worker = Get-Service -Config $config -Name 'n8n-worker'
$redis = Get-Service -Config $config -Name 'redis'

if ([string]$redis.image -ne 'redis:7.2-alpine') {
  throw "Redis image must be redis:7.2-alpine, rendered '$($redis.image)'."
}

if ($worker.PSObject.Properties.Name -contains 'container_name' -and $worker.container_name) {
  throw "n8n-worker must not set container_name, otherwise --scale n8n-worker=N breaks."
}

$mainEnv = Get-EnvironmentMap -Service $n8n -ServiceName 'n8n'
$webhookEnv = Get-EnvironmentMap -Service $webhook -ServiceName 'n8n-webhook'
$workerEnv = Get-EnvironmentMap -Service $worker -ServiceName 'n8n-worker'

$sharedKeys = @(
  'N8N_ENCRYPTION_KEY',
  'DB_TYPE',
  'DB_POSTGRESDB_HOST',
  'DB_POSTGRESDB_PORT',
  'DB_POSTGRESDB_DATABASE',
  'DB_POSTGRESDB_USER',
  'DB_POSTGRESDB_PASSWORD',
  'EXECUTIONS_MODE',
  'QUEUE_BULL_REDIS_HOST',
  'QUEUE_BULL_REDIS_PORT',
  'N8N_DEFAULT_BINARY_DATA_MODE',
  'GENERIC_TIMEZONE',
  'N8N_LOG_LEVEL',
  'BUSINESS_DATABASE_URL',
  'RAG_API_URL',
  'MVP_REPLY_WEBHOOK_SECRET',
  'AGENT_AUTH_SECRET',
  'N8N_BLOCK_ENV_ACCESS_IN_NODE',
  'NODE_FUNCTION_ALLOW_EXTERNAL'
)

Assert-EqualEnv -MainEnv $mainEnv -WebhookEnv $webhookEnv -WorkerEnv $workerEnv -Keys $sharedKeys

foreach ($service in @('n8n', 'n8n-webhook', 'n8n-worker')) {
  $env = switch ($service) {
    'n8n' { $mainEnv }
    'n8n-webhook' { $webhookEnv }
    'n8n-worker' { $workerEnv }
  }
  Assert-EnvValue -Environment $env -ServiceName $service -Key 'EXECUTIONS_MODE' -Expected 'queue'
  Assert-EnvValue -Environment $env -ServiceName $service -Key 'QUEUE_BULL_REDIS_HOST' -Expected 'redis'
  Assert-EnvValue -Environment $env -ServiceName $service -Key 'QUEUE_BULL_REDIS_PORT' -Expected '6379'
  Assert-EnvValue -Environment $env -ServiceName $service -Key 'N8N_DEFAULT_BINARY_DATA_MODE' -Expected 'filesystem'
}

Assert-EnvValue -Environment $mainEnv -ServiceName 'n8n' -Key 'OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS' -Expected 'true'
Assert-EnvValue -Environment $workerEnv -ServiceName 'n8n-worker' -Key 'QUEUE_HEALTH_CHECK_ACTIVE' -Expected 'true'

if (([string]$webhook.command) -notmatch 'webhook') {
  throw "n8n-webhook command must render as webhook, got '$($webhook.command)'."
}

if (([string]$worker.command) -notmatch 'worker') {
  throw "n8n-worker command must render as worker, got '$($worker.command)'."
}

Assert-VolumeTarget -Service $n8n -ServiceName 'n8n' -Source 'n8n_data' -Target '/home/node/.n8n'
Assert-VolumeTarget -Service $webhook -ServiceName 'n8n-webhook' -Source 'n8n_data' -Target '/home/node/.n8n'
Assert-VolumeTarget -Service $worker -ServiceName 'n8n-worker' -Source 'n8n_data' -Target '/home/node/.n8n'

Write-Host "Queue Compose config: ok"

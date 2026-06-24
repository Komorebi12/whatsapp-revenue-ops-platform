param(
  [string]$ProjectName = 'revenueops-load',
  [int[]]$WorkerScales = @(1, 2, 4),
  [int]$RunsPerScenario = 3,
  [int]$WarmupSeconds = 10,
  [int]$WarmupVus = 1,
  [int]$Vus = 5,
  [string]$Duration = '30s',
  [int]$HealthRetries = 80,
  [int]$HealthSleepSeconds = 5,
  [string]$ComposeOverrideFile = '',
  [switch]$SkipBuild,
  [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot 'deploy/docker-compose.yml'
$queueComposeFile = Join-Path $projectRoot 'deploy/docker-compose.queue.yml'
$envFile = Join-Path $projectRoot 'deploy/.env.mock'
$resultsRoot = Join-Path $projectRoot 'load/results'
$summaryRoot = Join-Path $resultsRoot ('compose-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))

$queueServices = @(
  'postgres',
  'ghl-mock',
  'sales-agent',
  'ghl-sync',
  'qdrant',
  'rag-api',
  'redis',
  'n8n',
  'n8n-webhook',
  'n8n-worker'
)

function Write-Section {
  param([string]$Name)
  Write-Host ''
  Write-Host "==> $Name"
}

function Invoke-Compose {
  param([string[]]$CommandArgs)
  $composeArgs = @(
    'compose',
    '-p', $ProjectName,
    '--env-file', $envFile,
    '-f', $composeFile,
    '-f', $queueComposeFile
  )
  if ($ComposeOverrideFile) {
    $composeArgs += @('-f', $ComposeOverrideFile)
  }
  $composeArgs += $CommandArgs

  & docker @composeArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker $($composeArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Invoke-ComposeOutput {
  param([string[]]$CommandArgs)
  $composeArgs = @(
    'compose',
    '-p', $ProjectName,
    '--env-file', $envFile,
    '-f', $composeFile,
    '-f', $queueComposeFile
  )
  if ($ComposeOverrideFile) {
    $composeArgs += @('-f', $ComposeOverrideFile)
  }
  $composeArgs += $CommandArgs

  $output = & docker @composeArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker $($composeArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
  return $output
}

function Invoke-DockerOutput {
  param([string[]]$CommandArgs)
  $output = & docker @CommandArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker $($CommandArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
  return $output
}

function Invoke-ComposeSqlScalar {
  param([string]$Query)
  $output = Invoke-ComposeOutput @('exec', '-T', 'postgres', 'psql', '-U', 'postgres', '-d', 'n8n_metadata', '-Atc', $Query)
  return (($output -join '').Trim())
}

function Invoke-RevenueSqlScalar {
  param([string]$Query)
  $output = Invoke-ComposeOutput @('exec', '-T', 'postgres', 'psql', '-U', 'postgres', '-d', 'revenue_ops', '-Atc', $Query)
  return (($output -join '').Trim())
}

function Get-N8nExecutionCount {
  return [int](Invoke-ComposeSqlScalar 'select count(*) from execution_entity;')
}

function Ensure-ConsoleReplyTicket {
  param([string]$TicketId)

  $escapedTicketId = $TicketId.Replace("'", "''")
  $customerId = [guid]::NewGuid().ToString()
  $phoneSuffix = (Get-Random -Minimum 1000000 -Maximum 9999999).ToString()
  $phone = "+1555$phoneSuffix"
  $query = @"
with customer as (
  insert into customers (id, phone, display_name, metadata_json)
  values (
    '$customerId',
    '$phone',
    'Demo Buyer',
    jsonb_build_object('source', 'load-smoke')
  )
  returning id
)
insert into tickets (ticket_id, customer_id, intent, status, subject, context_json)
select
  '$escapedTicketId',
  id,
  'information_query',
  'awaiting_staff',
  'Load smoke console reply ticket',
  jsonb_build_object('source', 'load-smoke')
from customer
on conflict (ticket_id) do nothing;
"@
  Invoke-RevenueSqlScalar $query | Out-Null
}

function Get-N8nWorkerContainers {
  $ids = @(Invoke-ComposeOutput @('ps', '-q', 'n8n-worker'))
  return @($ids | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
}

function Get-RedisEvidence {
  $keys = @(Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', '--scan'))
  $queueKeys = @($keys | Where-Object { $_ -match '(?i)(bull|queue|n8n)' } | Sort-Object)
  $evidence = [ordered]@{}
  foreach ($key in $queueKeys) {
    $type = ((Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', 'TYPE', $key)) -join '').Trim()
    $size = $null
    switch ($type) {
      'list' { $size = ((Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', 'LLEN', $key)) -join '').Trim() }
      'zset' { $size = ((Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', 'ZCARD', $key)) -join '').Trim() }
      'set' { $size = ((Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', 'SCARD', $key)) -join '').Trim() }
      'hash' { $size = ((Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', 'HLEN', $key)) -join '').Trim() }
      'string' { $size = ((Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', 'STRLEN', $key)) -join '').Trim() }
      default { $size = '' }
    }
    $evidence[$key] = @{ type = $type; size = $size }
  }
  return $evidence
}

function Get-WorkerLogEvidence {
  $containers = Get-N8nWorkerContainers
  $evidence = [ordered]@{
    container_count = $containers.Count
    containers_with_execution_logs = 0
    container_ids = $containers
  }

  foreach ($container in $containers) {
    $logs = (Invoke-DockerOutput @('logs', '--tail=250', $container)) -join "`n"
    if ($logs -match '(?i)(execution|workflow|job)') {
      $evidence['containers_with_execution_logs'] = [int]$evidence['containers_with_execution_logs'] + 1
    }
  }

  return $evidence
}

function Show-ComposeDiagnostics {
  Write-Section 'Compose status'
  try { Invoke-Compose @('ps') } catch { Write-Warning $_.Exception.Message }
  Write-Section 'Compose logs'
  try { Invoke-Compose @('logs', '--no-color', '--tail=400') } catch { Write-Warning $_.Exception.Message }
}

function Invoke-HealthCheckWithRetry {
  for ($attempt = 1; $attempt -le $HealthRetries; $attempt++) {
    try {
      & (Join-Path $PSScriptRoot 'health-check.ps1') -ProjectName $ProjectName
      Invoke-WebRequest -Uri 'http://localhost:5680/healthz' -UseBasicParsing -TimeoutSec 5 | Out-Null
      Write-Host "Queue-mode health checks passed on attempt $attempt."
      return
    }
    catch {
      if ($attempt -eq $HealthRetries) {
        throw "Queue-mode health checks did not pass after $HealthRetries attempts. Last error: $($_.Exception.Message)"
      }
      Write-Host "Queue-mode health not ready yet ($attempt/$HealthRetries): $($_.Exception.Message)"
      Start-Sleep -Seconds $HealthSleepSeconds
    }
  }
}

function Assert-MockOnly {
  Write-Section 'Assert mock-only isolation'
  $envText = Get-Content -Raw -LiteralPath $envFile
  if ($envText -match '(?m)^GEMINI_API_KEY[ \t]*=[ \t]*\S+') {
    throw 'deploy/.env.mock contains a non-empty GEMINI_API_KEY; refusing to run load tests.'
  }
  if ($envText -match 'AIza[0-9A-Za-z_-]+' -or $envText -match 'sk-[0-9A-Za-z_-]+' -or $envText -match 'sk_live_') {
    throw 'deploy/.env.mock appears to contain a real-looking key; refusing to run load tests.'
  }
  $ragHealth = Invoke-RestMethod -Method Get -Uri 'http://localhost:8000/health' -TimeoutSec 10
  if ($ragHealth.mock_mode -ne $true) {
    throw "rag-api mock_mode was not true. Response: $($ragHealth | ConvertTo-Json -Depth 20 -Compress)"
  }
  Write-Host 'Mock-only gate passed.'
}

function Invoke-K6Scenario {
  param(
    [string]$Scenario,
    [string]$Script,
    [int]$Run,
    [int]$ScenarioVus,
    [string]$ScenarioDuration,
    [hashtable]$ExtraEnv = @{}
  )

  $summaryPath = Join-Path $summaryRoot "$Scenario-run$Run.json"
  $env:K6_VUS = [string]$ScenarioVus
  $env:K6_DURATION = $ScenarioDuration
  $env:K6_SUMMARY_PATH = $summaryPath
  $env:RAG_API_URL = 'http://localhost:8000'
  $env:SALES_AGENT_URL = 'http://localhost:8020'
  $env:N8N_WEBHOOK_URL = 'http://localhost:5680/webhook/twilio/whatsapp/inbound'
  $env:AGENT_AUTH_SECRET = 'mock-agent-secret'
  foreach ($key in $ExtraEnv.Keys) {
    Set-Item -Path "Env:$key" -Value ([string]$ExtraEnv[$key])
  }

  $k6Output = & k6 run (Join-Path $projectRoot $Script) 2>&1
  $k6ExitCode = $LASTEXITCODE
  $k6Output | ForEach-Object { Write-Host $_ }
  if ($k6ExitCode -ne 0) {
    throw "k6 run failed for $Scenario run $Run"
  }

  return Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
}

function Get-Median {
  param(
    [object[]]$Values,
    [string]$Property
  )
  $numbers = @($Values | ForEach-Object { [double]($_.$Property) } | Sort-Object)
  if ($numbers.Count -eq 0) {
    return 0
  }
  $middle = [math]::Floor($numbers.Count / 2)
  if ($numbers.Count % 2 -eq 1) {
    return $numbers[$middle]
  }
  return ($numbers[$middle - 1] + $numbers[$middle]) / 2
}

function Convert-ToMedianSummary {
  param(
    [string]$Scenario,
    [object[]]$Runs
  )
  return [ordered]@{
    scenario = $Scenario
    runs = $Runs.Count
    median_rps = [math]::Round((Get-Median -Values $Runs -Property 'rps'), 2)
    median_p50_ms = [math]::Round((Get-Median -Values $Runs -Property 'p50_ms'), 2)
    median_p95_ms = [math]::Round((Get-Median -Values $Runs -Property 'p95_ms'), 2)
    median_p99_ms = [math]::Round((Get-Median -Values $Runs -Property 'p99_ms'), 2)
    median_error_rate = [math]::Round((Get-Median -Values $Runs -Property 'error_rate'), 6)
    median_checks_rate = [math]::Round((Get-Median -Values $Runs -Property 'checks_rate'), 6)
  }
}

function Invoke-Warmup {
  Write-Section 'Warm-up'
  Invoke-K6Scenario -Scenario 'warmup-rag-chat' -Script 'load/k6/rag-chat.js' -Run 1 -ScenarioVus $WarmupVus -ScenarioDuration "${WarmupSeconds}s" | Out-Null
}

function Invoke-RepeatedScenario {
  param(
    [string]$Scenario,
    [string]$Script
  )
  $runs = @()
  for ($run = 1; $run -le $RunsPerScenario; $run++) {
    Write-Section "$Scenario run $run/$RunsPerScenario"
    $runs += Invoke-K6Scenario -Scenario $Scenario -Script $Script -Run $run -ScenarioVus $Vus -ScenarioDuration $Duration
  }
  return Convert-ToMedianSummary -Scenario $Scenario -Runs $runs
}

function Assert-ConsoleReplyThroughQueue {
  Write-Section 'Assert console/reply queue path'
  $ticketId = 'TICKET-LOAD-CONSOLE-' + [guid]::NewGuid().ToString('N')
  Ensure-ConsoleReplyTicket -TicketId $ticketId

  $idempotencyKey = [guid]::NewGuid().ToString()
  $replyBody = @{
    ticket_id = $ticketId
    body_text = 'Load smoke staff reply through queue mode.'
    idempotency_key = $idempotencyKey
    clerk_user_id = 'user_demo_operator'
  } | ConvertTo-Json -Depth 5
  $reply = Invoke-RestMethod -Method Post -Uri 'http://localhost:5680/webhook/console/reply' -Headers @{ Authorization = 'Bearer mock-console-secret' } -ContentType 'application/json' -Body $replyBody -TimeoutSec 60
  if (($reply.PSObject.Properties.Name -contains 'success') -and $reply.success -ne $true) {
    throw "console/reply did not return success=true. Response: $($reply | ConvertTo-Json -Depth 20 -Compress)"
  }

  $escapedKey = $idempotencyKey.Replace("'", "''")
  $messageCount = [int](Invoke-RevenueSqlScalar "select count(*) from messages where idempotency_key = '$escapedKey';")
  if ($messageCount -lt 1) {
    throw "console/reply did not write an outbound staff message for idempotency key $idempotencyKey"
  }
}

function Invoke-WorkerScenario {
  param([int]$WorkerScale)
  Write-Section "Scale n8n-worker to $WorkerScale"
  Invoke-Compose @('up', '-d', '--scale', "n8n-worker=$WorkerScale", 'n8n-worker')
  Start-Sleep -Seconds 5

  $workerContainers = Get-N8nWorkerContainers
  if ($workerContainers.Count -lt $WorkerScale) {
    throw "Expected at least $WorkerScale n8n-worker containers, found $($workerContainers.Count)."
  }

  $beforeExecutions = Get-N8nExecutionCount
  $beforeRedis = Get-RedisEvidence
  $beforeWorkerLogs = Get-WorkerLogEvidence
  $runs = @()
  for ($run = 1; $run -le $RunsPerScenario; $run++) {
    Write-Section "n8n-inbound worker=$WorkerScale run $run/$RunsPerScenario"
    $runs += Invoke-K6Scenario -Scenario "n8n-inbound-w$WorkerScale" -Script 'load/k6/n8n-inbound.js' -Run $run -ScenarioVus $Vus -ScenarioDuration $Duration
  }
  $afterExecutions = Get-N8nExecutionCount
  $afterRedis = Get-RedisEvidence
  $afterWorkerLogs = Get-WorkerLogEvidence
  $executionDelta = $afterExecutions - $beforeExecutions
  if ($executionDelta -lt 1) {
    throw "n8n execution_entity count did not increase for worker scale $WorkerScale"
  }

  if ($WorkerScale -ge 2 -and [int]$afterWorkerLogs.containers_with_execution_logs -lt 1) {
    throw "No n8n-worker container exposed execution/workflow/job log evidence for worker scale $WorkerScale."
  }

  $summary = Convert-ToMedianSummary -Scenario "n8n-inbound-w$WorkerScale" -Runs $runs
  $summary['worker_scale'] = $WorkerScale
  $summary['execution_delta'] = $executionDelta
  $summary['redis_keys_before'] = $beforeRedis
  $summary['redis_keys_after'] = $afterRedis
  $summary['worker_log_evidence_before'] = $beforeWorkerLogs
  $summary['worker_log_evidence_after'] = $afterWorkerLogs
  return $summary
}

$k6 = Get-Command k6 -ErrorAction SilentlyContinue
if ($null -eq $k6) {
  throw 'k6 was not found on PATH. Install k6 before running M2.4 load tests.'
}

New-Item -ItemType Directory -Force -Path $summaryRoot | Out-Null

try {
  Write-Section 'Validate load-test assets'
  & (Join-Path $PSScriptRoot 'verify-load-test-assets.ps1')

  Write-Section 'Validate queue Compose config'
  & (Join-Path $PSScriptRoot 'verify-queue-config.ps1') -ProjectName "$ProjectName-config"

  Write-Section 'Build and start queue-mode services'
  $upArgs = @('up', '-d', '--scale', "n8n-worker=$($WorkerScales[0])")
  if (-not $SkipBuild) {
    $upArgs += '--build'
  }
  Invoke-Compose ($upArgs + $queueServices)

  Write-Section 'Wait for health checks'
  Invoke-HealthCheckWithRetry
  Assert-MockOnly

  Invoke-Warmup

  $scenarioSummaries = @()
  $scenarioSummaries += Invoke-RepeatedScenario -Scenario 'rag-chat' -Script 'load/k6/rag-chat.js'
  $scenarioSummaries += Invoke-RepeatedScenario -Scenario 'sales-agent' -Script 'load/k6/sales-agent.js'

  Assert-ConsoleReplyThroughQueue

  foreach ($scale in $WorkerScales) {
    $scenarioSummaries += Invoke-WorkerScenario -WorkerScale $scale
  }

  $report = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    project_name = $ProjectName
    vus = $Vus
    duration = $Duration
    warmup_seconds = $WarmupSeconds
    runs_per_scenario = $RunsPerScenario
    summaries = $scenarioSummaries
    note = 'Raw k6 summaries are local artifacts under load/results and are intentionally gitignored.'
  }

  $reportPath = Join-Path $summaryRoot 'summary-curated.json'
  $report | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $reportPath
  Write-Host "Curated local summary written to $reportPath"
  Write-Host ($report | ConvertTo-Json -Depth 20)
}
catch {
  Show-ComposeDiagnostics
  throw
}
finally {
  if (-not $KeepRunning) {
    Write-Section 'Stop queue Compose project'
    try { Invoke-Compose @('down', '--remove-orphans') } catch { Write-Warning $_.Exception.Message }
  }
}

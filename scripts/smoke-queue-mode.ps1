param(
  [string]$ProjectName = 'revenueops-queue',
  [int]$WorkerScale = 2,
  [int]$HealthRetries = 80,
  [int]$HealthSleepSeconds = 5,
  [string]$ComposeOverrideFile = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot 'deploy/docker-compose.yml'
$queueComposeFile = Join-Path $projectRoot 'deploy/docker-compose.queue.yml'
$envFile = Join-Path $projectRoot 'deploy/.env.mock'

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

function Invoke-Compose {
  param(
    [string[]]$CommandArgs
  )

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
  param(
    [string[]]$CommandArgs
  )

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

function Invoke-ComposeSqlScalar {
  param(
    [string]$Database,
    [string]$Query
  )

  $output = Invoke-ComposeOutput @('exec', '-T', 'postgres', 'psql', '-U', 'postgres', '-d', $Database, '-Atc', $Query)
  return (($output -join '').Trim())
}

function Get-N8nExecutionCount {
  return [int](Invoke-ComposeSqlScalar -Database 'n8n_metadata' -Query 'select count(*) from execution_entity;')
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
    'Queue Smoke Buyer',
    jsonb_build_object('source', 'queue-smoke')
  )
  returning id
)
insert into tickets (ticket_id, customer_id, intent, status, subject, context_json)
select
  '$escapedTicketId',
  id,
  'information_query',
  'awaiting_staff',
  'Queue smoke console reply ticket',
  jsonb_build_object('source', 'queue-smoke')
from customer
on conflict (ticket_id) do nothing;
"@
  Invoke-ComposeSqlScalar -Database 'revenue_ops' -Query $query | Out-Null
}

function Write-Section {
  param([string]$Name)
  Write-Host ""
  Write-Host "==> $Name"
}

function Show-ComposeDiagnostics {
  Write-Section 'Compose status'
  try {
    Invoke-Compose @('ps')
  }
  catch {
    Write-Warning $_.Exception.Message
  }

  Write-Section 'Compose logs'
  try {
    Invoke-Compose @('logs', '--no-color', '--tail=400')
  }
  catch {
    Write-Warning $_.Exception.Message
  }
}

function Test-ResponseField {
  param(
    [object]$Response,
    [string]$FieldName,
    [string]$Description
  )

  if (-not ($Response.PSObject.Properties.Name -contains $FieldName)) {
    throw "$Description did not include '$FieldName'. Response: $($Response | ConvertTo-Json -Depth 20 -Compress)"
  }

  $value = $Response.$FieldName
  if ($null -eq $value -or ($value -is [string] -and -not $value.Trim())) {
    throw "$Description returned an empty '$FieldName'. Response: $($Response | ConvertTo-Json -Depth 20 -Compress)"
  }
}

function Test-NotFallback {
  param(
    [object]$Response,
    [string]$Description
  )

  if (($Response.PSObject.Properties.Name -contains 'fallback') -and $Response.fallback -eq $true) {
    throw "$Description returned fallback=true. Response: $($Response | ConvertTo-Json -Depth 20 -Compress)"
  }
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

try {
  Write-Section 'Validate queue Compose config'
  & (Join-Path $PSScriptRoot 'verify-queue-config.ps1') -ProjectName "$ProjectName-config"

  Write-Section 'Build and start queue-mode services'
  Invoke-Compose (@('up', '-d', '--build', '--scale', "n8n-worker=$WorkerScale") + $queueServices)

  Write-Section 'Wait for health checks'
  Invoke-HealthCheckWithRetry

  Write-Section 'Assert n8n shared volume is writable across webhook and worker'
  $probeFile = '/home/node/.n8n/binaryData/queue-smoke-cross-read.txt'
  Invoke-Compose @('exec', '-T', 'n8n-webhook', 'sh', '-lc', "mkdir -p /home/node/.n8n/binaryData && printf ok > $probeFile")
  $probeValue = (Invoke-ComposeOutput @('exec', '-T', 'n8n-worker', 'sh', '-lc', "cat $probeFile")) -join ''
  if ($probeValue.Trim() -ne 'ok') {
    throw "n8n-worker could not read binaryData probe written by n8n-webhook through the shared n8n_data volume. Read '$probeValue'."
  }
  Invoke-Compose @('exec', '-T', 'n8n-worker', 'sh', '-lc', "rm -f $probeFile")

  Write-Section 'Assert rag-api mock mode'
  $ragHealth = Invoke-RestMethod -Method Get -Uri 'http://localhost:8000/health' -TimeoutSec 10
  if ($ragHealth.mock_mode -ne $true) {
    throw "rag-api mock_mode was not true. Response: $($ragHealth | ConvertTo-Json -Depth 20 -Compress)"
  }

  $beforeExecutions = Get-N8nExecutionCount

  Write-Section 'Assert sales path through queue webhook'
  $salesBody = @{
    customer_id = '11111111-1111-4111-8111-111111111111'
    customer_phone = '+15551234567'
    customer_display_name = 'Demo Buyer'
    message_id = [guid]::NewGuid().ToString()
    inbound_text = 'I want pricing for your CRM automation product'
    intent = 'purchase'
    intent_confidence = 0.91
    ticket_id = 'TICKET-QUEUE-SALES-001'
  } | ConvertTo-Json -Depth 5
  $salesResponse = Invoke-RestMethod -Method Post -Uri 'http://localhost:5680/webhook/twilio/whatsapp/inbound' -ContentType 'application/json' -Body $salesBody -TimeoutSec 45
  Test-ResponseField -Response $salesResponse -FieldName 'qualification_tier' -Description 'queue sales webhook'
  Test-NotFallback -Response $salesResponse -Description 'queue sales webhook'

  Write-Section 'Assert RAG mock path through queue webhook'
  $ragWebhookBody = @{
    customer_id = '11111111-1111-4111-8111-111111111111'
    customer_phone = '+15551234567'
    customer_display_name = 'Demo Buyer'
    message_id = [guid]::NewGuid().ToString()
    inbound_text = 'What is your return policy?'
    intent = 'information_query'
    intent_confidence = 0.88
    ticket_id = 'TICKET-QUEUE-RAG-001'
  } | ConvertTo-Json -Depth 5
  $ragWebhookResponse = Invoke-RestMethod -Method Post -Uri 'http://localhost:5680/webhook/twilio/whatsapp/inbound' -ContentType 'application/json' -Body $ragWebhookBody -TimeoutSec 45
  Test-ResponseField -Response $ragWebhookResponse -FieldName 'answer' -Description 'queue RAG webhook'
  Test-NotFallback -Response $ragWebhookResponse -Description 'queue RAG webhook'
  if ($ragWebhookResponse.answer -notlike '*Mock RAG answer*') {
    throw "queue RAG webhook did not return the deterministic mock answer. Response: $($ragWebhookResponse | ConvertTo-Json -Depth 20 -Compress)"
  }

  Write-Section 'Assert console/reply path through queue webhook'
  $consoleTicketId = 'TICKET-QUEUE-CONSOLE-' + [guid]::NewGuid().ToString('N')
  Ensure-ConsoleReplyTicket -TicketId $consoleTicketId

  $idempotencyKey = [guid]::NewGuid().ToString()
  $replyBody = @{
    ticket_id = $consoleTicketId
    body_text = 'Queue smoke staff reply through the dedicated webhook processor.'
    idempotency_key = $idempotencyKey
    clerk_user_id = 'user_demo_operator'
  } | ConvertTo-Json -Depth 5
  $replyResponse = Invoke-RestMethod -Method Post -Uri 'http://localhost:5680/webhook/console/reply' -Headers @{ Authorization = 'Bearer mock-console-secret' } -ContentType 'application/json' -Body $replyBody -TimeoutSec 45
  if (($replyResponse.PSObject.Properties.Name -contains 'success') -and $replyResponse.success -ne $true) {
    throw "queue console/reply did not return success=true. Response: $($replyResponse | ConvertTo-Json -Depth 20 -Compress)"
  }

  $escapedIdempotencyKey = $idempotencyKey.Replace("'", "''")
  $messageCount = [int](Invoke-ComposeSqlScalar -Database 'revenue_ops' -Query "select count(*) from messages where idempotency_key = '$escapedIdempotencyKey';")
  if ($messageCount -lt 1) {
    throw "queue console/reply did not write a staff message for idempotency key $idempotencyKey."
  }

  Write-Section 'Assert n8n execution records increased'
  $afterExecutions = Get-N8nExecutionCount
  if ($afterExecutions -le $beforeExecutions) {
    throw "n8n execution_entity count did not increase. Before: $beforeExecutions. After: $afterExecutions."
  }
  Write-Host "n8n execution_entity count increased from $beforeExecutions to $afterExecutions."

  Write-Section 'Assert Redis queue keys and worker logs'
  $redisKeys = @(Invoke-ComposeOutput @('exec', '-T', 'redis', 'redis-cli', '--scan'))
  $queueKeys = @($redisKeys | Where-Object { $_ -match '(?i)(bull|queue|n8n)' })
  if ($queueKeys.Count -lt 1) {
    throw "Redis did not expose any queue-like keys after queue webhook requests. Keys: $($redisKeys -join ', ')"
  }
  Write-Host "Queue-like Redis keys:"
  $queueKeys | Sort-Object | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

  $workerLogs = (Invoke-ComposeOutput @('logs', '--no-color', '--tail=500', 'n8n-worker')) -join "`n"
  if ($workerLogs -notmatch '(?i)(execution|workflow|job)') {
    throw 'n8n-worker logs did not include execution/workflow/job evidence after queue webhook requests.'
  }

  Write-Section 'Queue-mode smoke passed'
}
catch {
  Show-ComposeDiagnostics
  throw
}
finally {
  Write-Section 'Stop queue Compose project'
  try {
    Invoke-Compose @('down', '--remove-orphans')
  }
  catch {
    Write-Warning $_.Exception.Message
  }
}

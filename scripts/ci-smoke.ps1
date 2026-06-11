param(
  [string]$ProjectName = 'revenueops-ci',
  [int]$HealthRetries = 60,
  [int]$HealthSleepSeconds = 5
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot 'deploy/docker-compose.yml'
$envFile = Join-Path $projectRoot 'deploy/.env.mock'

$coreServices = @(
  'postgres',
  'ghl-mock',
  'sales-agent',
  'ghl-sync',
  'qdrant',
  'rag-api',
  'n8n'
)

function Invoke-Compose {
  param(
    [string[]]$CommandArgs
  )

  $composeArgs = @(
    'compose',
    '-p', $ProjectName,
    '--env-file', $envFile,
    '-f', $composeFile
  ) + $CommandArgs

  & docker @composeArgs
  if ($LASTEXITCODE -ne 0) {
    throw "docker $($composeArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
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
    Invoke-Compose @('logs', '--no-color', '--tail=300')
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
      Write-Host "Health checks passed on attempt $attempt."
      return
    }
    catch {
      if ($attempt -eq $HealthRetries) {
        throw "Health checks did not pass after $HealthRetries attempts. Last error: $($_.Exception.Message)"
      }

      Write-Host "Health checks not ready yet ($attempt/$HealthRetries): $($_.Exception.Message)"
      Start-Sleep -Seconds $HealthSleepSeconds
    }
  }
}

try {
  Write-Section 'Validate Compose config'
  Invoke-Compose @('config', '--quiet')

  Write-Section 'Build and start mock-first core services'
  Invoke-Compose (@('up', '-d', '--build') + $coreServices)

  Write-Section 'Wait for health checks'
  Invoke-HealthCheckWithRetry

  Write-Section 'Assert rag-api mock mode'
  $ragHealth = Invoke-RestMethod -Method Get -Uri 'http://localhost:8000/health' -TimeoutSec 10
  if ($ragHealth.mock_mode -ne $true) {
    throw "rag-api mock_mode was not true. Response: $($ragHealth | ConvertTo-Json -Depth 20 -Compress)"
  }

  $ragBody = @{
    question = 'What is your return policy?'
  } | ConvertTo-Json -Depth 5
  $ragDirect = Invoke-RestMethod -Method Post -Uri 'http://localhost:8000/chat' -ContentType 'application/json' -Body $ragBody -TimeoutSec 20
  Test-ResponseField -Response $ragDirect -FieldName 'answer' -Description 'direct rag-api mock chat'
  if ($ragDirect.answer -notlike '*Mock RAG answer*') {
    throw "direct rag-api mock chat did not return the deterministic mock answer. Response: $($ragDirect | ConvertTo-Json -Depth 20 -Compress)"
  }

  Write-Section 'Assert sales path through n8n'
  $salesBody = @{
    customer_id = '11111111-1111-4111-8111-111111111111'
    customer_phone = '+15551234567'
    customer_display_name = 'Demo Buyer'
    message_id = [guid]::NewGuid().ToString()
    inbound_text = 'I want pricing for your CRM automation product'
    intent = 'purchase'
    intent_confidence = 0.91
    ticket_id = 'TICKET-CI-SALES-001'
  } | ConvertTo-Json -Depth 5
  $salesResponse = Invoke-RestMethod -Method Post -Uri 'http://localhost:5678/webhook/twilio/whatsapp/inbound' -ContentType 'application/json' -Body $salesBody -TimeoutSec 30
  Test-ResponseField -Response $salesResponse -FieldName 'qualification_tier' -Description 'sales n8n webhook'
  Test-NotFallback -Response $salesResponse -Description 'sales n8n webhook'

  Write-Section 'Assert RAG mock path through n8n'
  $ragWebhookBody = @{
    customer_id = '11111111-1111-4111-8111-111111111111'
    customer_phone = '+15551234567'
    customer_display_name = 'Demo Buyer'
    message_id = [guid]::NewGuid().ToString()
    inbound_text = 'What is your return policy?'
    intent = 'information_query'
    intent_confidence = 0.88
    ticket_id = 'TICKET-CI-RAG-001'
  } | ConvertTo-Json -Depth 5
  $ragWebhookResponse = Invoke-RestMethod -Method Post -Uri 'http://localhost:5678/webhook/twilio/whatsapp/inbound' -ContentType 'application/json' -Body $ragWebhookBody -TimeoutSec 30
  Test-ResponseField -Response $ragWebhookResponse -FieldName 'answer' -Description 'RAG n8n webhook'
  Test-NotFallback -Response $ragWebhookResponse -Description 'RAG n8n webhook'
  if ($ragWebhookResponse.answer -notlike '*Mock RAG answer*') {
    throw "RAG n8n webhook did not return the deterministic mock answer. Response: $($ragWebhookResponse | ConvertTo-Json -Depth 20 -Compress)"
  }

  Write-Section 'CI smoke passed'
}
catch {
  Show-ComposeDiagnostics
  throw
}
finally {
  Write-Section 'Stop CI Compose project'
  try {
    Invoke-Compose @('down', '--remove-orphans')
  }
  catch {
    Write-Warning $_.Exception.Message
  }
}

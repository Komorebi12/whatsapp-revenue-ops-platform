param(
  [string]$Namespace = 'revenue-ops',
  [int]$WorkerScale = 2,
  [int]$ReadyTimeoutSeconds = 600,
  [int]$PortForwardPort = 5680
)

$ErrorActionPreference = 'Stop'

function Write-Section {
  param([string]$Name)
  Write-Host ""
  Write-Host "==> $Name"
}

function Invoke-Kubectl {
  param([string[]]$CommandArgs)
  & kubectl @CommandArgs
  if ($LASTEXITCODE -ne 0) {
    throw "kubectl $($CommandArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Invoke-KubectlOutput {
  param([string[]]$CommandArgs)
  $output = & kubectl @CommandArgs
  if ($LASTEXITCODE -ne 0) {
    throw "kubectl $($CommandArgs -join ' ') failed with exit code $LASTEXITCODE"
  }
  return $output
}

function Wait-Port {
  param(
    [int]$Port,
    [int]$TimeoutSeconds = 60
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $client = [System.Net.Sockets.TcpClient]::new()
      $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
      if ($async.AsyncWaitHandle.WaitOne(1000)) {
        $client.EndConnect($async)
        $client.Close()
        return
      }
      $client.Close()
    }
    catch {
      Start-Sleep -Seconds 1
    }
  }
  throw "Port $Port did not become ready within $TimeoutSeconds seconds."
}

function Show-K8sDiagnostics {
  Write-Section 'Kubernetes pods'
  try { Invoke-Kubectl @('-n', $Namespace, 'get', 'pods', '-o', 'wide') } catch { Write-Warning $_.Exception.Message }

  Write-Section 'Kubernetes events'
  try { Invoke-Kubectl @('-n', $Namespace, 'get', 'events', '--sort-by=.lastTimestamp') } catch { Write-Warning $_.Exception.Message }

  Write-Section 'Recent workload logs'
  foreach ($deployment in @('n8n', 'n8n-webhook', 'n8n-worker', 'sales-agent', 'ghl-sync', 'ghl-mock', 'rag-api')) {
    try {
      Write-Host ""
      Write-Host "--- deployment/$deployment ---"
      Invoke-Kubectl @('-n', $Namespace, 'logs', "deployment/$deployment", '--tail=120', '--all-containers=true')
    }
    catch {
      Write-Warning $_.Exception.Message
    }
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

function Invoke-WebhookSmoke {
  param([string]$TicketSuffix)

  Write-Section "Assert sales path through K8s webhook ($TicketSuffix)"
  $salesBody = @{
    customer_id = '11111111-1111-4111-8111-111111111111'
    customer_phone = '+15551234567'
    customer_display_name = 'Demo Buyer'
    message_id = [guid]::NewGuid().ToString()
    inbound_text = 'I want pricing for your CRM automation product'
    intent = 'purchase'
    intent_confidence = 0.91
    ticket_id = "TICKET-K8S-SALES-$TicketSuffix"
  } | ConvertTo-Json -Depth 5
  $salesResponse = Invoke-RestMethod -Method Post -Uri "http://localhost:$PortForwardPort/webhook/twilio/whatsapp/inbound" -ContentType 'application/json' -Body $salesBody -TimeoutSec 60
  Test-ResponseField -Response $salesResponse -FieldName 'qualification_tier' -Description 'K8s sales webhook'
  Test-NotFallback -Response $salesResponse -Description 'K8s sales webhook'

  Write-Section "Assert RAG mock path through K8s webhook ($TicketSuffix)"
  $ragBody = @{
    customer_id = '11111111-1111-4111-8111-111111111111'
    customer_phone = '+15551234567'
    customer_display_name = 'Demo Buyer'
    message_id = [guid]::NewGuid().ToString()
    inbound_text = 'What is your return policy?'
    intent = 'information_query'
    intent_confidence = 0.88
    ticket_id = "TICKET-K8S-RAG-$TicketSuffix"
  } | ConvertTo-Json -Depth 5
  $ragResponse = Invoke-RestMethod -Method Post -Uri "http://localhost:$PortForwardPort/webhook/twilio/whatsapp/inbound" -ContentType 'application/json' -Body $ragBody -TimeoutSec 60
  Test-ResponseField -Response $ragResponse -FieldName 'answer' -Description 'K8s RAG webhook'
  Test-NotFallback -Response $ragResponse -Description 'K8s RAG webhook'
  if ($ragResponse.answer -notlike '*Mock RAG answer*') {
    throw "K8s RAG webhook did not return the deterministic mock answer. Response: $($ragResponse | ConvertTo-Json -Depth 20 -Compress)"
  }
}

$portForward = $null
$portForwardLog = Join-Path ([System.IO.Path]::GetTempPath()) ('revenueops-k8s-port-forward-{0}.log' -f ([guid]::NewGuid().ToString('N')))

try {
  Write-Section 'Wait for core deployments'
  foreach ($deployment in @('postgres', 'redis', 'qdrant', 'ghl-mock', 'sales-agent', 'ghl-sync', 'rag-api', 'n8n', 'n8n-webhook', 'n8n-worker')) {
    Invoke-Kubectl @('-n', $Namespace, 'rollout', 'status', "deployment/$deployment", "--timeout=${ReadyTimeoutSeconds}s")
  }

  Write-Section 'Assert rag-api mock mode inside the cluster'
  $ragHealth = Invoke-KubectlOutput @('-n', $Namespace, 'exec', 'deployment/rag-api', '--', 'python', '-c', "import json, urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=10).read().decode())")
  $ragHealthJson = ($ragHealth -join "`n") | ConvertFrom-Json
  if ($ragHealthJson.mock_mode -ne $true) {
    throw "rag-api mock_mode was not true in K8s. Response: $($ragHealthJson | ConvertTo-Json -Depth 20 -Compress)"
  }

  Write-Section 'Start port-forward to n8n-webhook'
  $portForwardArgs = @('-n', $Namespace, 'port-forward', 'svc/n8n-webhook', "$PortForwardPort`:5678")
  $portForward = Start-Process -FilePath 'kubectl' -ArgumentList $portForwardArgs -NoNewWindow -WindowStyle Hidden -PassThru -RedirectStandardOutput $portForwardLog -RedirectStandardError $portForwardLog
  Wait-Port -Port $PortForwardPort -TimeoutSeconds 60

  Invoke-WebhookSmoke -TicketSuffix '001'

  Write-Section "Scale n8n-worker to $WorkerScale replicas"
  Invoke-Kubectl @('-n', $Namespace, 'scale', 'deployment/n8n-worker', "--replicas=$WorkerScale")
  Invoke-Kubectl @('-n', $Namespace, 'rollout', 'status', 'deployment/n8n-worker', "--timeout=${ReadyTimeoutSeconds}s")

  Invoke-WebhookSmoke -TicketSuffix '002'

  Write-Section 'Assert Redis exposes queue-like keys'
  $redisKeys = @(Invoke-KubectlOutput @('-n', $Namespace, 'exec', 'deployment/redis', '--', 'redis-cli', '--scan'))
  $queueKeys = @($redisKeys | Where-Object { $_ -match '(?i)(bull|queue|n8n)' })
  if ($queueKeys.Count -lt 1) {
    throw "Redis did not expose queue-like keys after K8s webhook requests. Keys: $($redisKeys -join ', ')"
  }
  $queueKeys | Sort-Object | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }

  Write-Section 'K8s smoke passed'
}
catch {
  Show-K8sDiagnostics
  throw
}
finally {
  if ($null -ne $portForward -and -not $portForward.HasExited) {
    Stop-Process -Id $portForward.Id -Force
  }
  if (Test-Path -LiteralPath $portForwardLog) {
    Remove-Item -LiteralPath $portForwardLog -Force
  }
}


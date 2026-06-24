param(
  [string]$Namespace = 'revenue-ops',
  [int]$PortForwardPort = 5680,
  [int]$WorkerScale = 2,
  [int]$Vus = 3,
  [string]$Duration = '30s',
  [int]$WarmupSeconds = 10,
  [int]$ReadyTimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$resultsRoot = Join-Path $projectRoot 'load/results'
$summaryRoot = Join-Path $resultsRoot ('kind-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Section {
  param([string]$Name)
  Write-Host ''
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
  param([int]$Port, [int]$TimeoutSeconds = 60)
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

function Get-RestartCounts {
  $json = (Invoke-KubectlOutput @('-n', $Namespace, 'get', 'pods', '-o', 'json')) -join "`n"
  $pods = $json | ConvertFrom-Json
  $counts = [ordered]@{}
  foreach ($pod in $pods.items) {
    $sum = 0
    foreach ($status in $pod.status.containerStatuses) {
      $sum += [int]$status.restartCount
    }
    $counts[$pod.metadata.name] = $sum
  }
  return $counts
}

function Assert-NoRestartIncrease {
  param(
    [System.Collections.IDictionary]$Before,
    [System.Collections.IDictionary]$After
  )
  foreach ($podName in $Before.Keys) {
    if ($After.Contains($podName) -and [int]$After[$podName] -gt [int]$Before[$podName]) {
      throw "Pod $podName restartCount increased from $($Before[$podName]) to $($After[$podName]) during under-load validation."
    }
  }
}

function Show-K8sDiagnostics {
  Write-Section 'Kubernetes pods'
  try { Invoke-Kubectl @('-n', $Namespace, 'get', 'pods', '-o', 'wide') } catch { Write-Warning $_.Exception.Message }
  Write-Section 'Kubernetes events'
  try { Invoke-Kubectl @('-n', $Namespace, 'get', 'events', '--sort-by=.lastTimestamp') } catch { Write-Warning $_.Exception.Message }
  Write-Section 'Recent n8n logs'
  foreach ($deployment in @('n8n', 'n8n-webhook', 'n8n-worker')) {
    try {
      Write-Host "--- deployment/$deployment ---"
      Invoke-Kubectl @('-n', $Namespace, 'logs', "deployment/$deployment", '--tail=120', '--all-containers=true')
    }
    catch { Write-Warning $_.Exception.Message }
  }
}

function Invoke-K6Kind {
  param(
    [string]$Name,
    [int]$ScenarioVus,
    [string]$ScenarioDuration
  )
  $summaryPath = Join-Path $summaryRoot "$Name.json"
  $env:K6_VUS = [string]$ScenarioVus
  $env:K6_DURATION = $ScenarioDuration
  $env:K6_SUMMARY_PATH = $summaryPath
  $env:N8N_WEBHOOK_URL = "http://localhost:$PortForwardPort/webhook/twilio/whatsapp/inbound"
  $k6Output = & k6 run (Join-Path $projectRoot 'load/k6/n8n-inbound.js') 2>&1
  $k6ExitCode = $LASTEXITCODE
  $k6Output | ForEach-Object { Write-Host $_ }
  if ($k6ExitCode -ne 0) {
    throw "k6 kind under-load run failed for $Name"
  }
  return Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
}

$k6 = Get-Command k6 -ErrorAction SilentlyContinue
if ($null -eq $k6) {
  throw 'k6 was not found on PATH. Install k6 before running the K8s under-load smoke.'
}

$portForward = $null
$portForwardLogPrefix = Join-Path ([System.IO.Path]::GetTempPath()) ('revenueops-load-k8s-port-forward-' + [guid]::NewGuid().ToString('N'))
$portForwardStdoutLog = "$portForwardLogPrefix.out.log"
$portForwardStderrLog = "$portForwardLogPrefix.err.log"
New-Item -ItemType Directory -Force -Path $summaryRoot | Out-Null

try {
  Write-Section 'Roll out core deployments'
  foreach ($deployment in @('postgres', 'redis', 'qdrant', 'ghl-mock', 'sales-agent', 'ghl-sync', 'rag-api', 'n8n', 'n8n-webhook', 'n8n-worker')) {
    Invoke-Kubectl @('-n', $Namespace, 'rollout', 'status', "deployment/$deployment", "--timeout=${ReadyTimeoutSeconds}s")
  }

  Write-Section "Scale n8n-worker to $WorkerScale"
  Invoke-Kubectl @('-n', $Namespace, 'scale', 'deployment/n8n-worker', "--replicas=$WorkerScale")
  Invoke-Kubectl @('-n', $Namespace, 'rollout', 'status', 'deployment/n8n-worker', "--timeout=${ReadyTimeoutSeconds}s")

  Write-Section 'Start port-forward to n8n-webhook'
  $portForwardArgs = @('-n', $Namespace, 'port-forward', 'svc/n8n-webhook', "$PortForwardPort`:5678")
  $portForward = Start-Process -FilePath 'kubectl' -ArgumentList $portForwardArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $portForwardStdoutLog -RedirectStandardError $portForwardStderrLog
  Wait-Port -Port $PortForwardPort -TimeoutSeconds 60

  Write-Section 'Warm-up'
  Invoke-K6Kind -Name 'warmup' -ScenarioVus 1 -ScenarioDuration "${WarmupSeconds}s" | Out-Null

  $beforeRestarts = Get-RestartCounts

  Write-Section 'Run fixed under-load validation'
  $summary = Invoke-K6Kind -Name 'under-load' -ScenarioVus $Vus -ScenarioDuration $Duration

  $afterRestarts = Get-RestartCounts
  Assert-NoRestartIncrease -Before $beforeRestarts -After $afterRestarts

  $report = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    namespace = $Namespace
    worker_scale = $WorkerScale
    vus = $Vus
    duration = $Duration
    summary = $summary
    restart_counts_before = $beforeRestarts
    restart_counts_after = $afterRestarts
    note = 'single-node kind deployment-under-load validation; not a throughput benchmark'
  }
  $reportPath = Join-Path $summaryRoot 'summary-curated.json'
  $report | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $reportPath
  Write-Host "Curated local K8s summary written to $reportPath"
  Write-Host ($report | ConvertTo-Json -Depth 20)
}
catch {
  Show-K8sDiagnostics
  throw
}
finally {
  if ($null -ne $portForward -and -not $portForward.HasExited) {
    Stop-Process -Id $portForward.Id -Force
  }
  foreach ($logPath in @($portForwardStdoutLog, $portForwardStderrLog)) {
    if (Test-Path -LiteralPath $logPath) {
      Remove-Item -LiteralPath $logPath -Force
    }
  }
}

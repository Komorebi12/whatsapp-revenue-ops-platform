param(
  [string]$Phone = '+15551234567',
  [string]$CustomerName = 'Demo Buyer',
  [string]$TicketId = 'TICKET-PHASE1A-001'
)

$ErrorActionPreference = 'Stop'

$messages = @(
  'Hi, I am interested in your product',
  'We have 50 users and need it this month with a $5000 budget',
  'Can we see pricing and book a demo?'
)

foreach ($message in $messages) {
  $messageId = [guid]::NewGuid().ToString()
  Write-Host "Sending: $message"
  & (Join-Path $PSScriptRoot 'simulate-message.ps1') `
    -Message $message `
    -Phone $Phone `
    -CustomerName $CustomerName `
    -TicketId $TicketId `
    -MessageId $messageId
  Start-Sleep -Seconds 1
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $projectRoot 'deploy')

docker compose exec -T postgres psql -U postgres -d revenue_ops -c "select total_score, qualification_tier, score_breakdown, updated_at from lead_scores order by updated_at desc limit 1;"

param(
  [string]$Message = 'Hi, I am interested in your product',
  [string]$Phone = '+15551234567',
  [string]$CustomerName = 'Demo Buyer',
  [string]$TicketId = 'TICKET-PHASE1A-001',
  [string]$MessageId = '22222222-2222-4222-8222-222222222222'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $projectRoot 'deploy')

$body = @{
  customer_id = '11111111-1111-4111-8111-111111111111'
  customer_phone = $Phone
  customer_display_name = $CustomerName
  message_id = $MessageId
  inbound_text = $Message
  intent = 'purchase'
  intent_confidence = 0.91
  ticket_id = $TicketId
} | ConvertTo-Json -Depth 5

try {
  Invoke-RestMethod -Method Post -Uri 'http://localhost:5678/webhook/twilio/whatsapp/inbound' -ContentType 'application/json' -Body $body
}
catch {
  Write-Warning "n8n webhook unavailable, falling back to sales-agent direct call."
  $agentSecret = if ($env:AGENT_AUTH_SECRET) { $env:AGENT_AUTH_SECRET } else { 'mock-agent-secret' }
  Invoke-RestMethod -Method Post -Uri 'http://localhost:8020/agent/respond' -Headers @{ 'X-Agent-Secret' = $agentSecret } -ContentType 'application/json' -Body $body
}

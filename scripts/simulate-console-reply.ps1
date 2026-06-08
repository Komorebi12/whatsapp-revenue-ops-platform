param(
  [string]$TicketId = 'TICKET-PHASE1A-001',
  [string]$BodyText = 'Thanks for the details. A teammate will follow up shortly.',
  [string]$ClerkUserId = 'user_demo_operator',
  [string]$IdempotencyKey = ''
)

$ErrorActionPreference = 'Stop'
if (-not $IdempotencyKey) {
  $IdempotencyKey = [guid]::NewGuid().ToString()
}

$secret = if ($env:MVP_REPLY_WEBHOOK_SECRET) { $env:MVP_REPLY_WEBHOOK_SECRET } else { 'mock-console-secret' }
$body = @{
  ticket_id = $TicketId
  body_text = $BodyText
  idempotency_key = $IdempotencyKey
  clerk_user_id = $ClerkUserId
} | ConvertTo-Json -Depth 5

Invoke-RestMethod `
  -Method Post `
  -Uri 'http://localhost:5678/webhook/console/reply' `
  -Headers @{ Authorization = "Bearer $secret" } `
  -ContentType 'application/json' `
  -Body $body

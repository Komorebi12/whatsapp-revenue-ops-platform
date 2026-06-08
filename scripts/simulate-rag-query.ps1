param(
  [string]$Message = 'What is your return policy?',
  [string]$Phone = '+15551234567',
  [string]$CustomerName = 'Demo Buyer',
  [string]$TicketId = 'TICKET-PHASE1A-001',
  [string]$MessageId = ''
)

$ErrorActionPreference = 'Stop'
if (-not $MessageId) {
  $MessageId = [guid]::NewGuid().ToString()
}

$body = @{
  customer_id = '11111111-1111-4111-8111-111111111111'
  customer_phone = $Phone
  customer_display_name = $CustomerName
  message_id = $MessageId
  inbound_text = $Message
  intent = 'information_query'
  intent_confidence = 0.88
  ticket_id = $TicketId
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri 'http://localhost:5678/webhook/twilio/whatsapp/inbound' -ContentType 'application/json' -Body $body
Start-Sleep -Seconds 3

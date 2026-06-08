param(
  [int]$Limit = 5
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $projectRoot 'deploy')

Write-Host 'customers'
docker compose exec -T postgres psql -U postgres -d revenue_ops -c "select id, phone, display_name, last_seen_at from customers order by last_seen_at desc nulls last limit $Limit;"

Write-Host 'tickets'
docker compose exec -T postgres psql -U postgres -d revenue_ops -c "select ticket_id, customer_id, status, updated_at from tickets order by updated_at desc nulls last limit $Limit;"

Write-Host 'messages'
docker compose exec -T postgres psql -U postgres -d revenue_ops -c "select id, ticket_id, direction, sender_role, left(body_text, 80) as body_text, created_at from messages order by created_at desc limit $Limit;"

Write-Host 'lead_scores'
docker compose exec -T postgres psql -U postgres -d revenue_ops -c "select customer_id, total_score, qualification_tier, updated_at from lead_scores order by updated_at desc nulls last limit $Limit;"

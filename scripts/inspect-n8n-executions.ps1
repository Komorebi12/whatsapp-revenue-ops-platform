param(
  [int]$Limit = 10
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $projectRoot 'deploy')

$query = @"
select
  id,
  "workflowId" as workflow_id,
  status,
  "startedAt" as started_at,
  "stoppedAt" as stopped_at
from execution_entity
order by id desc
limit $Limit;
"@

$query | docker compose exec -T postgres psql -U postgres -d n8n_metadata

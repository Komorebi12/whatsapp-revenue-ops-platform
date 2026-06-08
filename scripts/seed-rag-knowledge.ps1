param(
  [string]$RagApiBaseUrl = 'http://localhost:8000',
  [string]$SeedDir = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $SeedDir) {
  $SeedDir = Join-Path $projectRoot 'deploy\rag-seed'
}

$pdfs = Get-ChildItem -Path $SeedDir -Filter '*.pdf' -File
if ($pdfs.Count -eq 0) {
  throw "No PDF seed files found in $SeedDir"
}

foreach ($pdf in $pdfs) {
  Write-Host "Uploading RAG seed: $($pdf.Name)"
  $client = [System.Net.Http.HttpClient]::new()
  $content = [System.Net.Http.MultipartFormDataContent]::new()
  $stream = [System.IO.File]::OpenRead($pdf.FullName)
  $fileContent = [System.Net.Http.StreamContent]::new($stream)
  $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/pdf')
  $content.Add($fileContent, 'file', $pdf.Name)
  try {
    $response = $client.PostAsync("$RagApiBaseUrl/documents/upload", $content).GetAwaiter().GetResult()
    $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) {
      throw "Upload failed with status $([int]$response.StatusCode): $responseBody"
    }
    $responseBody | ConvertFrom-Json | Format-List
  }
  finally {
    $stream.Dispose()
    $content.Dispose()
    $client.Dispose()
  }
  Start-Sleep -Seconds 3
}

Write-Host 'RAG seed complete'
Invoke-RestMethod -Method Get -Uri "$RagApiBaseUrl/collection" | Format-List

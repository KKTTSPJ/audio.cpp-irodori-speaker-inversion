# start_server.ps1 - starts audiocpp_server.exe from the package folder.
# Creates server_config.json on the first run (edit it freely afterwards; it is never overwritten),
# then runs the server in this window and opens the WebUI in the browser once it is ready.
param([int]$Port = 8090, [switch]$NoBrowser)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$server = Join-Path $root "audiocpp_server.exe"
$config = Join-Path $root "server_config.json"
$modelDir = Join-Path $root "models\Irodori-TTS-v4-Small-GGUF"
$voiceDir = Join-Path $root "voices"

function Fail([string]$message) {
  Write-Host ""
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

if (-not (Test-Path -LiteralPath $server)) {
  Fail ("audiocpp_server.exe was not found in $root.`n" +
        "Extract this launcher zip into the folder of the binary package (cpu-avx2 or cuda12.8).")
}

# Which backends does this build have? (a missing CUDA DLL makes the exe fail to start at all)
$versionText = (& $server --version 2>&1 | Out-String)
if ($LASTEXITCODE -eq -1073741515) {
  Fail ("audiocpp_server.exe could not start because a DLL is missing.`n" +
        "For the CUDA build, extract the cudart zip into this folder as well.")
}
if ($versionText -notmatch 'backends:\s*([^\r\n]+)') {
  Fail "Unexpected output of 'audiocpp_server.exe --version':`n$versionText"
}
$backend = if ($Matches[1] -match 'cuda') { 'cuda' } else { 'cpu' }

$models = @(Get-ChildItem -LiteralPath $modelDir -Filter *.gguf -File -ErrorAction SilentlyContinue)
if ($models.Count -eq 0) {
  Fail "No model found in $modelDir`nRun download_model.bat first."
}
if ($models.Count -gt 1) {
  Fail "More than one .gguf file in $modelDir`nKeep exactly one model file in that folder."
}
New-Item -ItemType Directory -Force -Path $voiceDir | Out-Null

if (-not (Test-Path -LiteralPath $config)) {
  $threads = 1
  if ($backend -eq 'cpu') {
    $threads = [int](@(Get-CimInstance Win32_Processor) | Measure-Object NumberOfCores -Sum).Sum
    if ($threads -lt 1) { $threads = [Environment]::ProcessorCount }
  }
  $cfg = [ordered]@{
    host = "127.0.0.1"
    port = $Port
    backend = $backend
    device = 0
    threads = $threads
    ui = $true
    voice_dir = ($voiceDir -replace '\\', '/')
    models = @([ordered]@{
      id = "irodori-tts"
      family = "irodori_tts"
      path = ($modelDir -replace '\\', '/')
      task = "tts"
      mode = "offline"
      session_options = [ordered]@{
        "irodori_tts.mem_saver" = "true"
        "irodori_tts.condition_graph_arena_mb" = "64"
        "irodori_tts.rf_graph_arena_mb" = "128"
        "irodori_tts.codec_graph_arena_mb" = "128"
        "irodori_tts.codec_decode_chunk_steps" = "100"
        "irodori_tts.codec_encode_chunk_steps" = "100"
        "irodori_tts.codec_weight_type" = "f16"
        "irodori_tts.max_ref_seconds" = "checkpoint"
      }
    })
  }
  [IO.File]::WriteAllText($config, ($cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
  Write-Host "Created $config (backend: $backend)"
}

$settings = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
$urlHost = if ($settings.host -eq "0.0.0.0") { "127.0.0.1" } else { $settings.host }
$url = "http://${urlHost}:$($settings.port)/"

try {
  $null = Invoke-WebRequest "${url}health" -UseBasicParsing -TimeoutSec 2
  Write-Host "A server is already running at $url"
  if (-not $NoBrowser) { Start-Process $url }
  exit 0
} catch { }

if (-not $NoBrowser) {
  # Open the WebUI once /health answers (loading the model takes a few seconds).
  $null = Start-Job -ArgumentList $url -ScriptBlock {
    param($u)
    for ($i = 0; $i -lt 180; $i++) {
      try { $null = Invoke-WebRequest "${u}health" -UseBasicParsing -TimeoutSec 2; Start-Process $u; return } catch { Start-Sleep -Seconds 1 }
    }
  }
}

Write-Host ""
Write-Host "Starting audiocpp_server ($backend) with $config"
Write-Host "WebUI and API: $url    (close this window or press Ctrl+C to stop)"
Write-Host ""
Set-Location -LiteralPath $root
& $server --config $config
exit $LASTEXITCODE

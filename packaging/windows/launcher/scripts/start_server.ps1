# start_server.ps1 - starts audiocpp_server.exe from the package folder.
# Creates server_config.json on the first run (edit it freely afterwards; it is never overwritten),
# then runs the server in this window and opens the WebUI in the browser once it is ready.
param([int]$Port = 8090, [switch]$NoBrowser)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$server = Join-Path $root "audiocpp_server.exe"
$config = Join-Path $root "server_config.json"
$modelDir = Join-Path $root "models\Irodori-TTS-v4-Small-GGUF"
$modelFileName = "irodori-tts-v4-small-q8_0.gguf"
$voiceDir = Join-Path $root "voices"

function Fail([string]$message) {
  Write-Host ""
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

function Has-Property($object, [string]$name) {
  return ($null -ne $object) -and ($object.PSObject.Properties.Name -contains $name)
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
# Fork builds from v0.9.0 on print a "model manager:" line and understand "session_option_defaults"
# (session options that also reach models the WebUI loads). With "model manager: yes" the WebUI can
# download and switch models ("ui_management"). The launcher writes it as false: with it on, the
# WebUI lists only upstream's demo voices, so the embeddings in voices\ cannot be picked there.
$isV090Fork = $versionText -match '(?m)^model manager:'
$hasModelManager = $versionText -match '(?m)^model manager:\s*yes'

New-Item -ItemType Directory -Force -Path $voiceDir | Out-Null

if (-not (Test-Path -LiteralPath $config)) {
  $models = @(Get-ChildItem -LiteralPath $modelDir -Filter *.gguf -File -ErrorAction SilentlyContinue)
  if ($models.Count -eq 0) {
    Fail "No model found in $modelDir`nRun download_model.bat first."
  }
  $model = @($models | Where-Object { $_.Name -eq $modelFileName })
  if ($model.Count -eq 0) {
    if ($models.Count -gt 1) {
      Fail "More than one .gguf file in $modelDir and none is named $modelFileName`nRun download_model.bat, or keep exactly one model file in that folder."
    }
    $model = $models
  }
  $threads = 1
  if ($backend -eq 'cpu') {
    $threads = [int](@(Get-CimInstance Win32_Processor) | Measure-Object NumberOfCores -Sum).Sum
    if ($threads -lt 1) { $threads = [Environment]::ProcessorCount }
  }
  # Options that bound peak memory (README_launcher.txt).
  $memoryOptions = [ordered]@{
    "irodori_tts.mem_saver" = "true"
    "irodori_tts.condition_graph_arena_mb" = "64"
    "irodori_tts.rf_graph_arena_mb" = "128"
    "irodori_tts.codec_graph_arena_mb" = "128"
    "irodori_tts.codec_decode_chunk_steps" = "100"
    "irodori_tts.codec_encode_chunk_steps" = "100"
    "irodori_tts.codec_weight_type" = "f16"
    "irodori_tts.max_ref_seconds" = "checkpoint"
  }
  $modelEntry = [ordered]@{
    id = "irodori-tts"
    family = "irodori_tts"
    path = ($model[0].FullName -replace '\\', '/')
    task = "tts"
    mode = "offline"
  }
  $cfg = [ordered]@{
    host = "127.0.0.1"
    port = $Port
    backend = $backend
    device = 0
    threads = $threads
    ui = $true
  }
  if ($isV090Fork) {
    if ($hasModelManager) { $cfg.ui_management = $false }
    $cfg.session_option_defaults = $memoryOptions
  } else {
    $modelEntry.session_options = $memoryOptions
  }
  $cfg.voice_dir = ($voiceDir -replace '\\', '/')
  $cfg.models = @($modelEntry)
  [IO.File]::WriteAllText($config, ($cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
  Write-Host "Created $config (backend: $backend)"
}

$settings = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
$management = (Has-Property $settings "ui_management") -and $settings.ui_management
if ($management -and -not $hasModelManager) {
  Fail "server_config.json has ui_management enabled, but this build has no model manager.`n(Use a v0.9.0 or later package, or remove ui_management from the config.)"
}

# Check the model the config points to (a file, or a folder that must hold exactly one .gguf).
foreach ($entry in @($settings.models)) {
  if (-not (Has-Property $entry "path")) { continue }
  $path = $entry.path -replace '/', '\'
  if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $root $path }
  if (Test-Path -LiteralPath $path -PathType Leaf) { continue }
  $found = @(Get-ChildItem -LiteralPath $path -Filter *.gguf -File -ErrorAction SilentlyContinue)
  if ($found.Count -eq 0) {
    Fail "No model found at $path`nRun download_model.bat first."
  }
  if ($found.Count -gt 1) {
    Fail ("More than one .gguf file in $path`n" +
          "Set ""path"" of model ""$($entry.id)"" in server_config.json to the .gguf file to use.")
  }
}

if ($hasModelManager -and -not $management) {
  Write-Host ('Note: WebUI model management (download / switch models) can be turned on with' + "`n" +
              '      "ui_management": true in server_config.json; see README_launcher.txt.') -ForegroundColor Yellow
}
if ($management -and -not (Has-Property $settings "session_option_defaults")) {
  Write-Host ('Note: models loaded from the WebUI run without the memory options. Move them from "session_options"' + "`n" +
              '      to "session_option_defaults" in server_config.json; see README_launcher.txt.') -ForegroundColor Yellow
}
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

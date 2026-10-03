# download_model.ps1 - downloads the Irodori-TTS v4 Small GGUF (Q8_0) package used by start_server.bat
# from https://huggingface.co/audio-cpp/audio.cpp-gguf and checks its SHA256.
param([switch]$Yes)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$repo = "audio-cpp/audio.cpp-gguf"
$folder = "Irodori-TTS-v4-Small-GGUF"
$file = "irodori-tts-v4-small-q8_0.gguf"
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root "models\$folder"
$dest = Join-Path $dir $file
$part = "$dest.part"
$url = "https://huggingface.co/$repo/resolve/main/$folder/$file"

function Fail([string]$message) {
  Write-Host ""
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

Write-Host "Model: Irodori-TTS v4 Small, GGUF Q8_0 (audio.cpp package)"
Write-Host "  from $url"
Write-Host ""
Write-Host "Irodori-TTS is released by Aratako under the MIT License, with ethical restrictions:"
Write-Host "  - Do not clone or impersonate anyone's voice without their explicit consent."
Write-Host "  - Do not create deepfakes or speech intended to mislead or spread misinformation."
Write-Host "  - You are responsible for how you use the generated speech."
Write-Host "  Details: https://huggingface.co/Aratako/Irodori-TTS-v4.1-Small"
Write-Host ""

try {
  $listing = Invoke-RestMethod "https://huggingface.co/api/models/$repo/tree/main/$folder" -TimeoutSec 30
} catch {
  Fail "Could not reach huggingface.co: $($_.Exception.Message)"
}
$entry = @($listing | Where-Object { $_.path -eq "$folder/$file" })[0]
if ($null -eq $entry -or $null -eq $entry.lfs) { Fail "$folder/$file was not found in $repo." }
$size = [int64]$entry.size
$sha256 = ([string]$entry.lfs.oid).ToLowerInvariant()

if (Test-Path -LiteralPath $dest) {
  Write-Host "Checking the existing $dest ..."
  if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sha256) {
    Write-Host "The model is already downloaded and up to date."
    exit 0
  }
  Fail ("$dest exists but differs from the current file on Hugging Face.`n" +
        "Delete or move it, then run download_model.bat again.")
}
# Upstream's package list (the WebUI model manager) installs other Irodori-TTS packages into the
# same folder. That is fine: server_config.json created by start_server points to the file itself.
$others = @(Get-ChildItem -LiteralPath $dir -Filter *.gguf -File -ErrorAction SilentlyContinue)
if ($others.Count -gt 0) {
  Write-Host ("Note: $dir also contains $($others[0].Name).`n" +
              "      If server_config.json points to the folder instead of a .gguf file, set it to $file.") -ForegroundColor Yellow
}

if (-not $Yes) {
  $answer = Read-Host ("Download {0:N2} GB into {1} ? [y/N]" -f ($size / 1GB), $dir)
  if ($answer -notmatch '^(y|yes)$') { Write-Host "Cancelled."; exit 1 }
}
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($curl) {
  # -C - resumes an interrupted download from the .part file.
  & $curl.Source -L --fail --retry 3 --retry-delay 5 -C - -o $part $url
  if ($LASTEXITCODE -ne 0) { Fail "Download failed (curl exit code $LASTEXITCODE). Run download_model.bat again to resume." }
} else {
  Write-Host "Downloading (no progress display)..."
  Invoke-WebRequest $url -OutFile $part -UseBasicParsing
}

if ((Get-Item -LiteralPath $part).Length -ne $size) {
  Fail "The downloaded size does not match ($size bytes expected). Run download_model.bat again to resume."
}
Write-Host "Verifying SHA256 ..."
if ((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256) {
  Remove-Item -LiteralPath $part
  Fail "SHA256 mismatch; the partial file was deleted. Run download_model.bat again."
}
Move-Item -LiteralPath $part -Destination $dest
Write-Host ""
Write-Host "Done: $dest"
Write-Host "Next: run start_server.bat"

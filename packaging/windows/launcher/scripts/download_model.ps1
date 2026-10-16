# download_model.ps1 - downloads models for start_server.bat from Hugging Face and checks their SHA256.
# Without -Model it shows a numbered list (scripts\models.ps1) and asks which to download.
#   -Model <numbers or keys>  e.g. -Model 1,6  or  -Model irodori-v4.1-small-q8
#   -Yes                      no questions; without -Model this downloads the default model only
#   -AcceptLicense            accept licenses that need explicit consent (non-commercial models)
#   -List                     show the list and exit
# start_server.bat adds every downloaded model to server_config.json.
param([string[]]$Model = @(), [switch]$Yes, [switch]$AcceptLicense, [switch]$List)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "models.ps1")

function Fail([string]$message) {
  Write-Host ""
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

function Show-ModelList {
  $group = ""
  for ($i = 0; $i -lt $LauncherModels.Count; $i++) {
    $m = $LauncherModels[$i]
    if ($m.Group -ne $group) {
      $group = $m.Group
      Write-Host ""
      Write-Host "  $group"
    }
    $state = if (Test-Path -LiteralPath (Get-LauncherModelFile $m $root) -PathType Leaf) { "downloaded" } else { "" }
    $mark = if ($m.IsDefault) { "*" } else { " " }
    Write-Host ("  {0,2}{1} {2,-45} {3,5:N2} GB  {4,-26} {5}" -f ($i + 1), $mark, $m.Title, $m.SizeGB, $m.License, $state)
  }
  Write-Host ""
  Write-Host "  * default (what start_server.bat uses for test_tts.bat and the API examples)"
}

function Resolve-Selection([string[]]$items) {
  $picked = @()
  foreach ($item in ($items -join ",").Split(",")) {
    $t = $item.Trim()
    if ($t -eq "") { continue }
    $n = 0
    if ([int]::TryParse($t, [ref]$n)) {
      if ($n -lt 1 -or $n -gt $LauncherModels.Count) { Fail "No model number $t (1 to $($LauncherModels.Count))." }
      $m = $LauncherModels[$n - 1]
    } else {
      $m = @($LauncherModels | Where-Object { $_.Key -eq $t })[0]
      if ($null -eq $m) { Fail "Unknown model '$t'. Run download_model.bat -List to see the names." }
    }
    if (@($picked | Where-Object { $_.Key -eq $m.Key }).Count -eq 0) { $picked += $m }
  }
  return $picked
}

# Downloads one model; returns $true when the file is in place (new or already up to date).
function Get-Model($m) {
  $dest = Get-LauncherModelFile $m $root
  $dir = Split-Path -Parent $dest
  $part = "$dest.part"
  $url = "https://huggingface.co/$($m.Repo)/resolve/$($m.Revision)/$($m.RemotePath)"
  $parent = Split-Path -Parent ($m.RemotePath -replace '/', '\')
  $treePath = if ($parent) { "/" + ($parent -replace '\\', '/') } else { "" }
  Write-Host ""
  Write-Host "=== $($m.Title)"
  Write-Host "  from $url"
  try {
    $listing = Invoke-RestMethod "https://huggingface.co/api/models/$($m.Repo)/tree/$($m.Revision)$treePath" -TimeoutSec 30
  } catch {
    Write-Host "  Could not reach huggingface.co: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }
  $entry = @($listing | Where-Object { $_.path -eq $m.RemotePath })[0]
  if ($null -eq $entry -or $null -eq $entry.lfs) {
    Write-Host "  $($m.RemotePath) was not found in $($m.Repo)." -ForegroundColor Red
    return $false
  }
  $size = [int64]$entry.size
  $sha256 = ([string]$entry.lfs.oid).ToLowerInvariant()

  if (Test-Path -LiteralPath $dest) {
    Write-Host "  Checking the existing $dest ..."
    if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sha256) {
      Write-Host "  Already downloaded and up to date."
      return $true
    }
    Write-Host ("  $dest exists but differs from the current file on Hugging Face.`n" +
                "  Delete or move it, then run download_model.bat again.") -ForegroundColor Red
    return $false
  }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    # -C - resumes an interrupted download from the .part file.
    & $curl.Source -L --fail --retry 3 --retry-delay 5 -C - -o $part $url
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  Download failed (curl exit code $LASTEXITCODE). Run download_model.bat again to resume." -ForegroundColor Red
      return $false
    }
  } else {
    Write-Host "  Downloading (no progress display)..."
    Invoke-WebRequest $url -OutFile $part -UseBasicParsing
  }
  if ((Get-Item -LiteralPath $part).Length -ne $size) {
    Write-Host "  The downloaded size does not match ($size bytes expected). Run download_model.bat again to resume." -ForegroundColor Red
    return $false
  }
  Write-Host "  Verifying SHA256 ..."
  if ((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256) {
    Remove-Item -LiteralPath $part
    Write-Host "  SHA256 mismatch; the partial file was deleted. Run download_model.bat again." -ForegroundColor Red
    return $false
  }
  Move-Item -LiteralPath $part -Destination $dest
  Write-Host "  Done: $dest"
  return $true
}

Write-Host "Models for the audio.cpp Irodori-TTS Speaker Inversion launcher (saved under $root\models)"
if ($List) { Show-ModelList; exit 0 }

if ($Model.Count -gt 0) {
  $selected = @(Resolve-Selection $Model)
} elseif ($Yes) {
  $selected = @($LauncherModels | Where-Object { $_.IsDefault })
} else {
  Show-ModelList
  Write-Host ""
  $answer = Read-Host "Numbers to download, separated by commas (Enter = the default, 1; q = quit)"
  if ($answer -match '^\s*q') { Write-Host "Cancelled."; exit 1 }
  if ($answer.Trim() -eq "") { $answer = "1" }
  $selected = @(Resolve-Selection @($answer))
}
if ($selected.Count -eq 0) { Write-Host "Nothing selected."; exit 1 }

# Licenses first, so that every question comes before the downloads start.
$todo = @()
foreach ($m in $selected) {
  Write-Host ""
  Write-Host "--- $($m.Title)  [$($m.License)]"
  foreach ($line in $m.Notice) { Write-Host $line }
  if ($m.NeedsConsent -and -not $AcceptLicense) {
    if ($Yes) { Write-Host "Skipped $($m.Title): with -Yes, add -AcceptLicense to accept this license."; continue }
    $agree = Read-Host "Type 'agree' to accept this license and download the model (anything else skips it)"
    if ($agree.Trim() -ne "agree") { Write-Host "Skipped $($m.Title)."; continue }
  }
  $todo += $m
}
if ($todo.Count -eq 0) { Write-Host ""; Write-Host "Nothing to download."; exit 1 }
$missing = @($todo | Where-Object { -not (Test-Path -LiteralPath (Get-LauncherModelFile $_ $root) -PathType Leaf) })
$total = ($missing | Measure-Object SizeGB -Sum).Sum
if (-not $Yes -and $missing.Count -gt 0) {
  Write-Host ""
  $answer = Read-Host ("Download {0} model(s), about {1:N2} GB, into {2}\models ? [y/N]" -f $missing.Count, $total, $root)
  if ($answer -notmatch '^(y|yes)$') { Write-Host "Cancelled."; exit 1 }
}

$failed = @()
foreach ($m in $todo) {
  if (-not (Get-Model $m)) { $failed += $m }
}
Write-Host ""
if ($failed.Count -gt 0) {
  Fail ("Not downloaded: " + (($failed | ForEach-Object { $_.Title }) -join ", "))
}
Write-Host "All selected models are in place."
Write-Host "Next: run start_server.bat (it adds new models to server_config.json)."

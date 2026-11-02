# convert_v4_large.ps1 - makes the Irodori-TTS v4 Large GGUF, which is not published: downloads
# the original checkpoint and the DACVAE codec from Hugging Face (scripts\models.ps1 pins the
# revisions) into sources\, then converts them with audiocpp_gguf.exe into models\.
# Without -Type it shows the types and asks which to make.
#   -Type <numbers or types>  e.g. -Type 1  or  -Type q8_0,q4_k
#   -Yes                      no questions; without -Type this makes Q8_0 only; keeps sources\
#   -AcceptLicense            accept the Gemma Terms of Use without typing 'agree'
#   -DeleteSource             delete sources\ after a successful conversion without asking
#   -List                     show the types and exit
# This does what tools/models/convert_irodori_gguf.py of the repository does, without Python.
# start_server.bat adds every converted model to server_config.json.
param([string[]]$Type = @(), [switch]$Yes, [switch]$AcceptLicense, [switch]$DeleteSource, [switch]$List)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "models.ps1")
. (Join-Path $PSScriptRoot "huggingface.ps1")
$converter = Join-Path $root "audiocpp_gguf.exe"
$sourceDir = Join-Path $root "sources\Irodori-TTS-v4-Large"
$codecFile = Join-Path $root ("sources\Semantic-DACVAE-Japanese-32dim\" + $DacvaeSource.File)

function Fail([string]$message) {
  Write-Host ""
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

function Show-TypeList {
  Write-Host ""
  for ($i = 0; $i -lt $ConvertedModels.Count; $i++) {
    $m = $ConvertedModels[$i]
    $state = if (Test-Path -LiteralPath (Get-LauncherModelFile $m $root) -PathType Leaf) { "converted" } else { "" }
    $mark = if ($m.IsDefault) { "*" } else { " " }
    Write-Host ("  {0,2}{1} {2,-36} {3,5:N2} GB  id {4,-27} {5}" -f ($i + 1), $mark, $m.Title, $m.SizeGB, $m.Id, $state)
  }
  Write-Host ""
  Write-Host "  * default. Q8_0 is closest to the original; the smaller types need less memory."
}

function Resolve-Selection([string[]]$items) {
  $picked = @()
  foreach ($item in ($items -join ",").Split(",")) {
    $t = $item.Trim().ToLowerInvariant()
    if ($t -eq "") { continue }
    $n = 0
    if ([int]::TryParse($t, [ref]$n)) {
      if ($n -lt 1 -or $n -gt $ConvertedModels.Count) { Fail "No type number $t (1 to $($ConvertedModels.Count))." }
      $m = $ConvertedModels[$n - 1]
    } else {
      $m = @($ConvertedModels | Where-Object { $_.Type -eq $t -or $_.Key -eq $t })[0]
      if ($null -eq $m) { Fail "Unknown type '$t'. Run convert_v4_large.bat -List to see them." }
    }
    if (@($picked | Where-Object { $_.Key -eq $m.Key }).Count -eq 0) { $picked += $m }
  }
  return $picked
}

# The safetensors header: 8 bytes of little-endian length, then that much JSON with each tensor's
# dtype and shape, and "__metadata__" (Irodori keeps its config JSON there).
function Read-SafetensorsHeader([string]$path) {
  $stream = [IO.File]::OpenRead($path)
  try {
    $reader = New-Object IO.BinaryReader $stream
    $length = $reader.ReadUInt64()
    if ($length -gt 100MB) { throw "unexpected safetensors header length $length" }
    $json = [Text.Encoding]::UTF8.GetString($reader.ReadBytes([int]$length))
  } finally { $stream.Dispose() }
  return $json | ConvertFrom-Json
}

# 2-D weights whose input width is not a multiple of 256: a k-quant would leave them in F32 (the
# 1152-wide T5Gemma 2 projections), so they are stored as Q8_0. Embeddings keep the converter's
# F16 rule. Same rule as k_quant_fallbacks() in convert_irodori_gguf.py.
function Get-KQuantFallbacks($header) {
  $names = @()
  foreach ($p in $header.PSObject.Properties) {
    if ($p.Name -eq "__metadata__") { continue }
    $shape = @($p.Value.shape)
    if ($p.Name.EndsWith(".weight") -and $shape.Count -eq 2 -and $p.Name.ToLowerInvariant() -notlike "*embed*" -and
        ([int64]$shape[1] % 256) -ne 0 -and ([int64]$shape[1] % 32) -eq 0) {
      $names += $p.Name
    }
  }
  return $names
}

Write-Host "Irodori-TTS v4 Large for the audio.cpp Irodori-TTS Speaker Inversion launcher"
if ($List) { Show-TypeList; exit 0 }

if (-not (Test-Path -LiteralPath $converter)) {
  Fail ("audiocpp_gguf.exe was not found in $root.`n" +
        "Packages before it was included (v0.9.3 and older) cannot make or run Irodori-TTS v4 Large;" +
        "`nuse a newer binary package.")
}
# Windows PowerShell turns redirected stderr of a program into errors, which "Stop" would raise.
$ErrorActionPreference = "Continue"
$null = & $converter --help 2>&1
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -eq -1073741515) {
  Fail ("audiocpp_gguf.exe could not start because a DLL is missing.`n" +
        "For the CUDA build, extract the cudart zip into this folder as well.")
}

if ($Type.Count -gt 0) {
  $selected = @(Resolve-Selection $Type)
} elseif ($Yes) {
  $selected = @($ConvertedModels | Where-Object { $_.IsDefault })
} else {
  Show-TypeList
  Write-Host ""
  $answer = Read-Host "Numbers of the types to make, separated by commas (Enter = the default, 1; q = quit)"
  if ($answer -match '^\s*q') { Write-Host "Cancelled."; exit 1 }
  if ($answer.Trim() -eq "") { $answer = "1" }
  $selected = @(Resolve-Selection @($answer))
}
$todo = @($selected | Where-Object { -not (Test-Path -LiteralPath (Get-LauncherModelFile $_ $root) -PathType Leaf) })
foreach ($m in $selected) {
  if ($todo -notcontains $m) { Write-Host "Already converted: $(Get-LauncherModelFile $m $root)" }
}
if ($todo.Count -eq 0) { Write-Host "Nothing to convert. Delete a file to make it again."; exit 0 }

Write-Host ""
Write-Host "--- Irodori-TTS v4 Large  [$($todo[0].License)]"
foreach ($line in $todo[0].Notice) { Write-Host $line }
if (-not $AcceptLicense) {
  if ($Yes) { Fail "With -Yes, add -AcceptLicense to accept the Gemma Terms of Use." }
  $agree = Read-Host "Type 'agree' to accept these terms and make the model (anything else cancels)"
  if ($agree.Trim() -ne "agree") { Write-Host "Cancelled."; exit 1 }
}

Write-Host ""
Write-Host "Checking the files on Hugging Face ..."
$largeFiles = Get-HfFileList $LargeSource.Repo $LargeSource.Revision -Recursive
if ($null -eq $largeFiles) { Fail "Could not get the file list of $($LargeSource.Repo)." }
$codecEntry = @(Get-HfFileList $DacvaeSource.Repo $DacvaeSource.Revision | Where-Object { $_.path -eq $DacvaeSource.File })[0]
if ($null -eq $codecEntry) { Fail "$($DacvaeSource.File) was not found in $($DacvaeSource.Repo)." }
if (@($largeFiles | Where-Object { $_.path -eq "model.safetensors" }).Count -eq 0) {
  Fail "model.safetensors was not found in $($LargeSource.Repo)."
}
$downloads = @($largeFiles | ForEach-Object { [pscustomobject]@{ Source = $LargeSource; Entry = $_; Dest = Join-Path $sourceDir ($_.path -replace '/', '\') } }) +
             [pscustomobject]@{ Source = $DacvaeSource; Entry = $codecEntry; Dest = $codecFile }
$downloadBytes = [int64](($downloads | Where-Object { -not (Test-Path -LiteralPath $_.Dest) } | ForEach-Object { [int64]$_.Entry.size } | Measure-Object -Sum).Sum)
$outputBytes = [int64](($todo | Measure-Object SizeGB -Sum).Sum * 1e9)
$free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($root))).AvailableFreeSpace
Write-Host ("  Download: {0:N2} GB into {1}\sources (kept for later conversions unless deleted)" -f ($downloadBytes / 1e9), $root)
Write-Host ("  Output:   {0:N2} GB into {1}\models ({2})" -f ($outputBytes / 1e9), $root, (($todo | ForEach-Object { $_.Type.ToUpperInvariant() }) -join ", "))
Write-Host ("  Free space on the drive: {0:N2} GB" -f ($free / 1e9))
Write-Host "  The conversion reads the 13 GB checkpoint and takes several minutes per type."
if ($free -lt $downloadBytes + $outputBytes + 1e9) { Fail "Not enough free space on the drive." }
if (-not $Yes) {
  $answer = Read-Host "Continue? [y/N]"
  if ($answer -notmatch '^(y|yes)$') { Write-Host "Cancelled."; exit 1 }
}

foreach ($d in $downloads) {
  if ($null -ne $d.Entry.lfs -and -not (Test-Path -LiteralPath $d.Dest)) {
    Write-Host ""
    Write-Host ("=== {0} ({1:N2} GB)" -f $d.Entry.path, ([int64]$d.Entry.size / 1e9))
  }
  if (-not (Save-HfFile $d.Source.Repo $d.Source.Revision $d.Entry $d.Dest "convert_v4_large.bat")) {
    Fail "Not downloaded: $($d.Source.Repo)/$($d.Entry.path)"
  }
}
Write-Host ""
Write-Host "All source files are in place."

$model = Join-Path $sourceDir "model.safetensors"
$header = Read-SafetensorsHeader $model
$metadata = $header.__metadata__
if ($null -eq $metadata -or $null -eq $metadata.config_json -or $null -eq $metadata.text_encoder_config_json) {
  Fail "$model has no Irodori config in its metadata."
}
$fallbacks = @(Get-KQuantFallbacks $header)
$work = Join-Path ([IO.Path]::GetTempPath()) ("irodori_gguf_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$failed = @()
try {
  # The config JSON goes into the GGUF as the sidecars the runtime reads.
  $utf8 = New-Object Text.UTF8Encoding $false
  $sidecars = @{ "model_config.json" = $metadata.config_json; "text_encoder_config.json" = $metadata.text_encoder_config_json }
  foreach ($name in $sidecars.Keys) { [IO.File]::WriteAllText((Join-Path $work $name), $sidecars[$name] + "`n", $utf8) }
  foreach ($m in $todo) {
    $dest = Get-LauncherModelFile $m $root
    $partial = $dest -replace '\.gguf$', '.converting.gguf'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    $arguments = @("--family", "irodori_tts", "--input", "model_weights=$model", "--input", "codec_weights=$codecFile",
                   "--root", $sourceDir, "--type", $m.Type, "--output", $partial, "--overwrite")
    foreach ($name in $sidecars.Keys) { $arguments += @("--sidecar", "$(Join-Path $work $name)=$name") }
    if ($m.Type -like "q*_k") { foreach ($name in $fallbacks) { $arguments += @("--keep-type", "model_weights/$name=q8_0") } }
    Write-Host ""
    Write-Host "=== $($m.Title)"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    & $converter @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $partial)) {
      Write-Host "  audiocpp_gguf.exe failed (exit code $LASTEXITCODE)." -ForegroundColor Red
      Remove-Item -LiteralPath $partial -ErrorAction SilentlyContinue
      $failed += $m
      continue
    }
    Move-Item -LiteralPath $partial -Destination $dest -Force
    Write-Host ("  Done in {0:N1} min: {1} ({2:N2} GB)" -f $clock.Elapsed.TotalMinutes, $dest, ((Get-Item -LiteralPath $dest).Length / 1e9)) -ForegroundColor Green
  }
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
if ($failed.Count -gt 0) {
  Fail ("Not converted: " + (($failed | ForEach-Object { $_.Title }) -join ", "))
}

$sources = Join-Path $root "sources"
$sourceBytes = [int64]((Get-ChildItem -LiteralPath $sources -Recurse -File | Measure-Object Length -Sum).Sum)
$remove = $DeleteSource
if (-not $remove -and -not $Yes) {
  $answer = Read-Host ("Delete the downloaded source files in {0} ({1:N2} GB)? They are only needed to make another type. [y/N]" -f $sources, ($sourceBytes / 1e9))
  $remove = $answer -match '^(y|yes)$'
}
if ($remove) {
  Remove-Item -LiteralPath $sourceDir, (Split-Path -Parent $codecFile) -Recurse -Force
  if (@(Get-ChildItem -LiteralPath $sources -Force).Count -eq 0) { Remove-Item -LiteralPath $sources }
  Write-Host "Deleted the source files."
} else {
  Write-Host "Kept the source files in $sources (delete the folder when no longer needed)."
}
Write-Host "Next: run start_server.bat (it adds the converted models to server_config.json)."

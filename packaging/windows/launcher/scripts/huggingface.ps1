# huggingface.ps1 - downloads files from Hugging Face and checks them against the repository's
# file list. Dot-sourced by download_model.ps1 and convert_v4_large.ps1.

# The files of a repository at a revision, from the Hugging Face API (path, size, lfs.oid = SHA256
# for LFS files, oid = git blob SHA-1 for the others). $Folder limits it to one folder;
# -Recursive includes subfolders. Returns $null when huggingface.co cannot be reached.
function Get-HfFileList([string]$Repo, [string]$Revision, [string]$Folder = "", [switch]$Recursive) {
  $treePath = if ($Folder) { "/" + ($Folder -replace '\\', '/') } else { "" }
  $query = if ($Recursive) { "?recursive=true" } else { "" }
  try {
    $listing = Invoke-RestMethod "https://huggingface.co/api/models/$Repo/tree/$Revision$treePath$query" -TimeoutSec 30
  } catch {
    Write-Host "  Could not reach huggingface.co: $($_.Exception.Message)" -ForegroundColor Red
    return $null
  }
  return @($listing | Where-Object { $_.type -eq "file" })
}

# Git's blob id of a file: SHA-1 of "blob <size>\0" followed by the content.
function Get-GitBlobSha1([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $header = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
  $sha1 = [Security.Cryptography.SHA1]::Create()
  try {
    $null = $sha1.TransformBlock($header, 0, $header.Length, $null, 0)
    $null = $sha1.TransformFinalBlock($bytes, 0, $bytes.Length)
    return ([BitConverter]::ToString($sha1.Hash) -replace '-', '').ToLowerInvariant()
  } finally { $sha1.Dispose() }
}

function Test-HfFile($Entry, [string]$Path) {
  if ((Get-Item -LiteralPath $Path).Length -ne [int64]$Entry.size) { return $false }
  if ($null -ne $Entry.lfs) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$Entry.lfs.oid).ToLowerInvariant()
  }
  return (Get-GitBlobSha1 $Path) -eq ([string]$Entry.oid).ToLowerInvariant()
}

# Downloads one file of Get-HfFileList to $Dest (resumable through $Dest.part) and checks it.
# A file already at $Dest is kept when it matches and reported when it does not.
# $Again names what to run to retry. Returns $true when the file is in place.
function Save-HfFile([string]$Repo, [string]$Revision, $Entry, [string]$Dest, [string]$Again) {
  $url = "https://huggingface.co/$Repo/resolve/$Revision/$($Entry.path)"
  $part = "$Dest.part"
  if (Test-Path -LiteralPath $Dest) {
    if ($null -ne $Entry.lfs) { Write-Host "  Checking the existing $Dest ..." }
    if (Test-HfFile $Entry $Dest) {
      if ($null -ne $Entry.lfs) { Write-Host "  Already downloaded and up to date." }
      return $true
    }
    Write-Host ("  $Dest exists but differs from the file on Hugging Face.`n" +
                "  Delete or move it, then run $Again again.") -ForegroundColor Red
    return $false
  }
  Write-Host "  from $url"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    # -C - resumes an interrupted download from the .part file.
    & $curl.Source -L --fail --retry 3 --retry-delay 5 -C - -o $part $url
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  Download failed (curl exit code $LASTEXITCODE). Run $Again again to resume." -ForegroundColor Red
      return $false
    }
  } else {
    Write-Host "  Downloading (no progress display)..."
    Invoke-WebRequest $url -OutFile $part -UseBasicParsing
  }
  if (-not (Test-Path -LiteralPath $part)) {
    # curl writes no file for an empty download.
    New-Item -ItemType File -Path $part | Out-Null
  }
  if ((Get-Item -LiteralPath $part).Length -ne [int64]$Entry.size) {
    Write-Host "  The downloaded size does not match ($($Entry.size) bytes expected). Run $Again again to resume." -ForegroundColor Red
    return $false
  }
  if ($null -ne $Entry.lfs) { Write-Host "  Verifying SHA256 ..." }
  if (-not (Test-HfFile $Entry $part)) {
    Remove-Item -LiteralPath $part
    Write-Host "  Checksum mismatch; the partial file was deleted. Run $Again again." -ForegroundColor Red
    return $false
  }
  Move-Item -LiteralPath $part -Destination $Dest
  return $true
}

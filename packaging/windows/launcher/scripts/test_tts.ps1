# test_tts.ps1 - sends one request to the running server and saves test.wav in the package folder.
# Usage: test_tts.bat ["text"] [voice]
#   voice = a file name (without extension) in the voices folder: a .wav reference or a
#           .speaker.safetensors Speaker Inversion embedding. Without it, no reference is used.
param([string]$Text = "", [string]$Voice = "")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $root "server_config.json"
$out = Join-Path $root "test.wav"

function Fail([string]$message) {
  Write-Host ""
  Write-Host "ERROR: $message" -ForegroundColor Red
  exit 1
}

if (-not (Test-Path -LiteralPath $config)) { Fail "server_config.json not found. Run start_server.bat first." }
$settings = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
$urlHost = if ($settings.host -eq "0.0.0.0") { "127.0.0.1" } else { $settings.host }
$url = "http://${urlHost}:$($settings.port)"
try { $null = Invoke-WebRequest "$url/health" -UseBasicParsing -TimeoutSec 3 }
catch { Fail "The server is not running at $url. Start it with start_server.bat and wait until the model is loaded." }

if ($Text -eq "") {
  # "Konnichiwa. Kore wa onsei gousei no tesuto desu." in Japanese (kept as escapes so this file stays ASCII).
  $Text = [regex]::Unescape('\u3053\u3093\u306b\u3061\u306f\u3002\u3053\u308c\u306f\u97f3\u58f0\u5408\u6210\u306e\u30c6\u30b9\u30c8\u3067\u3059\u3002')
}
$body = [ordered]@{ model = "irodori-tts"; input = $Text; response_format = "wav" }
if ($Voice -ne "") {
  # The server silently falls back to no reference for an unknown voice name, so check first.
  $voiceDir = if ($settings.voice_dir) { $settings.voice_dir -replace '/', '\' } else { Join-Path $root "voices" }
  if (-not ((Test-Path -LiteralPath (Join-Path $voiceDir "$Voice.speaker.safetensors")) -or
            (Test-Path -LiteralPath (Join-Path $voiceDir "$Voice.wav")))) {
    Fail "No $Voice.speaker.safetensors or $Voice.wav in $voiceDir"
  }
  $body.voice = $Voice
}
$json = $body | ConvertTo-Json -Compress

Write-Host "Requesting speech from $url ..."
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  Invoke-WebRequest "$url/v1/audio/speech" -Method Post -ContentType "application/json; charset=utf-8" `
    -Body ([Text.Encoding]::UTF8.GetBytes($json)) -OutFile $out -UseBasicParsing -TimeoutSec 600
} catch {
  Fail "The request failed: $($_.Exception.Message)"
}
$seconds = ((Get-Item -LiteralPath $out).Length - 44) / 2 / 48000
Write-Host ("Saved {0} ({1:N1} s of audio, generated in {2:N1} s)" -f $out, $seconds, $sw.Elapsed.TotalSeconds)

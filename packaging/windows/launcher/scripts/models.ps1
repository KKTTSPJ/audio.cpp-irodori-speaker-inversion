# models.ps1 - the models the launcher can download (download_model.ps1) and add to
# server_config.json (start_server.ps1). Dot-sourced by both.
#
# Files land where upstream's model manager puts the same packages (models\<target directory>\<file>,
# as in model_specs\*.json), so the WebUI's model management sees them as installed too.
# "Id" follows upstream's WebUI catalog (webui/configs/models_catalog.json) where it has one.
#
# The WebUI names a configured model after the catalog entry its family, task and path match, so
# a second variant in the same folder (v4.1 Small F16 / Anime next to Q8_0, MeanVC2 Q4_K next to
# F32) would show under the same name. The list therefore leaves out F16 and Q4_K, and puts Anime
# into a folder of its own, where it matches no entry and shows as plain "Irodori-TTS".

function New-LauncherModel([string]$Key, [string]$Title, [string]$Group, [double]$SizeGB, [string]$Id,
                           [string]$Family, [string]$Task, [string]$Repo, [string]$Revision,
                           [string]$RemotePath, [string]$LocalPath, [string]$License, [string[]]$Notice,
                           [bool]$NeedsConsent = $false, [bool]$IsDefault = $false) {
  return [pscustomobject]@{
    Key = $Key; Title = $Title; Group = $Group; SizeGB = $SizeGB; Id = $Id; Family = $Family; Task = $Task
    Repo = $Repo; Revision = $Revision; RemotePath = $RemotePath; LocalPath = $LocalPath
    License = $License; Notice = $Notice; NeedsConsent = $NeedsConsent; IsDefault = $IsDefault
  }
}

$ggufRepo = "audio-cpp/audio.cpp-gguf"
$irodoriNotice = @(
  "Irodori-TTS is released by Aratako under the MIT License, with ethical restrictions:",
  "  - Do not clone or impersonate anyone's voice without their explicit consent.",
  "  - Do not create deepfakes or speech intended to mislead or spread misinformation.",
  "  - You are responsible for how you use the generated speech.",
  "  Details: https://huggingface.co/Aratako/Irodori-TTS-v4.1-Small")
$vcEthics = @(
  "  Do not convert speech into anyone's voice without their explicit consent, and do not",
  "  use the output to mislead. You are responsible for how you use it.")

$LauncherModels = @(
  (New-LauncherModel "irodori-v4.1-small-q8" "Irodori-TTS v4.1 Small, GGUF Q8_0" "Text to speech (Irodori-TTS)" 1.28 `
    "irodori-tts" "irodori_tts" "tts" $ggufRepo "main" `
    "Irodori-TTS-v4-Small-GGUF/irodori-tts-v4-small-q8_0.gguf" "Irodori-TTS-v4-Small-GGUF\irodori-tts-v4-small-q8_0.gguf" `
    "MIT, ethical restrictions" $irodoriNotice $false $true),
  (New-LauncherModel "irodori-v4.1-anime-q8" "Irodori-TTS v4.1 Anime, GGUF Q8_0" "Text to speech (Irodori-TTS)" 1.04 `
    "irodori-tts-anime" "irodori_tts" "tts" $ggufRepo "main" `
    "Irodori-TTS-v4-Small-GGUF/irodori-tts-v4.1-anime-q8_0.gguf" "Irodori-TTS-v4.1-Anime-GGUF\irodori-tts-v4.1-anime-q8_0.gguf" `
    "MIT, ethical restrictions" $irodoriNotice),
  (New-LauncherModel "irodori-500m-v3-q8" "Irodori-TTS 500M v3, GGUF Q8_0" "Text to speech (Irodori-TTS)" 1.02 `
    "irodori-tts-v3-500m" "irodori_tts" "tts" $ggufRepo "main" `
    "Irodori-TTS-500M-v3-GGUF/irodori-tts-500m-v3-q8_0.gguf" "Irodori-TTS-500M-v3-GGUF\irodori-tts-500m-v3-q8_0.gguf" `
    "MIT, ethical restrictions" $irodoriNotice),
  (New-LauncherModel "irodori-600m-v3-voicedesign-q8" "Irodori-TTS 600M v3 VoiceDesign, GGUF Q8_0" "Text to speech (Irodori-TTS)" 1.18 `
    "irodori-tts-v3-vdesign" "irodori_tts" "vdes" $ggufRepo "main" `
    "Irodori-TTS-600M-v3-VoiceDesign-GGUF/irodori-tts-600m-v3-voicedesign-q8_0.gguf" "Irodori-TTS-600M-v3-VoiceDesign-GGUF\irodori-tts-600m-v3-voicedesign-q8_0.gguf" `
    "MIT, ethical restrictions" $irodoriNotice),
  (New-LauncherModel "qwen3-asr-0.6b-q8" "Qwen3-ASR 0.6B, GGUF Q8_0" "Speech recognition" 1.07 `
    "qwen3-asr" "qwen3_asr" "asr" $ggufRepo "main" `
    "Qwen3-ASR-0.6B-GGUF/qwen3-asr-0.6b-q8_0.gguf" "Qwen3-ASR-0.6B-GGUF\qwen3-asr-0.6b-q8_0.gguf" `
    "Apache-2.0" @("Qwen3-ASR is released by the Qwen team under the Apache License 2.0.",
                   "  Details: https://huggingface.co/Qwen/Qwen3-ASR-0.6B")),
  (New-LauncherModel "qwen3-asr-1.7b-q8" "Qwen3-ASR 1.7B, GGUF Q8_0" "Speech recognition" 2.30 `
    "qwen3-asr-1.7b" "qwen3_asr" "asr" $ggufRepo "main" `
    "Qwen3-ASR-1.7B-GGUF/qwen3-asr-1.7b-q8_0.gguf" "Qwen3-ASR-1.7B-GGUF\qwen3-asr-1.7b-q8_0.gguf" `
    "Apache-2.0" @("Qwen3-ASR is released by the Qwen team under the Apache License 2.0.",
                   "  Details: https://huggingface.co/Qwen/Qwen3-ASR-1.7B")),
  (New-LauncherModel "crisperwhisper-2-q8" "CrisperWhisper 2.0 Large, GGUF Q8_0" "Speech recognition" 1.60 `
    "crisperwhisper" "crisperwhisper" "asr" $ggufRepo "main" `
    "CrisperWhisper2.0-GGUF/crisperwhisper-2-large-q8_0.gguf" "CrisperWhisper2.0-GGUF\crisperwhisper-2-large-q8_0.gguf" `
    "NON-COMMERCIAL" @("CrisperWhisper 2.0: the model weights AND the transcripts they produce are licensed by",
                       "nyra health GmbH for NON-COMMERCIAL use only (nyra health Non-Commercial Research License).",
                       "  Commercial use of the model or its output needs a separate license from nyra health.",
                       "  Details: https://huggingface.co/audio-cpp/audio.cpp-gguf/blob/main/CrisperWhisper2.0-GGUF/LICENSE.md") $true),
  (New-LauncherModel "meanvc2-f32" "MeanVC2 120ms/40ms, GGUF F32" "Voice conversion" 1.52 `
    "meanvc2" "meanvc2" "vc" $ggufRepo "main" `
    "MeanVC2-GGUF/meanvc2-120ms-40ms-fp32.gguf" "MeanVC2-GGUF\meanvc2-120ms-40ms-fp32.gguf" `
    "Apache-2.0" (@("MeanVC2 is released by ASLP-lab under the Apache License 2.0.",
                    "  Details: https://huggingface.co/ASLP-lab/MeanVC2") + $vcEthics)),
  (New-LauncherModel "seed-vc-q8" "Seed-VC, GGUF Q8_0" "Voice conversion" 2.91 `
    "seed-vc" "seed_vc" "vc" $ggufRepo "main" `
    "SeedVC-MLX-GGUF/seed-vc-mlx-q8_0.gguf" "SeedVC-MLX-GGUF\seed-vc-mlx-q8_0.gguf" `
    "GPL-3.0" (@("Seed-VC is released by Plachta under the GNU General Public License v3.0 (copyleft).",
                 "  Details: https://huggingface.co/Plachta/Seed-VC") + $vcEthics))
)

function Get-LauncherModelFile($model, [string]$root) {
  return Join-Path $root ("models\" + $model.LocalPath)
}

function Get-DownloadedLauncherModels([string]$root) {
  return @($LauncherModels | Where-Object { Test-Path -LiteralPath (Get-LauncherModelFile $_ $root) -PathType Leaf })
}

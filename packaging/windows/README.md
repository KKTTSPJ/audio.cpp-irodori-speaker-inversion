# Windows launcher (release asset)

`launcher/` is packed as-is into the release asset
`audiocpp-irodori-speaker-inversion-<version>-launcher-windows.zip`. Users extract it into the
same folder as a binary package (`cpu-avx2`, or `cuda12.8` + `cudart`) and then run:

| File | Purpose |
|---|---|
| `download_model.bat` | Show the models of `scripts\models.ps1` (Irodori-TTS v4.1 Small Q8_0 as the default, v4.1 Small MeanFlow, v4.1 Anime, 500M v3, 600M v3 VoiceDesign, Qwen3-ASR 0.6B / 1.7B, CrisperWhisper 2.0, MeanVC2, Seed-VC, MioCodec) and download the chosen ones from Hugging Face into `models\`, at the paths upstream's model manager uses for the same packages (except v4.1 MeanFlow and Anime, kept in folders of their own so that the WebUI does not show them under the name of v4.1 Small). Resumable, SHA256 checked against the Hugging Face API, each model's license shown first (CrisperWhisper's non-commercial license must be accepted by typing `agree` or with `-AcceptLicense`). `-Model 1,6` / `-List` / `-Yes` (alone: the default model only) |
| `start_server.bat` | Create `server_config.json` on the first run (127.0.0.1:8090, WebUI on, CUDA or CPU detected from `audiocpp_server.exe --version`, all chunked encode/decode memory options on), start the server and open the WebUI. For a v0.9.0 or later package (`model manager:` line in `--version`) it writes the memory options as `default_session_options` for v0.9.2-r2 and later builds and as `session_option_defaults` for the v0.9.0 and v0.9.2 releases (so that WebUI-loaded models get them too), `"ui_management": true` (upstream's model management; for those releases it wrote false, because their WebUI did not list the voices in `voices\`). v0.9.2-r2 still reports version 0.9.2 (it is built on upstream's `v0.9.2-drama3-base-small`), so a 0.9.2 build counts as later unless `--version` prints exactly `0.9.2` or `0.9.2-irodori-speaker-inversion`, and points each model entry at its `.gguf` file. The config lists every downloaded model; later runs append models downloaded since (keeping `server_config.json.bak-<time>`), and with more than one model it sets `lazy_load: true` and `max_loaded_models: 1` unless the config sets them |
| `convert_v4_large.bat` | Make Irodori-TTS v4 Large, which has no published GGUF (the Gemma Terms of Use apply to its T5Gemma 2 text encoder). Shows the terms (type `agree` or `-AcceptLicense`), downloads every file of `Aratako/Irodori-TTS-v4-Large` and the DACVAE codec's `weights.pth` at the revisions pinned in `scripts\models.ps1` into `sources\` (resumable; LFS files checked by SHA256, the others by their git blob SHA-1), and runs `audiocpp_gguf.exe` the way `tools/models/convert_irodori_gguf.py` does, without Python: the sidecars come from the safetensors header's metadata, and for the k-quants the 2-D weights whose input width is not a multiple of 256 are kept as Q8_0. Types Q8_0 (default) / Q6_K / Q5_K / Q4_K, each in a folder of its own under `models\`; the result is written as `*.converting.gguf` and renamed when it is complete. Asks at the end whether to delete `sources\`. `start_server.bat` adds the converted models like downloaded ones (`$ConvertedModels`). Needs a binary package that ships `audiocpp_gguf.exe` |
| `test_tts.bat` | Send one request to the running server and write `test.wav` (to `irodori-tts`, or the first Irodori-TTS model of the config; `-Model <id>`) |
| `voices\` | `voice_dir`: reference WAVs and Speaker Inversion embeddings (`.speaker.safetensors`) |
| `README_launcher.txt` | User instructions (English and Japanese) |

The `.bat` files are thin wrappers around `scripts\*.ps1` (Windows PowerShell 5.1). Keep the
`.bat` and `.ps1` files ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts in the ANSI code
page, so non-ASCII text would break on non-Japanese systems (Japanese sample text in
`test_tts.ps1` is written as `\uXXXX` escapes). Line endings are CRLF (`launcher/.gitattributes`).
`scripts\huggingface.ps1` holds the download and checksum code shared by `download_model.ps1`
and `convert_v4_large.ps1`. When testing from PowerShell 7, clear `PSModulePath` before starting
`powershell.exe`, or Windows PowerShell inherits 7's module path and cannot find `Get-FileHash`
(double-clicking the `.bat` files is not affected).

Packing:

```powershell
Compress-Archive -Path packaging\windows\launcher\* -DestinationPath audiocpp-irodori-speaker-inversion-<version>-launcher-windows.zip
```

Do not include `.gitattributes` in the zip (it is harmless, but not needed by users).

Checked on Windows 10 with the v0.8.2-r3 CUDA and CPU packages, and again with a v0.9.0 CUDA build
(with the native model manager): extract, download, start, WebUI,
`test_tts` (no reference, embedding, Japanese argument), and the error paths (missing cudart,
missing model, server already running, unknown voice name). The model list and the automatic
additions to `server_config.json` were checked with a v0.9.2 CUDA build: every listed model
downloaded, added to the config and answered a request.

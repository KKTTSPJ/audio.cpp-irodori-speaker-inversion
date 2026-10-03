# Windows launcher (release asset)

`launcher/` is packed as-is into the release asset
`audiocpp-irodori-speaker-inversion-<version>-launcher-windows.zip`. Users extract it into the
same folder as a binary package (`cpu-avx2`, or `cuda12.8` + `cudart`) and then run:

| File | Purpose |
|---|---|
| `download_model.bat` | Download Irodori-TTS v4 Small (GGUF Q8_0) from `audio-cpp/audio.cpp-gguf` into `models\Irodori-TTS-v4-Small-GGUF`, resumable, SHA256 checked against the Hugging Face API |
| `start_server.bat` | Create `server_config.json` on the first run (127.0.0.1:8090, WebUI on, CUDA or CPU detected from `audiocpp_server.exe --version`, all chunked encode/decode memory options on), start the server and open the WebUI. For a v0.9.0 or later package (`model manager:` line in `--version`) it also turns on WebUI model management (`ui_management`), writes the memory options as `session_option_defaults` so that WebUI-loaded models get them too, and points the model entry at the `.gguf` file |
| `test_tts.bat` | Send one request to the running server and write `test.wav` |
| `voices\` | `voice_dir`: reference WAVs and Speaker Inversion embeddings (`.speaker.safetensors`) |
| `README_launcher.txt` | User instructions (English and Japanese) |

The `.bat` files are thin wrappers around `scripts\*.ps1` (Windows PowerShell 5.1). Keep the
`.bat` and `.ps1` files ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts in the ANSI code
page, so non-ASCII text would break on non-Japanese systems (Japanese sample text in
`test_tts.ps1` is written as `\uXXXX` escapes). Line endings are CRLF (`launcher/.gitattributes`).

Packing:

```powershell
Compress-Archive -Path packaging\windows\launcher\* -DestinationPath audiocpp-irodori-speaker-inversion-<version>-launcher-windows.zip
```

Do not include `.gitattributes` in the zip (it is harmless, but not needed by users).

Checked on Windows 10 with the v0.8.2-r3 CUDA and CPU packages, and again with a v0.9.0 CUDA build
(with the native model manager): extract, download, start, WebUI,
`test_tts` (no reference, embedding, Japanese argument), and the error paths (missing cudart,
missing model, server already running, unknown voice name).

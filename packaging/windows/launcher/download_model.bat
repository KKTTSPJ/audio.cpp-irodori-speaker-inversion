@echo off
rem Downloads the Irodori-TTS v4 Small GGUF (Q8_0, about 1.3 GB) into models\Irodori-TTS-v4-Small-GGUF.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\download_model.ps1" %*
pause

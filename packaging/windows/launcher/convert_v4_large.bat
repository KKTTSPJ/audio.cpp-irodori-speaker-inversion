@echo off
rem Makes the Irodori-TTS v4 Large GGUF (not published) from the original checkpoint on Hugging Face.
rem Options: -List, -Type 1  or  -Type q8_0,q4_k, -Yes, -AcceptLicense, -DeleteSource
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\convert_v4_large.ps1" %*
pause

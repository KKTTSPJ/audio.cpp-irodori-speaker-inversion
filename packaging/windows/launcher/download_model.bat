@echo off
rem Downloads models into models\ from a numbered list (Enter = Irodori-TTS v4.1 Small).
rem Options: -List, -Model 1,6, -Yes, -AcceptLicense
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\download_model.ps1" %*
pause

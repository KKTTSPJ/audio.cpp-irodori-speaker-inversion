@echo off
rem Sends one request to the running server and saves test.wav.
rem Usage: test_tts.bat ["text"] [voice name from the voices folder]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\test_tts.ps1" %*
pause

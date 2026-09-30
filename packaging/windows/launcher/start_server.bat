@echo off
rem Starts audiocpp_server.exe with server_config.json and opens the WebUI.
rem Options: -Port <n> (only used when server_config.json is created), -NoBrowser
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start_server.ps1" %*
if errorlevel 1 pause

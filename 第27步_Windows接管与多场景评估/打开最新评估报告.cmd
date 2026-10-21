@echo off
powershell.exe -NoProfile -File "%~dp0open-latest-report.ps1"
if errorlevel 1 pause

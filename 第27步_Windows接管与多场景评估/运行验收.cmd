@echo off
powershell.exe -NoProfile -File "%~dp0run-evaluation.ps1" -Mode Verify
pause

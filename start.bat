@echo off
setlocal
cd /d "%~dp0"
set "CHECKLIST_BOOTSTRAP_USER=lucas.santiago"
set "CHECKLIST_BOOTSTRAP_NAME=Lucas Santiago"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"

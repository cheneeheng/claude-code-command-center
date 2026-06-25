@echo off
set PORT=7779
set PROJECT_ROOT=%CD%
cd /d "%~dp0"
start /B python server.py %PORT% "%PROJECT_ROOT%"
timeout /t 2 /nobreak >nul
start http://localhost:%PORT%/

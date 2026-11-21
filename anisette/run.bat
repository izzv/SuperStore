@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>&1
if %errorlevel%==0 (
    py anisette_server.py %*
) else (
    python anisette_server.py %*
)
pause

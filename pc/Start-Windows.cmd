@echo off
setlocal
cd /d "%~dp0"
set "ALBO_NODE=node"
where node >nul 2>&1
if errorlevel 1 (
  if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe" (
    set "ALBO_NODE=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
  ) else (
    echo Bitte Node.js 22 oder neuer installieren: https://nodejs.org/
    pause
    exit /b 1
  )
)
echo ALBO Connect wird gestartet. Dieses Fenster offen lassen.
echo Zum Beenden Strg+C druecken oder das Fenster schliessen.
"%ALBO_NODE%" "%~dp0server.mjs" --open
if errorlevel 1 pause

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
echo Zuerst NetBird am Buero-PC verbinden.
echo Die NetBird-IP steht im NetBird-Programm und beginnt mit 100.
set /p "ALBO_VPN_IP=NetBird-IP dieses PCs: "
echo Die lokale Verwaltung bleibt nur auf diesem PC erreichbar.
echo Dieses Fenster offen lassen. Zum Beenden Strg+C druecken.
"%ALBO_NODE%" "%~dp0server.mjs" --private-vpn --open
if errorlevel 1 pause

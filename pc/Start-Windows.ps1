$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$alboNode = Get-Command node -ErrorAction SilentlyContinue
if (-not $alboNode) {
    Write-Host 'Node.js 22 oder neuer wird benötigt. Installation: https://nodejs.org/'
    exit 1
}
Write-Host 'ALBO Connect startet lokal. Im Browser http://localhost:8787 öffnen.'
Write-Host 'Dieses Fenster zum Beenden schließen oder Strg+C drücken.'
& $alboNode.Source (Join-Path $PSScriptRoot 'server.mjs')

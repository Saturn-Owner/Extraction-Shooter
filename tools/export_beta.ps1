# Exportiert den Windows-Client und den Linux-Server in build/.
#
#   .\tools\export_beta.ps1
#   .\tools\export_beta.ps1 -Godot "C:\Pfad\zu\Godot_console.exe"
#
# Voraussetzungen (einmalig):
#   1. Export-Vorlagen fuer 4.7.1 im Editor herunterladen
#      (Editor > Exportvorlagen verwalten)
#   2. export_presets.cfg anlegen — macht dieses Skript selbst, falls sie
#      fehlt (Kopie der eingecheckten Vorlage export_presets.example.cfg)

param(
    [string]$Godot = "C:\Users\Anwender\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Godot)) {
    Write-Host "Godot nicht gefunden: $Godot" -ForegroundColor Red
    Write-Host "Pfad mit -Godot uebergeben." -ForegroundColor Yellow
    exit 1
}

$presets = Join-Path $projectPath "export_presets.cfg"
if (-not (Test-Path $presets)) {
    Copy-Item (Join-Path $projectPath "export_presets.example.cfg") $presets
    Write-Host "export_presets.cfg aus der Vorlage angelegt." -ForegroundColor DarkGray
}

New-Item -ItemType Directory -Force (Join-Path $projectPath "build\windows") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $projectPath "build\linux") | Out-Null

Write-Host "Exportiere Windows Client..." -ForegroundColor Cyan
& $Godot --headless --path $projectPath --export-release "Windows Client" 2>&1 | Select-String "ERROR|error" | ForEach-Object { Write-Host $_ -ForegroundColor Red }
if ($LASTEXITCODE -ne 0) { Write-Host "Client-Export fehlgeschlagen (Exportvorlagen installiert?)" -ForegroundColor Red; exit 1 }

Write-Host "Exportiere Linux Server..." -ForegroundColor Cyan
& $Godot --headless --path $projectPath --export-release "Linux Server" 2>&1 | Select-String "ERROR|error" | ForEach-Object { Write-Host $_ -ForegroundColor Red }
if ($LASTEXITCODE -ne 0) { Write-Host "Server-Export fehlgeschlagen (Exportvorlagen installiert?)" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Fertig:" -ForegroundColor Green
Write-Host "  build\windows\extraction_shooter.exe   - an die Tester verteilen"
Write-Host "  build\linux\extraction_server.x86_64   - auf den VPS (tools/deploy_server.sh)"

# Veroeffentlicht die Launcher-Inhalte: News, Patchnotes und Roadmap.
#
#   .\tools\publish_news.ps1 -Key "<SSH-Schluessel>"
#
# Inhalte schreiben = die Dateien in docs/ editieren (neueste Eintraege
# nach oben), dieses Skript laufen lassen, fertig. Kein Spiel-Deploy noetig.

param(
    [string]$Target = "root@193.23.160.41",
    [string]$Key = ""
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot

$sshArgs = @("-o", "BatchMode=yes")
if ($Key -ne "") { $sshArgs = @("-i", $Key) + $sshArgs }

foreach ($name in @("news.json", "patchnotes.json", "roadmap.json")) {
    $file = Join-Path $projectPath "docs\$name"
    # Kaputtes JSON wuerde im Launcher nur "nicht erreichbar" zeigen -
    # hier faellt es sofort auf.
    try { Get-Content $file -Raw | ConvertFrom-Json | Out-Null }
    catch { Write-Host "docs/$name ist kein gueltiges JSON: $_" -ForegroundColor Red; exit 1 }
    scp @sshArgs $file "${Target}:/opt/extraction/downloads/$name"
    Write-Host "  $name veroeffentlicht" -ForegroundColor Green
}
Write-Host "Fertig - alle Launcher zeigen die neuen Inhalte." -ForegroundColor Green

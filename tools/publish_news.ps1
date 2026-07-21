# Veroeffentlicht docs/news.json fuer den Launcher.
#
#   .\tools\publish_news.ps1 -Key "<SSH-Schluessel>"
#
# News schreiben = docs/news.json editieren (neueste Eintraege nach oben),
# dieses Skript laufen lassen, fertig. Kein Spiel-Deploy noetig.

param(
    [string]$Target = "root@193.23.160.41",
    [string]$Key = ""
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
$news = Join-Path $projectPath "docs\news.json"

# Kaputtes JSON wuerde im Launcher nur "keine Nachrichten" zeigen -
# hier faellt es sofort auf.
try { Get-Content $news -Raw | ConvertFrom-Json | Out-Null }
catch { Write-Host "docs/news.json ist kein gueltiges JSON: $_" -ForegroundColor Red; exit 1 }

$sshArgs = @("-o", "BatchMode=yes")
if ($Key -ne "") { $sshArgs = @("-i", $Key) + $sshArgs }
scp @sshArgs $news "${Target}:/opt/extraction/downloads/news.json"
Write-Host "News veroeffentlicht." -ForegroundColor Green

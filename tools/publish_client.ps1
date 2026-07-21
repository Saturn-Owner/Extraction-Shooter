# Baut den Client und veroeffentlicht ihn fuer den Launcher.
#
#   .\tools\publish_client.ps1 -Godot "<Godot-Console-Exe>" -Key "<SSH-Schluessel>"
#
# Ablauf: exportiert die .exe, packt sie in ein ZIP, schreibt version.json
# (Versionsnummer aus dem Git-Stand, plus SHA-256-Pruefsumme des ZIPs - der
# Launcher verifiziert damit jeden Download, bevor er ihn entpackt) und legt
# beides auf den VPS in den Download-Ordner. Ab dann zieht jeder Launcher
# beim naechsten Start das Update automatisch. WICHTIG: Danach auch den
# Server ausrollen (tools/deploy_server.sh), sonst passen Client und Server
# nicht zusammen.

param(
    [string]$Godot = "C:\Users\Anwender\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
    [string]$Target = "root@193.23.160.41",
    [string]$Key = ""
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot

# Version aus Git: Anzahl Commits + Kurz-Hash, z. B. "b312-29ee3d6".
# Steigt mit jedem Commit und ist eindeutig einem Stand zuzuordnen.
$count = (git -C $projectPath rev-list --count HEAD).Trim()
$hash = (git -C $projectPath rev-parse --short HEAD).Trim()
$version = "b$count-$hash"

Write-Host "Exportiere Client (Version $version)..." -ForegroundColor Cyan
$exe = Join-Path $projectPath "build\windows\extraction_shooter.exe"
if (Test-Path $exe) { Remove-Item $exe }
# Windows PowerShell 5.1 macht aus jeder harmlosen Godot-Warnung auf
# stderr einen Abbruch, sobald ErrorActionPreference=Stop gilt. Fuer den
# einen Aufruf lokal entschaerfen - ob der Export geklappt hat, sagt die
# Datei selbst.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Godot --headless --path $projectPath --export-release "Windows Client" 2>&1 | Out-Null
$ErrorActionPreference = $previousPreference
if (-not (Test-Path $exe)) {
    Write-Host "Export fehlgeschlagen - keine exe unter build\windows" -ForegroundColor Red
    exit 1
}

$stage = Join-Path $projectPath "build\publish"
New-Item -ItemType Directory -Force $stage | Out-Null
$zip = Join-Path $stage "extraction_beta.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $exe -DestinationPath $zip
# Die echte Downloadgroesse wandert mit ins Manifest - der Launcher zeigt sie an.
$sizeMb = [math]::Round((Get-Item $zip).Length / 1MB)
$hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
@{ version = $version; file = "extraction_beta.zip"; size_mb = $sizeMb; sha256 = $hash } |
    ConvertTo-Json | Out-File -Encoding ascii (Join-Path $stage "version.json")

Write-Host "Lade auf den VPS..." -ForegroundColor Cyan
$sshArgs = @("-o", "BatchMode=yes")
if ($Key -ne "") { $sshArgs = @("-i", $Key) + $sshArgs }
# Erst das ZIP, dann version.json: Wer waehrend des Uploads prueft, sieht
# die neue Version erst, wenn die Datei dazu vollstaendig da ist.
scp @sshArgs $zip "${Target}:/opt/extraction/downloads/extraction_beta.zip"
scp @sshArgs (Join-Path $stage "version.json") "${Target}:/opt/extraction/downloads/version.json"

Write-Host "Veroeffentlicht: $version" -ForegroundColor Green
Write-Host "Nicht vergessen: tools/deploy_server.sh fuer den Serverstand." -ForegroundColor Yellow

# Baut den Launcher und veroeffentlicht ihn fuer den Selbst-Update-Mechanismus.
#
#   .\tools\publish_launcher.ps1 -Godot "<Godot-Console-Exe>" -Key "<SSH-Schluessel>"
#
# Ablauf: liest LAUNCHER_VERSION aus launcher/launcher.gd, exportiert
# ExtractionLauncher.exe, berechnet ihre SHA-256-Pruefsumme, schreibt
# launcher_version.json und legt beides auf den VPS in den Download-Ordner.
# Ab dann tauscht sich jeder laufende Launcher beim naechsten Start selbst
# aus (siehe _check_launcher_update in launcher.gd).
#
# WICHTIG: LAUNCHER_VERSION in launcher/launcher.gd von Hand hochzaehlen,
# BEVOR dieses Skript laeuft - sonst haelt der neue Launcher sich selbst
# fuer aktuell und das Manifest zeigt auf eine Version, die niemand fuer
# neuer haelt.

param(
    [string]$Godot = "C:\Users\Anwender\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
    [string]$Target = "root@193.23.160.41",
    [string]$Key = ""
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $projectPath "launcher"

# export_presets.cfg liegt nicht im Repo (lokale Pfade) - aus der Vorlage anlegen.
$presets = Join-Path $launcherPath "export_presets.cfg"
if (-not (Test-Path $presets)) {
    Copy-Item (Join-Path $launcherPath "export_presets.example.cfg") $presets
}

# LAUNCHER_VERSION direkt aus launcher.gd lesen, damit das Manifest nie von
# Hand aus dem Ruder laeuft.
$gdSource = Get-Content (Join-Path $launcherPath "launcher.gd") -Raw
if ($gdSource -notmatch 'LAUNCHER_VERSION\s*:=\s*"([^"]+)"') {
    Write-Host "LAUNCHER_VERSION nicht in launcher.gd gefunden" -ForegroundColor Red
    exit 1
}
$version = $Matches[1]

Write-Host "Exportiere Launcher (Version $version)..." -ForegroundColor Cyan
$exe = Join-Path $projectPath "build\launcher\ExtractionLauncher.exe"
if (Test-Path $exe) { Remove-Item $exe }
# Windows PowerShell 5.1 macht aus jeder harmlosen Godot-Warnung auf
# stderr einen Abbruch, sobald ErrorActionPreference=Stop gilt. Fuer den
# einen Aufruf lokal entschaerfen - ob der Export geklappt hat, sagt die
# Datei selbst.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Godot --headless --path $launcherPath --export-release "Windows Launcher" 2>&1 | Out-Null
$ErrorActionPreference = $previousPreference
if (-not (Test-Path $exe)) {
    Write-Host "Export fehlgeschlagen - keine exe unter build\launcher" -ForegroundColor Red
    exit 1
}

$hash = (Get-FileHash -Path $exe -Algorithm SHA256).Hash.ToLower()
$sizeMb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
$stage = Join-Path $projectPath "build\publish"
New-Item -ItemType Directory -Force $stage | Out-Null
@{ version = $version; file = "ExtractionLauncher.exe"; sha256 = $hash; size_mb = $sizeMb } |
    ConvertTo-Json | Out-File -Encoding ascii (Join-Path $stage "launcher_version.json")

Write-Host "Lade auf den VPS..." -ForegroundColor Cyan
$sshArgs = @("-o", "BatchMode=yes")
if ($Key -ne "") { $sshArgs = @("-i", $Key) + $sshArgs }
# Erst die exe, dann das Manifest: Wer waehrend des Uploads prueft, sieht
# die neue Version erst, wenn die Datei dazu vollstaendig da ist.
scp @sshArgs $exe "${Target}:/opt/extraction/downloads/ExtractionLauncher.exe"
scp @sshArgs (Join-Path $stage "launcher_version.json") "${Target}:/opt/extraction/downloads/launcher_version.json"

Write-Host "Veroeffentlicht: Launcher $version" -ForegroundColor Green
Write-Host "Laufende Launcher tauschen sich beim naechsten Start selbst aus." -ForegroundColor Yellow

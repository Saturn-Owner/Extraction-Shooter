# Fuehrt alle Testsuiten aus und fasst das Ergebnis zusammen.
#
#   .\tools\run_tests.ps1
#   .\tools\run_tests.ps1 -Godot "C:\Pfad\zu\Godot_console.exe"
#   .\tools\run_tests.ps1 -SkipImport      # schneller, wenn .godot/ aktuell ist
#
# Jede Suite bekommt ein hartes Zeitlimit. Haengt eine, wird sie abgebrochen
# und als Fehler gewertet - ein haengender Test ist schlimmer als ein
# fehlschlagender, weil er unbemerkt bleibt.
#
# HINWEIS: Bewusst ueber System.Diagnostics.Process statt Start-Process.
# Start-Process -PassThru liefert nach WaitForExit(millisekunden) keinen
# verwertbaren ExitCode - dadurch wurden gruene Suiten als Fehler gemeldet.

param(
    [string]$Godot = "C:\Users\Anwender\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
    [int]$TimeoutSeconds = 120,
    [switch]$SkipImport
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Godot)) {
    Write-Host "Godot nicht gefunden: $Godot" -ForegroundColor Red
    Write-Host "Pfad mit -Godot uebergeben." -ForegroundColor Yellow
    exit 1
}

function Invoke-Godot {
    param([string[]]$Arguments, [int]$Timeout)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Godot
    # ArgumentList gibt es erst ab .NET Core - Windows PowerShell 5.1 laeuft
    # auf .NET Framework, deshalb die Argumente selbst zusammensetzen.
    # Nur Argumente mit Leerzeichen brauchen Anfuehrungszeichen.
    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }
    $psi.Arguments = $quoted -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)

    # Asynchron lesen, sonst blockiert der Prozess, sobald der Ausgabepuffer
    # voll ist, und wartet ewig darauf, dass jemand liest.
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($Timeout * 1000)) {
        # Kill($true) fuer den Prozessbaum gibt es ebenfalls erst ab .NET Core.
        try { $proc.Kill() } catch {}
        return [PSCustomObject]@{ TimedOut = $true; ExitCode = -1; Output = "" }
    }

    $text = $stdout.Result + "`n" + $stderr.Result
    return [PSCustomObject]@{ TimedOut = $false; ExitCode = $proc.ExitCode; Output = $text }
}

# Nach einem frischen Clone muss einmal importiert werden, sonst kennt
# Godot die class_name-Typen nicht (.godot/ liegt bewusst nicht im Repo).
if (-not $SkipImport) {
    Write-Host "Importiere Projekt..." -ForegroundColor DarkGray
    $null = Invoke-Godot -Arguments @("--headless", "--path", $projectPath, "--import", "--quit-after", "150") -Timeout 180
}

$suites = @(
    "verify_item_data",
    "verify_inventory",
    "verify_player",
    "verify_ballistics",
    "verify_feedback",
    "verify_loadout",
    "verify_raid",
    "verify_health"
)

$failed = @()

foreach ($suite in $suites) {
    Write-Host ("{0,-22}" -f $suite) -NoNewline

    $run = Invoke-Godot -Arguments @("--headless", "--path", $projectPath, "--script", "res://tests/$suite.gd") -Timeout $TimeoutSeconds

    if ($run.TimedOut) {
        Write-Host "HAENGT (nach ${TimeoutSeconds}s abgebrochen)" -ForegroundColor Red
        $failed += $suite
        continue
    }

    $lines = $run.Output -split "`r?`n"
    $summary = ($lines | Select-String -Pattern "bestanden|ERGEBNIS" | Select-Object -Last 1)
    $summaryText = if ($summary) { $summary.ToString().Trim() } else { "(keine Zusammenfassung)" }

    # Ein Skriptfehler kann eine Pruefung ueberspringen, ohne sie scheitern zu
    # lassen - die Suite meldet dann stillschweigend weniger Pruefungen und
    # bleibt gruen. Genau so blieb ein Parserfehler im Loot-Fenster unbemerkt.
    $scriptErrors = $lines | Select-String -Pattern "SCRIPT ERROR"

    if ($run.ExitCode -eq 0 -and $scriptErrors) {
        Write-Host "FEHLER   $summaryText (Skriptfehler trotz gruener Pruefungen)" -ForegroundColor Red
        $failed += $suite
        $scriptErrors | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $($_.ToString().Trim())" -ForegroundColor DarkRed
        }
    } elseif ($run.ExitCode -eq 0) {
        Write-Host "OK   $summaryText" -ForegroundColor Green
    } else {
        Write-Host "FEHLER   $summaryText" -ForegroundColor Red
        $failed += $suite
        # Nur die fehlgeschlagenen Pruefungen zeigen, nicht die ganze Ausgabe.
        $lines | Select-String -Pattern "^\s*FEHLER|SCRIPT ERROR" | ForEach-Object {
            Write-Host "    $($_.ToString().Trim())" -ForegroundColor DarkRed
        }
    }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "Alle $($suites.Count) Suiten gruen." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($failed.Count) von $($suites.Count) Suiten fehlgeschlagen: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

# FINAL UAC DEMO (FULL CONSENT PROOF)
# Zeigt, dass KEINE Aenderung ohne explizite Zustimmung moeglich ist.
# Ablauf:
# 1. LOCK   -> JA   (Erfolg)
# 2. UNLOCK -> NEIN (Muss fehlschlagen, Datei bleibt gesperrt)
# 3. UNLOCK -> JA   (Erfolg)
# 4. LOCK   -> NEIN (Muss fehlschlagen, Datei bleibt offen)

$pwd = (Get-Item .).FullName

# Helper for detailed logging
function Log-Demo {
    param([string]$Msg)
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $logFile = Join-Path $pwd "scripts/audit_debug.log"
    "[$timestamp] [DEMO-CONTROLLER] $Msg" | Out-File $logFile -Append -Encoding utf8
    Write-Host $Msg -ForegroundColor DarkGray
}

# Clear all logs at start
$scriptsDir = Join-Path $pwd "scripts"
Remove-Item (Join-Path $scriptsDir "audit_debug.log") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $scriptsDir "lock_output.log") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $scriptsDir "unlock_output.log") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $scriptsDir "lock_processing.log") -ErrorAction SilentlyContinue

Log-Demo "--- DEMO STARTED ---"

function Show-Header {
    param($Text)
    Log-Demo "PHASE START: $Text"
    Write-Host "`n====================================================" -ForegroundColor Magenta
    Write-Host "   $Text" -ForegroundColor Magenta
    Write-Host "====================================================" -ForegroundColor Magenta
}

function Run-Audit {
    param($TargetExpect)
    Log-Demo "Run-Audit Expect=$TargetExpect Start"
    # Wir rufen das Audit-Skript auf und geben nur relevante Zeilen aus
    # -NoElevate wird genutzt, da die Demo bereits UAC/Admin-Kontext steuert.
    
    $auditPath = Join-Path $pwd "scripts/e2e-security-audit.ps1"
    
    # Starte Audit als NEUEN Prozess, damit Windows frische ACLs liest (kein Caching vom Parent)
    $proc = Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass", "-File `"$auditPath`"", "-Expect $TargetExpect", "-VerifyOnly", "-NoElevate" -Wait -PassThru -NoNewWindow
    $auditExitCode = $proc.ExitCode
    
    if ($auditExitCode -ne 0) {
    Log-Demo "Run-Audit Failed with $auditExitCode"
    Write-Host "🚨 DEMO ABBRUCH: Audit fehlgeschlagen mit Exit-Code: $auditExitCode" -ForegroundColor Red
    if (Test-Path "$PSScriptRoot\audit_debug.log") {
        Write-Host "`n--- AUDIT LOG (FEHLER DETAILS) ---" -ForegroundColor Yellow
        Get-Content "$PSScriptRoot\audit_debug.log" -Tail 30
        Write-Host "----------------------------------" -ForegroundColor Yellow
    }
    # NICHT automatisch entsperren - User soll manuell unlock-files.ps1 ausführen wenn nötig
    exit 1
}
    Log-Demo "Run-Audit Success"
    Write-Host "✨ Audit ($TargetExpect) bestanden!" -ForegroundColor Green
}

# --- PHASE 1: LOCK (JA) ---
Show-Header "PHASE 1: SPERRE AKTIVIEREN (KLICK: JA)"
Write-Host ">>> BITTE JETZT IM WINDOWS-FENSTER AUF 'JA' KLICKEN <<<" -ForegroundColor Red -BackgroundColor White

Log-Demo "Sending UAC Request for lock-files.ps1..."
Start-Process pwsh -ArgumentList "-NoProfile", "-File", "$pwd/scripts/lock-files.ps1", "-SkipProfile" -Verb RunAs -Wait
Log-Demo "UAC Request finished."

Write-Host "`nAUDIT 1: Prüfe ob Dateien GESPERRT sind (und Warnung kommt!)..." -ForegroundColor Yellow
Run-Audit "Locked"


# --- PHASE 2: UNLOCK (NEIN) ---
Show-Header "PHASE 2: ENTSPERREN ABLEHNEN (KLICK: NEIN)"
Write-Host "Wir versuchen den Schutz aufzuheben. Du verbietest es." -ForegroundColor Gray
Write-Host ">>> BITTE JETZT IM WINDOWS-FENSTER AUF 'NEIN' / 'ABBRECHEN' KLICKEN <<<" -ForegroundColor Red -BackgroundColor White

try {
    Start-Process pwsh -ArgumentList "-NoProfile", "-File", "$pwd/scripts/unlock-files.ps1" -Verb RunAs -Wait -ErrorAction Stop
    Write-Host "`nHinweis: Du hast 'JA' geklickt, wir wollten 'NEIN' testen." -ForegroundColor Gray
} catch {
    Write-Host "`n✅ ERFOLG: Du hast das Entsperren verweigert!" -ForegroundColor Green
}

Write-Host "`nAUDIT 2: Prüfe ob Dateien IMMER NOCH GESPERRT sind..." -ForegroundColor Yellow
Run-Audit "Locked"


# --- PHASE 3: UNLOCK (JA) ---
Show-Header "PHASE 3: ENTSPERREN ERLAUBEN (KLICK: JA)"
Write-Host "Jetzt erlauben wir es wirklich." -ForegroundColor Gray
Write-Host ">>> BITTE JETZT IM WINDOWS-FENSTER AUF 'JA' KLICKEN <<<" -ForegroundColor Red -BackgroundColor White

Start-Process pwsh -ArgumentList "-NoProfile", "-File", "$pwd/scripts/unlock-files.ps1" -Verb RunAs -Wait

Write-Host "`nAUDIT 3: Prüfe ob Dateien jetzt OFFEN sind..." -ForegroundColor Yellow
Run-Audit "Open"


# --- PHASE 4: LOCK (NEIN) ---
Show-Header "PHASE 4: SPERRE ABLEHNEN (KLICK: NEIN)"
Write-Host "Versuch einer erneuten Sperre. Du verbietest es." -ForegroundColor Gray
Write-Host ">>> BITTE JETZT IM WINDOWS-FENSTER AUF 'NEIN' / 'ABBRECHEN' KLICKEN <<<" -ForegroundColor Red -BackgroundColor White

try {
    Start-Process pwsh -ArgumentList "-NoProfile", "-File", "$pwd/scripts/lock-files.ps1", "-SkipProfile" -Verb RunAs -Wait -ErrorAction Stop
    Write-Host "`nHinweis: Du hast 'JA' geklickt, wir wollten 'NEIN' testen." -ForegroundColor Gray
} catch {
    Write-Host "`n✅ ERFOLG: Du hast das Sperren verweigert!" -ForegroundColor Green
}

Write-Host "`nAUDIT 4: Prüfe ob Dateien IMMER NOCH OFFEN sind..." -ForegroundColor Yellow
Run-Audit "Open"


Show-Header "DEMO BEENDET: EXAKT 4 ADMIN-ENTSCHEIDUNGEN (JA, NEIN, JA, NEIN)"
Write-Host "Beweisführung abgeschlossen: Ohne dein JA passiert hier gar nichts." -ForegroundColor Green

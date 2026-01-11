# MASTER E2E SECURITY & ANTI-GHOST AUDIT (Fail-Fast)
param(
    [switch] $NoElevate,
    [switch] $VerifyOnly,
    [string] $Expect = "All" # All, Locked, Open
)
Write-Host "DEBUG: E2E SCRIPT STARTED (Param Expect=$Expect, VerifyOnly=$VerifyOnly, NoElevate=$NoElevate)"

# --- 0. ADMIN-CHECK ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -and -not $NoElevate) {
    Write-Host "CRITICAL: E2E-Test erfordert Administrator-Rechte!" -ForegroundColor Red
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$baseFiles = @("package.json", "pyproject.toml", ".husky")

# Log File Setup
$global:AuditLogFile = "$PSScriptRoot\audit_debug.log"
"--- NEW AUDIT RUN $(Get-Date) ---" | Out-File $global:AuditLogFile -Append -Encoding utf8

function Log-Audit {
    param([string]$Msg)
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    "[$timestamp] $Msg" | Out-File $global:AuditLogFile -Append -Encoding utf8
    # Auch in Konsole für Live-Log
    Microsoft.PowerShell.Utility\Write-Host "[$timestamp] $Msg" -ForegroundColor Gray
}

# 1. Alle Dateien auflösen (rekursiv bei Ordnern wie .husky)
$files = @()
foreach ($f in $baseFiles) {
    if (Test-Path $f) {
        $item = Get-Item $f
        if ($item -is [System.IO.DirectoryInfo]) {
            $files += Get-ChildItem $f -File -Recurse | ForEach-Object { $_.FullName }
        } else {
            $files += $item.FullName
        }
    }
}

# --- 1. STEP RUNNER (STRICT) ---
function Run-Step {
    param(
        [string]$ActionName,
        [scriptblock]$Action,
        [switch]$ExpectedUnlocked,
        [string]$TargetFile
    )
    
    Log-Audit "START: $ActionName on $TargetFile (Unlocked=$ExpectedUnlocked)"

    # State Reset
    $error.Clear()
    $global:lastIdManualOverride = [int](Get-Random)
    $global:lastSeenErrorCount = 0

    $contentBefore = if ($TargetFile -and (Test-Path $TargetFile)) { 
        try { Get-Content $TargetFile -Raw -ErrorAction SilentlyContinue } catch { "" }
    } else { "" }
    # Reset State
    $script:shadowWarningShown = $false
    $global:AuditTargetFile = $TargetFile
    $global:AuditWarningTriggered = $false
    $global:SimulatedSecurityError = $null
    $global:AuditLastExitCode = $null
    $readErrorBefore = $false
    $contentBefore = if ($TargetFile -and (Test-Path $TargetFile)) { 
        try { Get-Content $TargetFile -Raw -ErrorAction Stop } catch { $readErrorBefore = $true; Log-Audit "READ ERROR BEFORE: $_"; "" }
    } else { "" }
    
    $failed = $false
    try {
        $ErrorActionPreference = "Continue" # Continue damit Stderr captured werden kann
        
        # Capture Output (Stdout + Stderr merged via 2>&1)
        # Wir wollen es im Log UND (optional) sehen? Nein, primär Log.
        $cmdOutput = & $Action 2>&1 | Out-String
        
        # Logge den KOMPLETTEN Output
        Log-Audit "OUTPUT from '$ActionName':"
        if ($cmdOutput) {
            $cmdOutput -split "`n" | ForEach-Object { Log-Audit "  > $_" }
        } else {
             Log-Audit "  (No Output)"
        }
        
        $global:AuditLastExitCode = $LASTEXITCODE
        Log-Audit "Action finished. ExitCode: $LASTEXITCODE"
        
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { 
            $failed = $true 
            if (-not $global:SimulatedSecurityError) {
                $global:SimulatedSecurityError = [PSCustomObject]@{
                    Exception = [PSCustomObject]@{ Message = "Native Command Failure for $TargetFile (ExitCode $LASTEXITCODE)" }
                }
            }
        }
    } catch {
        $failed = $true
        # Sicherstellen, dass der Fehler in $global:Error landet für den Hook
        $global:SimulatedSecurityError = $_
        Log-Audit "CATCH: $($_.Exception.Message)"
    }

    # Fallback: Wenn Failed aber kein Fehlerobjekt (z.B. Native Git Failure)
    # Und sicherstellen, dass wir es wirklich setzen!
    if ($failed -and -not $global:SimulatedSecurityError) {
         $global:SimulatedSecurityError = [PSCustomObject]@{
             Exception = [PSCustomObject]@{ Message = "Generischer Fehler für $TargetFile (ExitCode $global:AuditLastExitCode)" }
         }
    }
    
    # Trigger Hook (explicitly invoke prompt with current state)
    if (Get-Command prompt -ErrorAction SilentlyContinue) { 
        prompt | Out-Null 
    }
    
    $warningTriggered = $global:AuditWarningTriggered
    $readErrorAfter = $false
    $contentAfter = if ($TargetFile -and (Test-Path $TargetFile)) { 
        try { Get-Content $TargetFile -Raw -ErrorAction Stop } catch { $readErrorAfter = $true; Log-Audit "READ ERROR AFTER: $_"; "" }
    } else { "" }

    # Modified Logic: Only if NO Read Errors occurred
    if ($readErrorBefore -or $readErrorAfter) {
        $wasActuallyModified = $false
        Log-Audit "SKIPPING Modified Check due to Read Errors (Before=$readErrorBefore, After=$readErrorAfter)"
    } else {
        $wasActuallyModified = ($contentBefore -ne $contentAfter)
    }

    $errorDetail = if ($global:SimulatedSecurityError) { $global:SimulatedSecurityError.Exception.Message } else { "Keine Details (Failed=$failed)" }
    
    if ($ExpectedUnlocked) {
        if ($wasActuallyModified -or -not $failed) {
             Log-Audit "SUCCESS: Allowed ($ActionName)"
             return $true
        } else {
             Log-Audit "FAIL: Unexpected Block ($ActionName) - $errorDetail"
             Microsoft.PowerShell.Utility\Write-Host "  ❌ FEHLER: Unerwartet blockiert ($TargetFile)! Fehler: $errorDetail" -ForegroundColor Red
             return $false
        }
    } else {
        if ($wasActuallyModified) {
            Log-Audit "CRITICAL: File Modified ($ActionName)"
            Log-Audit "  Before Len: $($contentBefore.Length)"
            Log-Audit "  After  Len: $($contentAfter.Length)"
            if ($contentBefore -eq $null) { Log-Audit "  Before is NULL" }
            if ($contentAfter -eq $null) { Log-Audit "  After is NULL" }
            
            Microsoft.PowerShell.Utility\Write-Host "  ❌ SICHERHEITSLÜCKE: Datei $TargetFile manipuliert!" -ForegroundColor White -BackgroundColor Red
            return $false
        }
        
        if (-not $warningTriggered) {
             Log-Audit "FAIL-FAST: No Warning ($ActionName)"
             Log-Audit "  ErrDetails: $errorDetail"
             Log-Audit "  Pattern: $(Split-Path $TargetFile -Leaf)"
             
             Microsoft.PowerShell.Utility\Write-Host "  ❌ FAIL-FAST: Keine Warnung für $TargetFile" -ForegroundColor Red
             return $false
        }
        Log-Audit "SUCCESS: Blocked + Warned ($ActionName)"
        return $true
    }
}

# --- 2. AUDIT EXECUTION ---
try {
    # 1. Dateiliste bereinigen (Duplikate entfernen)
    $files = $files | Select-Object -Unique

    if (Test-Path "./scripts/warning-hook.ps1") {
        # Wichtig: Pattern muss auf LEAF-Namen basieren für Shell-Kompatibilität
        $patternList = $files | ForEach-Object { Split-Path $_ -Leaf | ForEach-Object { [Regex]::Escape($_) } }
        $global:ProtectedFilesPattern = ($patternList | Select-Object -Unique) -join '|'
        . ./scripts/warning-hook.ps1
    }

    if (-not $VerifyOnly) {
        Microsoft.PowerShell.Utility\Write-Host ">>> PHASE 1: LOCKING <<<" -ForegroundColor Yellow
        . ./scripts/lock-files.ps1 -SkipProfile | Out-Null
    }

    if ($Expect -eq "All" -or $Expect -eq "Locked") {
        foreach ($f in $files) {
            if (Test-Path $f) {
                # ACL Debug
                try {
                    $acl = Get-Acl $f
                    Log-Audit "DEBUG ACL $f :: Owner=$($acl.Owner) Access=$($acl.AccessToString)"
                } catch { Log-Audit "DEBUG ACL FAIL: $_" }

                if (-not (Run-Step "Write Check" { "hack" | Out-File $f -Force } -TargetFile $f)) { exit 1 }
                if (-not (Run-Step "Delete Check" { Remove-Item $f -Force } -TargetFile $f)) { exit 1 }
                
                # Restore Check kann tricky sein bei untracked files, aber wir testen nur tracked files
                if (-not (Run-Step "Restore Check" { git restore -s HEAD $f 2>&1 | Out-Null } -TargetFile $f)) { exit 1 }
            }
        }
    }

    if ($Expect -eq "All" -or $Expect -eq "Open") {
        foreach ($f in $files) {
            if (Test-Path $f) {
                # Read Check: Versuche Inhalt zu lesen statt git add (weniger Side-Effects)
                if (-not (Run-Step "Read Check" { Get-Content $f | Select-Object -First 1 } -ExpectedUnlocked -TargetFile $f)) { exit 1 }
            }
        }
    }

    Microsoft.PowerShell.Utility\Write-Host "`nAUDIT BESTANDEN! ✅" -ForegroundColor Green
    exit 0
} finally {
    if (-not $VerifyOnly) { . ./scripts/unlock-files.ps1 -Targets $baseFiles | Out-Null }
}
exit 0

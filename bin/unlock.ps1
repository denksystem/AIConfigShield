# FILE-LOCK-TOOL: UNLOCK
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string[]]$Targets,
    [switch] $SkipProfile
)

$global:UnlockLogFile = Join-Path (Get-Location).Path "unlock_output.log"

function Log-Unlock {
    param([string]$Msg)
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    "[$timestamp] $Msg" | Out-File $global:UnlockLogFile -Append -Encoding utf8
}

Log-Unlock "=== UNLOCK START ==="

# --- 0. ADMIN-CHECK mit Auto-Elevation ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $workDir = (Get-Location).Path
    
    $targetArgs = ($Targets | ForEach-Object { "`"$_`"" }) -join " "
    $skipArg = if ($SkipProfile) { " -SkipProfile" } else { "" }
    $cmd = "Set-Location '$workDir'; & '$scriptPath' $targetArgs$skipArg; exit `$LASTEXITCODE"
    
    $proc = Start-Process pwsh -ArgumentList "-ExecutionPolicy Bypass", "-Command", $cmd -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

# --- 1. ENTSPERRUNG ---
foreach ($targetRaw in $Targets) {
    if (-not (Test-Path $targetRaw)) { 
        Log-Unlock "WARN: Target not found: $targetRaw"
        continue 
    }
    $item = Get-Item $targetRaw -Force
    $fullPath = $item.FullName
    $isDir = $item.PSIsContainer
    $fileName = Split-Path $fullPath -Leaf

    Log-Unlock "--- Processing: $fullPath (Dir=$isDir) ---"
    Write-Host "🔓 Entsperre $fileName (Dir=$isDir)..." -ForegroundColor Cyan

    $takeownArgs = @("/F", "$fullPath", "/A")
    if ($isDir) { $takeownArgs += "/R"; $takeownArgs += "/D"; $takeownArgs += "Y" }

    # A. Besitz erzwingen (Admin)
    Log-Unlock "STEP: takeown"
    $out = & takeown $takeownArgs 2>&1 | Out-String
    Log-Unlock "OUTPUT: $out"

    # B. Integrität zurück auf Medium setzen
    $intArgs = @("$fullPath", "/setintegritylevel", "M", "/c")
    if ($isDir) { $intArgs += "/T" }
    Log-Unlock "STEP: setintegritylevel M"
    $out = & icacls $intArgs 2>&1 | Out-String
    Log-Unlock "OUTPUT: $out"

    # C. ACLs komplett zurücksetzen
    $resetArgs = @("$fullPath", "/reset", "/c")
    if ($isDir) { $resetArgs += "/T" }
    Log-Unlock "STEP: reset"
    $out = & icacls $resetArgs 2>&1 | Out-String
    Log-Unlock "OUTPUT: $out"

    # D. Besitzer zurück an User
    $ownArgs = @("$fullPath", "/setowner", "${env:USERNAME}", "/c")
    if ($isDir) { $ownArgs += "/T" }
    Log-Unlock "STEP: setowner ${env:USERNAME}"
    $out = & icacls $ownArgs 2>&1 | Out-String
    Log-Unlock "OUTPUT: $out"

    Log-Unlock "--- DONE: $fullPath ---"
    Write-Host "✅ $fileName (und Inhalte) entsperrt." -ForegroundColor Green
}

Log-Unlock "=== UNLOCK END ==="

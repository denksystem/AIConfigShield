# FILE-LOCK-TOOL: LOCK
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string[]]$Targets,
    [switch] $SkipProfile
)

$global:LockLogFile = Join-Path (Get-Location).Path "lock_output.log"

function Log-Lock {
    param([string]$Msg)
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    "[$timestamp] $Msg" | Out-File $global:LockLogFile -Append -Encoding utf8
}

Log-Lock "=== LOCK START ==="
Log-Lock "Args: $($PSBoundParameters | Out-String)"

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

# --- 1. PRE-RESET: Entsperren für Enumeration ---
Log-Lock "PRE-RESET: Unlocking targets for enumeration..."
foreach ($targetRaw in $Targets) {
    if (-not (Test-Path $targetRaw)) { 
        Log-Lock "WARN: Target not found: $targetRaw"
        continue 
    }
    $item = Get-Item $targetRaw -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { continue }
    
    Log-Lock "PRE-RESET: $($item.FullName)"
    if ($item.PSIsContainer) {
        & icacls "$($item.FullName)" /reset /T /C 2>&1 | Out-Null
    } else {
        & icacls "$($item.FullName)" /reset /C 2>&1 | Out-Null
    }
}
Log-Lock "PRE-RESET: Done"

# --- 2. SCHUTZ ANWENDEN ---
$allFiles = @()
foreach ($targetRaw in $Targets) {
    if (-not (Test-Path $targetRaw)) { continue }
    $item = Get-Item $targetRaw -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { continue }
    
    if ($item -is [System.IO.DirectoryInfo]) {
        $allFiles += $item.FullName
        try {
            $children = Get-ChildItem $item.FullName -Recurse -Force -ErrorAction Stop
            $allFiles += ($children | ForEach-Object { $_.FullName })
        } catch {
            Log-Lock "WARN: Cannot enumerate $($item.FullName): $_"
        }
    } else {
        $allFiles += $item.FullName
    }
}

Log-Lock "Expanded targets to $($allFiles.Count) files"

foreach ($fullPath in $allFiles) {
    if (-not (Test-Path $fullPath)) { continue }
    $item = Get-Item $fullPath -Force
    $isDir = ($item -is [System.IO.DirectoryInfo])

    Log-Lock "--- Processing: $fullPath (Dir=$isDir) ---"
    Write-Host "🛡️  Sperre $(Split-Path $fullPath -Leaf)..." -ForegroundColor Cyan

    # A. Besitz erzwingen (takeown)
    Log-Lock "STEP: takeown"
    $out = & takeown /F "$fullPath" /A 2>&1 | Out-String
    Log-Lock "OUTPUT: $out"

    # B. Vererbung kappen und aufräumen
    Log-Lock "STEP: icacls reset"
    $out = & icacls "$fullPath" /reset /c 2>&1 | Out-String
    Log-Lock "OUTPUT: $out"
    
    Log-Lock "STEP: icacls inheritance:r"
    $out = & icacls "$fullPath" /inheritance:r /c 2>&1 | Out-String
    Log-Lock "OUTPUT: $out"

    # C. Lesezugriff erlauben
    Log-Lock "STEP: icacls grant RX"
    $out = & icacls "$fullPath" /grant "${env:USERNAME}:(RX)" /c 2>&1 | Out-String
    Log-Lock "OUTPUT: $out"

    Log-Lock "STEP: icacls grant Admin+System"
    $out = & icacls "$fullPath" /grant "*S-1-5-32-544:(F)" /grant "SYSTEM:(F)" /c 2>&1 | Out-String
    Log-Lock "OUTPUT: $out"

    Log-Lock "--- DONE: $fullPath ---"
    Write-Host "✅ GESPERRT: $(Split-Path $fullPath -Leaf)" -ForegroundColor Green
}

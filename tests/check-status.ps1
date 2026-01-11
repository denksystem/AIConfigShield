param(
    [string[]] $Files = @(
        "package.json",
        "pyproject.toml",
        ".husky\pre-commit",
        ".husky\pre-push"
    )
)

$allLocked = $true
$allOpen = $true

foreach ($f in $Files) {
    if (Test-Path $f) {
        try {
            # Versuch, die Datei zu öffnen (Lesen+Schreiben)
            $stream = [System.IO.File]::Open(
                $f,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite
            )
            $stream.Close()
            Write-Host "OPEN:   $f" -ForegroundColor Green
            $allLocked = $false
        } catch {
            Write-Host "LOCKED: $f" -ForegroundColor Red
            $allOpen = $false
        }
    }
}

if ($allLocked) {
    exit 10
} # Code 10 = ALL LOCKED
if ($allOpen) {
    exit 20
} # Code 20 = ALL OPEN
exit 30 # Code 30 = MIXED

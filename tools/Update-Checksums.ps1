$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path "$PSScriptRoot\.."
Push-Location $RepoRoot

try {
    $Files = git ls-files |
        Where-Object {
            $_ -ne "CHECKSUMS.sha256" -and
            $_ -notmatch "^\.git/" -and
            $_ -notmatch "^github-security-audit-" -and
            $_ -notmatch "\.zip$"
        } |
        Sort-Object

    $Lines = foreach ($File in $Files) {
        if (Test-Path $File -PathType Leaf) {
            $Hash = Get-FileHash -Path $File -Algorithm SHA256
            "$($Hash.Hash.ToLower())  $File"
        }
    }

    $Lines | Set-Content -Path "CHECKSUMS.sha256" -Encoding utf8
    Write-Host "CHECKSUMS.sha256 refreshed."
}
finally {
    Pop-Location
}

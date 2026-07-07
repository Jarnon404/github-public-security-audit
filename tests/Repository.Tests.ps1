BeforeAll {
    $RepoRoot = Resolve-Path "$PSScriptRoot/.."
}

Describe "Repository structure" {
    It "Has a README" {
        Test-Path (Join-Path $RepoRoot "README.md") | Should -BeTrue
    }

    It "Has a LICENSE file" {
        Test-Path (Join-Path $RepoRoot "LICENSE") | Should -BeTrue
    }

    It "Has documentation folder" {
        Test-Path (Join-Path $RepoRoot "docs") | Should -BeTrue
    }

    It "Has script folder" {
        Test-Path (Join-Path $RepoRoot "scripts") | Should -BeTrue
    }
}

Describe "PowerShell scripts" {
    $Scripts = Get-ChildItem -Path (Join-Path $RepoRoot "scripts") -Filter "*.ps1" -Recurse

    It "Contains PowerShell scripts" {
        $Scripts.Count | Should -BeGreaterThan 0
    }

    foreach ($Script in $Scripts) {
        It "PowerShell script <Name> parses successfully" -TestCases @{ Name = $Script.Name } {
            param([string]$Name)

            $ScriptPath = Join-Path $RepoRoot "scripts/$Name"
            $Errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$Errors) | Out-Null
            $Errors.Count | Should -Be 0
        }

        It "PowerShell script <Name> has comments" -TestCases @{ Name = $Script.Name } {
            param([string]$Name)

            $ScriptPath = Join-Path $RepoRoot "scripts/$Name"
            (Get-Content $ScriptPath -Raw) | Should -Match "#"
        }
    }
}

Describe "Public safety" {
    It "Does not include generated audit output folders" {
        $Generated = Get-ChildItem -Path $RepoRoot -Directory -Recurse |
            Where-Object { $_.Name -match '^github-security-audit-\d{8}-\d{6}$' }

        $Generated.Count | Should -Be 0
    }

    It "Requires explicit owner and repository parameters" {
        $ScriptPath = Join-Path $RepoRoot "scripts/Invoke-GitHubPublicSecurityAudit.ps1"
        $Content = Get-Content $ScriptPath -Raw

        $Content | Should -Match '\[Parameter\(Mandatory\s*=\s*\$true\)\]\s*\r?\n\s*\[ValidateNotNullOrEmpty\(\)\]\s*\r?\n\s*\[string\]\$Owner'
        $Content | Should -Match '\[Parameter\(Mandatory\s*=\s*\$true\)\]\s*\r?\n\s*\[ValidateNotNullOrEmpty\(\)\]\s*\r?\n\s*\[string\[\]\]\$Repositories'
    }
}

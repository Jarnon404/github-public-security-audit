$ErrorActionPreference = "Stop"

BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

Describe "Repository structure" {
    It "Has a README" {
        Test-Path (Join-Path $script:RepositoryRoot "README.md") | Should -BeTrue
    }

    It "Has a LICENSE file" {
        Test-Path (Join-Path $script:RepositoryRoot "LICENSE") | Should -BeTrue
    }

    It "Has documentation folder" {
        Test-Path (Join-Path $script:RepositoryRoot "docs") | Should -BeTrue
    }

    It "Has script folder" {
        Test-Path (Join-Path $script:RepositoryRoot "scripts") | Should -BeTrue
    }
}

Describe "PowerShell scripts" {
    It "Contains at least one PowerShell script" {
        $ScriptFiles = Get-ChildItem `
            -Path (Join-Path $script:RepositoryRoot "scripts") `
            -Filter "*.ps1" `
            -Recurse `
            -File

        $ScriptFiles.Count | Should -BeGreaterThan 0
    }

    It "PowerShell scripts parse successfully" {
        $ScriptFiles = Get-ChildItem `
            -Path (Join-Path $script:RepositoryRoot "scripts") `
            -Filter "*.ps1" `
            -Recurse `
            -File

        foreach ($ScriptFile in $ScriptFiles) {
            $Errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $ScriptFile.FullName -Raw),
                [ref]$Errors
            )

            $Errors | Should -BeNullOrEmpty
        }
    }
}

Describe "Repository metadata" {
    It "Has VERSION.txt" {
        Test-Path (Join-Path $script:RepositoryRoot "VERSION.txt") | Should -BeTrue
    }

    It "Has CHECKSUMS.sha256" {
        Test-Path (Join-Path $script:RepositoryRoot "CHECKSUMS.sha256") | Should -BeTrue
    }

    It "Has SECURITY.md" {
        Test-Path (Join-Path $script:RepositoryRoot "SECURITY.md") | Should -BeTrue
    }
}

# GitHub Public Security Audit

[![PSScriptAnalyzer](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/psscriptanalyzer.yml/badge.svg)](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/psscriptanalyzer.yml)
[![Pester Tests](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/pester.yml/badge.svg)](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/pester.yml)
[![Secret Scan](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/gitleaks.yml)
[![Public Safety Check](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/public-safety-check.yml/badge.svg)](https://github.com/Jarnon404/github-public-security-audit/actions/workflows/public-safety-check.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

PowerShell tool for auditing public GitHub repositories and GitHub Pages sites.

The tool collects repository metadata, branch protection state, workflow status, release information, expected repository files, static content findings, and basic GitHub Pages live checks. It exports a clean CSV, TXT and interactive HTML report.

## Features

- Audits multiple repositories under one GitHub owner.
- Checks repository visibility, wiki/project flags, releases and open pull requests.
- Checks GitHub Pages source, HTTPS enforcement and live HTTP status.
- Checks branch protection, required status checks, admin enforcement, force-push and deletion settings.
- Scans selected text files for common public-safety risks.
- Generates an interactive HTML report with repository buttons, status filters, findings filter, search and sortable columns.
- Removes temporary offline clone data by default.
- Supports `-KeepOfflineData` for debugging.

## Requirements

- PowerShell 7+
- Git
- GitHub CLI
- Authenticated GitHub CLI session:

```powershell
gh auth login
```

## Quick start

```powershell
cd C:\GitHub\SecurityAudit

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-GitHubPublicSecurityAudit.ps1 `
  -Owner "YourGitHubUserOrOrg" `
  -Repositories @(
      "repo-one",
      "repo-two",
      "repo-three"
  )
```

Use a custom output path:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-GitHubPublicSecurityAudit.ps1 `
  -Owner "YourGitHubUserOrOrg" `
  -Repositories @("repo-one","repo-two") `
  -OutputPath "C:\GitHub\SecurityAudit"
```

Keep temporary cloned repositories for troubleshooting:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-GitHubPublicSecurityAudit.ps1 `
  -Owner "YourGitHubUserOrOrg" `
  -Repositories @("repo-one","repo-two") `
  -KeepOfflineData
```

## Output

Each audit run creates a timestamped folder:

```text
github-security-audit-yyyyMMdd-HHmmss
```

Normal output contains only:

```text
github-security-audit-summary.csv
github-security-audit-summary.html
github-security-audit-summary.txt
```

Temporary offline clone data is removed unless `-KeepOfflineData` is used.

## Public-safe design

The script does not include hardcoded customer names, tenant identifiers, internal hostnames, private IP addresses, credentials or environment-specific data.

The default parameters are intentionally generic. You must explicitly provide the GitHub owner and repository names when running the tool.

## Checks performed

The audit includes these areas:

- Repository metadata
- GitHub Pages configuration and live status
- Branch protection
- GitHub Actions workflow definitions
- Recent workflow runs
- Open pull requests
- Releases
- Expected repository files
- SECURITY.md and CODEOWNERS presence
- README public-safety wording
- Static content checks for obvious sensitive-data patterns

## Limitations

This is a practical public repository hygiene audit, not a full security assessment. It does not replace GitHub Advanced Security, manual code review, secret rotation procedures or organization-level policy enforcement.

Static checks are intentionally conservative. Some findings may be informational or false positives, especially in repositories that intentionally discuss security, tenant, credential or customer-safety topics.

## Public safety note

This repository is intended to contain only public-safe material. Do not commit customer-specific data, tenant identifiers, credentials, generated audit reports, internal hostnames, private IP addresses or environment-specific exports.

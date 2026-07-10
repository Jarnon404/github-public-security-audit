param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Repositories,

    [ValidateRange(1, 500)]
    [int]$MaxInlineFindings = 25,

    [string]$OutputPath = (Get-Location).Path,

    [switch]$KeepOfflineData
)

$ErrorActionPreference = "Stop"

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutDir = Join-Path $OutputPath "github-security-audit-$Timestamp"
New-Item -ItemType Directory -Force $OutDir | Out-Null

$Summary = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Repository,
        [string]$Area,
        [string]$Check,
        [string]$Status,
        [string]$Detail
    )

    $Summary.Add([pscustomobject]@{
        Repository = $Repository
        Area       = $Area
        Check      = $Check
        Status     = $Status
        Detail     = $Detail
    })
}

function Invoke-GhJson {
    param([string]$ApiPath)

    try {
        return gh api $ApiPath | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-CommandExists "gh")) {
    throw "GitHub CLI 'gh' not found."
}

if (-not (Test-CommandExists "git")) {
    throw "Git 'git' not found."
}

$Auth = gh auth status 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not logged in. Run: gh auth login"
}

foreach ($Repo in $Repositories) {
    $FullName = "$Owner/$Repo"
    Write-Host "Auditing $FullName..." -ForegroundColor Cyan

    $RepoDir = Join-Path $OutDir $Repo
    New-Item -ItemType Directory -Force $RepoDir | Out-Null

    # Repository metadata
    $RepoInfo = Invoke-GhJson "/repos/$FullName"

    if (-not $RepoInfo) {
        Add-Result $Repo "Repository" "Repository accessible" "FAIL" "Could not read repository metadata."
        continue
    }

    Add-Result $Repo "Repository" "Repository accessible" "PASS" "Repository metadata readable."
    Add-Result $Repo "Repository" "Visibility" (($RepoInfo.private -eq $false) ? "PASS" : "WARN") "Private=$($RepoInfo.private)"
    Add-Result $Repo "Repository" "Default branch" "INFO" "Default branch: $($RepoInfo.default_branch)"
    Add-Result $Repo "Repository" "Archived" (($RepoInfo.archived -eq $false) ? "PASS" : "WARN") "Archived=$($RepoInfo.archived)"
    Add-Result $Repo "Repository" "Fork" (($RepoInfo.fork -eq $false) ? "PASS" : "INFO") "Fork=$($RepoInfo.fork)"
    Add-Result $Repo "Repository" "Has wiki" (($RepoInfo.has_wiki -eq $false) ? "PASS" : "WARN") "Has wiki=$($RepoInfo.has_wiki)"
    Add-Result $Repo "Repository" "Has projects" "INFO" "Has projects=$($RepoInfo.has_projects)"
    Add-Result $Repo "Repository" "Open issues count" "INFO" "Open issues=$($RepoInfo.open_issues_count)"

    # Pages
    $Pages = Invoke-GhJson "/repos/$FullName/pages"

    if ($Pages) {
        Add-Result $Repo "GitHub Pages" "Pages configured" "PASS" "URL=$($Pages.html_url)"
        $PagesStatusResult = if ($Pages.status -eq "built") { "PASS" } elseif ([string]::IsNullOrWhiteSpace([string]$Pages.status)) { "INFO" } else { "WARN" }
        Add-Result $Repo "GitHub Pages" "Pages status" $PagesStatusResult "Status=$($Pages.status)"
        Add-Result $Repo "GitHub Pages" "HTTPS enforced" (($Pages.https_enforced -eq $true) ? "PASS" : "WARN") "https_enforced=$($Pages.https_enforced)"
        Add-Result $Repo "GitHub Pages" "Source" "INFO" "Branch=$($Pages.source.branch), Path=$($Pages.source.path)"
    }
    else {
        Add-Result $Repo "GitHub Pages" "Pages configured" "INFO" "Pages not configured or not readable."
    }

    # Branch protection
    $DefaultBranch = $RepoInfo.default_branch
    $Protection = Invoke-GhJson "/repos/$FullName/branches/$DefaultBranch/protection"

    if ($Protection) {
        Add-Result $Repo "Branch protection" "Default branch protection" "PASS" "Protection configured for $DefaultBranch."

        if ($Protection.required_status_checks) {
            Add-Result $Repo "Branch protection" "Required status checks" "PASS" "Required status checks configured."
        }
        else {
            Add-Result $Repo "Branch protection" "Required status checks" "WARN" "No required status checks detected."
        }

        if ($Protection.enforce_admins.enabled -eq $true) {
            Add-Result $Repo "Branch protection" "Enforce admins" "PASS" "Admins included."
        }
        else {
            Add-Result $Repo "Branch protection" "Enforce admins" "WARN" "Admins may bypass protection."
        }
    }
    else {
        Add-Result $Repo "Branch protection" "Default branch protection" "WARN" "No branch protection detected or not readable."
    }

    # Workflows
    $Workflows = Invoke-GhJson "/repos/$FullName/actions/workflows"

    if ($Workflows -and $Workflows.workflows) {
        foreach ($Workflow in $Workflows.workflows) {
            $State = if ($Workflow.state -eq "active") { "PASS" } else { "WARN" }
            Add-Result $Repo "Actions" "Workflow: $($Workflow.name)" $State "State=$($Workflow.state), Path=$($Workflow.path)"
        }
    }
    else {
        Add-Result $Repo "Actions" "Workflows" "WARN" "No workflows found or not readable."
    }

    # Recent workflow runs
    $Runs = Invoke-GhJson "/repos/$FullName/actions/runs?per_page=20"

    if ($Runs -and $Runs.workflow_runs) {
        $FailedRuns = @($Runs.workflow_runs | Where-Object { $_.conclusion -eq "failure" })
        $PendingRuns = @($Runs.workflow_runs | Where-Object { $_.status -ne "completed" })

        if ($FailedRuns.Count -eq 0) {
            Add-Result $Repo "Actions" "Recent workflow failures" "PASS" "No failures in latest 20 workflow runs."
        }
        else {
            Add-Result $Repo "Actions" "Recent workflow failures" "WARN" "$($FailedRuns.Count) failed run(s) in latest 20 workflow runs."
        }

        if ($PendingRuns.Count -eq 0) {
            Add-Result $Repo "Actions" "Pending workflow runs" "PASS" "No pending runs in latest 20 workflow runs."
        }
        else {
            Add-Result $Repo "Actions" "Pending workflow runs" "INFO" "$($PendingRuns.Count) pending run(s)."
        }
    }
    else {
        Add-Result $Repo "Actions" "Recent workflow runs" "INFO" "No recent workflow runs found."
    }

    # Open pull requests
    try {
        $Prs = gh pr list --repo $FullName --json number,title,state 2>$null | ConvertFrom-Json
        if ($Prs.Count -eq 0) {
            Add-Result $Repo "Pull requests" "Open PRs" "PASS" "No open pull requests."
        }
        else {
            Add-Result $Repo "Pull requests" "Open PRs" "WARN" "$($Prs.Count) open pull request(s)."
        }
    }
    catch {
        Add-Result $Repo "Pull requests" "Open PRs" "INFO" "Could not read pull requests."
    }

    # Releases
    $Releases = Invoke-GhJson "/repos/$FullName/releases?per_page=10"

    if ($Releases -and $Releases.Count -gt 0) {
        $LatestRelease = $Releases | Select-Object -First 1
        Add-Result $Repo "Releases" "Latest release" "PASS" "$($LatestRelease.tag_name) - $($LatestRelease.name)"
    }
    else {
        Add-Result $Repo "Releases" "Latest release" "WARN" "No releases found."
    }

    # Clone shallow working copy for static checks
    $ClonePath = Join-Path $RepoDir "repo"

    git clone --depth 1 "https://github.com/$FullName.git" $ClonePath *> $null

    # File presence
    $ExpectedFiles = @(
        "README.md",
        "LICENSE",
        "VERSION.txt",
        "CHECKSUMS.sha256",
        ".gitignore",
        ".github/workflows"
    )

    foreach ($File in $ExpectedFiles) {
        $Target = Join-Path $ClonePath $File
        if (Test-Path $Target) {
            Add-Result $Repo "Repository files" $File "PASS" "Found."
        }
        else {
            Add-Result $Repo "Repository files" $File "WARN" "Missing."
        }
    }

    # SECURITY.md
    $SecurityPolicyPaths = @(
        "SECURITY.md",
        ".github/SECURITY.md",
        "docs/SECURITY.md"
    )

    $HasSecurityPolicy = $false
    foreach ($SecurityPath in $SecurityPolicyPaths) {
        if (Test-Path (Join-Path $ClonePath $SecurityPath)) {
            $HasSecurityPolicy = $true
        }
    }

    Add-Result $Repo "Repository files" "SECURITY.md" ($HasSecurityPolicy ? "PASS" : "WARN") (($HasSecurityPolicy) ? "Security policy found." : "Security policy missing.")

    # CODEOWNERS
    $CodeownersPaths = @(
        ".github/CODEOWNERS",
        "CODEOWNERS",
        "docs/CODEOWNERS"
    )

    $HasCodeowners = $false
    foreach ($CodeownersPath in $CodeownersPaths) {
        if (Test-Path (Join-Path $ClonePath $CodeownersPath)) {
            $HasCodeowners = $true
        }
    }

    Add-Result $Repo "Repository files" "CODEOWNERS" ($HasCodeowners ? "PASS" : "WARN") (($HasCodeowners) ? "CODEOWNERS found." : "CODEOWNERS missing.")

    # README badge and safety notes
    $ReadmePath = Join-Path $ClonePath "README.md"
    if (Test-Path $ReadmePath) {
        $Readme = Get-Content $ReadmePath -Raw

        Add-Result $Repo "README" "Has badges" (($Readme -match "badge\.svg|shields\.io") ? "PASS" : "WARN") "Badge reference check."
        Add-Result $Repo "README" "Mentions public-safe/sanitized" (($Readme -match "(?i)public-safe|sanitized|sanitised") ? "PASS" : "WARN") "Public-safe wording check."
        Add-Result $Repo "README" "Mentions generated output exclusion" (($Readme -match "(?i)generated.*(excluded|outside|not commit|not committed)|output.*excluded") ? "PASS" : "INFO") "Generated output wording check."
    }

    # Static content checks
    $TextFiles = Get-ChildItem -Path $ClonePath -Recurse -File |
        Where-Object {
            $_.FullName -notmatch "\\.git\\" -and
            $_.Extension -match "\.(ps1|psm1|psd1|sh|bat|cmd|md|html|css|js|json|yml|yaml|txt|gitignore|gitattributes|editorconfig)$"
        }

    $Patterns = [ordered]@{
        "Private IPv4 address" = "\b(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)\d{1,3}\.\d{1,3}\b"
        "Email address"        = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
        "Possible secret"      = "(?i)(password|passwd|pwd|secret|token|apikey|api_key|client_secret)\s*[:=]\s*['""]?[^'""]+"
        "HTTP reference"       = "http://"
        "Internal domain"      = "(?i)\b[a-z0-9-]+\.(local|lan|corp|internal)\b"
        "Customer-looking term" = "(?i)(customer|tenant|client|domain controller name|server name|production server)"
    }

    foreach ($Name in $Patterns.Keys) {
        $Hits = New-Object System.Collections.Generic.List[string]

        foreach ($File in $TextFiles) {
            $Matches = Select-String -Path $File.FullName -Pattern $Patterns[$Name] -AllMatches -ErrorAction SilentlyContinue
            foreach ($Match in $Matches) {
                $Relative = $File.FullName.Substring($ClonePath.Length + 1)
                $LineText = $Match.Line.Trim()

                # Known safe GitHub Actions references.
                if ($Name -eq "Possible secret") {
                    if ($LineText -match '^\s*id-token:\s*write\s*$') {
                        continue
                    }

                    if ($LineText -match 'GITHUB_TOKEN:\s*\$\{\{\s*secrets\.GITHUB_TOKEN\s*\}\}') {
                        continue
                    }
                }

                $Hits.Add("${Relative}:$($Match.LineNumber): $LineText")
            }
        }

        if ($Hits.Count -eq 0) {
            Add-Result $Repo "Static scan" $Name "PASS" "No matches."
        }
        else {
            $StaticStatus = if ($Name -eq "Customer-looking term") { "INFO" } else { "WARN" }

            $InlineHits = @($Hits | Select-Object -First $MaxInlineFindings)
            $MoreText = if ($Hits.Count -gt $MaxInlineFindings) {
                " ... and $($Hits.Count - $MaxInlineFindings) more match(es)"
            }
            else {
                ""
            }

            $InlineDetail = "$($Hits.Count) match(es): " + (($InlineHits -join " | ") + $MoreText)

            Add-Result $Repo "Static scan" $Name $StaticStatus $InlineDetail
        }
    }

    # GitHub Pages live check
    if ($Pages -and $Pages.html_url) {
        try {
            $Response = Invoke-WebRequest $Pages.html_url -UseBasicParsing -MaximumRedirection 5
            Add-Result $Repo "Live site" "HTTP status" (($Response.StatusCode -eq 200) ? "PASS" : "WARN") "StatusCode=$($Response.StatusCode)"

            $Headers = $Response.Headers

            foreach ($HeaderName in @(
                "Strict-Transport-Security",
                "Content-Security-Policy",
                "X-Content-Type-Options",
                "Referrer-Policy",
                "X-Frame-Options"
            )) {
                if ($Headers[$HeaderName]) {
                    Add-Result $Repo "Live site headers" $HeaderName "PASS" "$($Headers[$HeaderName])"
                }
                else {
                    Add-Result $Repo "Live site headers" $HeaderName "INFO" "Header not present."
                }
            }

            $LiveContent = $Response.Content
            Add-Result $Repo "Live site" "Mixed content check" (($LiveContent -match "http://") ? "WARN" : "PASS") "Search for http:// in live HTML."
        }
        catch {
            Add-Result $Repo "Live site" "HTTP status" "WARN" $_.Exception.Message
        }
    }
}

# Apply known-safe finding downgrades.
# Added in v1.1.0 to reduce false positives from sanitized documentation examples.
$KnownSafeFindingRules = @(
    [pscustomobject]@{
        RepositoryPattern = ".*"
        CheckPattern      = "Email address"
        DetailPattern     = "admin\.user@example\.com|example\.com"
        Reason            = "Known-safe sanitized example email/domain."
    },
    [pscustomobject]@{
        RepositoryPattern = ".*"
        CheckPattern      = "Internal domain"
        DetailPattern     = "contoso\.local|DC01\.contoso\.local"
        Reason            = "Known-safe sanitized example internal domain."
    },
    [pscustomobject]@{
        RepositoryPattern = "github-public-security-audit"
        CheckPattern      = "Possible secret"
        DetailPattern     = "secrets\\.GITHUB_TOKEN|GITHUB_TOKEN|id-token|LineText -match"
        Reason            = "GitHub Actions token permission reference, not a secret value."
    },
    [pscustomobject]@{
        RepositoryPattern = "github-public-security-audit"
        CheckPattern      = "HTTP reference"
        DetailPattern     = "http://|Search for http://"
        Reason            = "Audit tool self-reference for detecting HTTP links."
    }
)

$ReportSummary = foreach ($Finding in $Summary) {
    $RepositoryValue = [string]$Finding.Repository
    $AreaValue       = [string]$Finding.Area
    $CheckValue      = [string]$Finding.Check
    $StatusValue     = [string]$Finding.Status
    $DetailValue     = [string]$Finding.Detail

    if ($StatusValue -eq "WARN") {
        foreach ($Rule in $KnownSafeFindingRules) {
            $IsKnownSafe =
                ($RepositoryValue -match $Rule.RepositoryPattern) -and
                ($CheckValue -match $Rule.CheckPattern) -and
                ($DetailValue -match $Rule.DetailPattern)

            if ($IsKnownSafe) {
                $StatusValue = "INFO"
                $DetailValue = "$DetailValue Known-safe downgrade: $($Rule.Reason)"
                break
            }
        }
    }

    [pscustomobject]@{
        Repository = $RepositoryValue
        Area       = $AreaValue
        Check      = $CheckValue
        Status     = $StatusValue
        Detail     = $DetailValue
    }
}
$CsvPath = Join-Path $OutDir "github-security-audit-summary.csv"
$HtmlPath = Join-Path $OutDir "github-security-audit-summary.html"
$TxtPath = Join-Path $OutDir "github-security-audit-summary.txt"

$ReportSummary |
    Sort-Object Repository, Area, Check |
    Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

$ReportSummary |
    Sort-Object Repository, Area, Check |
    Format-Table -AutoSize |
    Out-String |
    Set-Content -Path $TxtPath -Encoding UTF8


$StatusOrder = @{
    "FAIL" = 1
    "WARN" = 2
    "INFO" = 3
    "PASS" = 4
}

$SortedSummary = $ReportSummary |
    Sort-Object Repository, @{ Expression = { $StatusOrder[$_.Status] } }, Area, Check

$Totals = $ReportSummary |
    Group-Object Status |
    Sort-Object Name |
    ForEach-Object {
        $StatusLower = $_.Name.ToLower()
        "<button class='pill $StatusLower' type='button' onclick=`"setStatusFilter('$($_.Name)')`">$($_.Name): $($_.Count)</button>"
    }

$RepositoryButtons = $ReportSummary |
    Select-Object -ExpandProperty Repository -Unique |
    Sort-Object |
    ForEach-Object {
        $RepoSafe = [System.Net.WebUtility]::HtmlEncode($_)
        "<button class='repo-btn' type='button' onclick=`"setRepoFilter('$RepoSafe', true)`">$RepoSafe</button>"
    }

$RepositorySummaryRows = foreach ($RepoGroup in ($ReportSummary | Group-Object Repository | Sort-Object Name)) {
    $RepoName = $RepoGroup.Name
    $RepoId = "repo-" + ($RepoName -replace '[^a-zA-Z0-9_-]', '-')
    $PassCount = @($RepoGroup.Group | Where-Object Status -eq "PASS").Count
    $InfoCount = @($RepoGroup.Group | Where-Object Status -eq "INFO").Count
    $WarnCount = @($RepoGroup.Group | Where-Object Status -eq "WARN").Count
    $FailCount = @($RepoGroup.Group | Where-Object Status -eq "FAIL").Count

    "<tr id='$RepoId'><td><button class='link-btn' type='button' onclick=`"setRepoFilter('$RepoName', true)`">$([System.Net.WebUtility]::HtmlEncode($RepoName))</button></td><td class='status-pass'>$PassCount</td><td class='status-info'>$InfoCount</td><td class='status-warn'>$WarnCount</td><td class='status-fail'>$FailCount</td></tr>"
}

$Rows = foreach ($Item in $SortedSummary) {
    $Class = switch ($Item.Status) {
        "PASS" { "pass" }
        "WARN" { "warn" }
        "FAIL" { "fail" }
        default { "info" }
    }

    $RepoEncoded   = [System.Net.WebUtility]::HtmlEncode($Item.Repository)
    $AreaEncoded   = [System.Net.WebUtility]::HtmlEncode($Item.Area)
    $CheckEncoded  = [System.Net.WebUtility]::HtmlEncode($Item.Check)
    $StatusEncoded = [System.Net.WebUtility]::HtmlEncode($Item.Status)
    $DetailEncoded = [System.Net.WebUtility]::HtmlEncode($Item.Detail)

    "<tr class='$Class audit-row' data-repo='$RepoEncoded' data-status='$StatusEncoded'><td>$RepoEncoded</td><td>$AreaEncoded</td><td>$CheckEncoded</td><td>$StatusEncoded</td><td class='detail-cell'>$DetailEncoded</td></tr>"
}

$GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$HtmlTemplate = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>GitHub Public Security Audit</title>
<style>
:root {
  --bg: #0f172a;
  --panel: #111827;
  --panel-2: #1f2937;
  --border: #374151;
  --text: #e5e7eb;
  --muted: #94a3b8;
  --pass: #22c55e;
  --warn: #f59e0b;
  --fail: #ef4444;
  --info: #38bdf8;
}

* { box-sizing: border-box; }

body {
  font-family: Segoe UI, Arial, sans-serif;
  background: var(--bg);
  color: var(--text);
  margin: 0;
}

.page {
  margin: 28px;
}

h1 {
  color: #f8fafc;
  margin: 0 0 4px 0;
}

h2 {
  color: #cbd5e1;
  margin: 0 0 12px 0;
  font-weight: 400;
}

small {
  color: var(--muted);
}

.toolbar {
  position: sticky;
  top: 0;
  z-index: 10;
  background: rgba(15, 23, 42, 0.96);
  backdrop-filter: blur(8px);
  border-bottom: 1px solid var(--border);
  padding: 14px 28px;
  margin: 18px -28px 20px -28px;
}

.toolbar-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
  margin: 8px 0;
}

button, input {
  font: inherit;
}

button {
  cursor: pointer;
  border: 1px solid var(--border);
  background: #111827;
  color: var(--text);
  border-radius: 999px;
  padding: 7px 11px;
}

button:hover {
  border-color: #64748b;
  background: #172033;
}

button.active {
  outline: 2px solid #60a5fa;
  border-color: #60a5fa;
}

.search {
  min-width: 280px;
  width: min(520px, 100%);
  border: 1px solid var(--border);
  background: #020617;
  color: var(--text);
  border-radius: 999px;
  padding: 8px 12px;
}

.pill {
  display: inline-block;
  font-weight: 700;
}

.pill.pass { background:#064e3b; color:#bbf7d0; }
.pill.warn { background:#78350f; color:#fde68a; }
.pill.fail { background:#7f1d1d; color:#fecaca; }
.pill.info { background:#0c4a6e; color:#bae6fd; }

.repo-btn {
  background: #172033;
}

.summary-grid {
  display: grid;
  grid-template-columns: minmax(280px, 520px) 1fr;
  gap: 18px;
  align-items: start;
}

.card {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 14px;
}

.card h3 {
  margin: 0 0 10px 0;
  color: #f8fafc;
}

table {
  border-collapse: collapse;
  width: 100%;
  background: var(--panel);
}

th, td {
  border: 1px solid var(--border);
  padding: 8px;
  vertical-align: top;
  font-size: 13px;
}

th {
  background: var(--panel-2);
  text-align: left;
  position: sticky;
  top: 128px;
  z-index: 5;
  user-select: none;
}

th.sortable {
  cursor: pointer;
}

th.sortable::after {
  content: " ⇅";
  color: var(--muted);
  font-weight: 400;
}

tr.pass td:nth-child(4), .status-pass { color: var(--pass); font-weight: 700; }
tr.warn td:nth-child(4), .status-warn { color: var(--warn); font-weight: 700; }
tr.fail td:nth-child(4), .status-fail { color: var(--fail); font-weight: 700; }
tr.info td:nth-child(4), .status-info { color: var(--info); font-weight: 700; }

.detail-cell {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.link-btn {
  border: 0;
  background: transparent;
  color: #93c5fd;
  padding: 0;
  border-radius: 0;
  text-align: left;
}

.link-btn:hover {
  background: transparent;
  text-decoration: underline;
}

.hidden {
  display: none;
}

.counter {
  color: var(--muted);
  margin-left: auto;
}

.notice {
  color: var(--muted);
  line-height: 1.5;
}

@media (max-width: 980px) {
  .summary-grid {
    grid-template-columns: 1fr;
  }

  th {
    top: 178px;
  }
}
</style>
</head>
<body>
<div class="page">
  <h1>GitHub Public Security Audit</h1>
  <h2>Public repositories and GitHub Pages review</h2>
  <small>Generated: __GENERATED_AT__</small>

  <div class="toolbar">
    <div class="toolbar-row">
      <button type="button" id="filter-all" class="active" onclick="clearFilters()">All</button>
      <button type="button" id="filter-findings" onclick="setFindingsFilter()">Findings: WARN + FAIL</button>
      __TOTALS__
      <span class="counter" id="visible-count"></span>
    </div>

    <div class="toolbar-row">
      <button type="button" onclick="setRepoFilter('', false)">All repos</button>
      __REPO_BUTTONS__
    </div>

    <div class="toolbar-row">
      <input id="search" class="search" type="search" placeholder="Search repository, area, check, status or detail..." oninput="applyFilters()">
      <button type="button" onclick="clearSearch()">Clear search</button>
    </div>
  </div>

  <div class="summary-grid">
    <div class="card">
      <h3>Repository summary</h3>
      <table>
        <thead>
          <tr>
            <th>Repository</th>
            <th>PASS</th>
            <th>INFO</th>
            <th>WARN</th>
            <th>FAIL</th>
          </tr>
        </thead>
        <tbody>
          __REPOSITORY_SUMMARY_ROWS__
        </tbody>
      </table>
    </div>

    <div class="card">
      <h3>How to use this report</h3>
      <div class="notice">
        Use the repository buttons to jump/filter to one repository. Use WARN, FAIL or Findings to show only actionable rows across all repositories.
        Click table headers to sort rows. The Detail column shows the source or reason found by the audit.
      </div>
    </div>
  </div>

  <div class="card" style="margin-top:18px;">
    <h3>Audit rows</h3>
    <table id="audit-table">
      <thead>
        <tr>
          <th class="sortable" data-column="0">Repository</th>
          <th class="sortable" data-column="1">Area</th>
          <th class="sortable" data-column="2">Check</th>
          <th class="sortable" data-column="3">Status</th>
          <th class="sortable" data-column="4">Detail</th>
        </tr>
      </thead>
      <tbody>
        __ROWS__
      </tbody>
    </table>
  </div>
</div>

<script>
let currentStatus = "";
let findingsOnly = false;
let currentRepo = "";
let sortState = { column: null, direction: 1 };

function normalize(value) {
  return (value || "").toString().toLowerCase();
}

function setActiveButton(id) {
  document.querySelectorAll(".toolbar button").forEach(btn => btn.classList.remove("active"));
  const button = document.getElementById(id);
  if (button) button.classList.add("active");
}

function clearFilters() {
  currentStatus = "";
  findingsOnly = false;
  currentRepo = "";
  document.getElementById("search").value = "";
  setActiveButton("filter-all");
  applyFilters();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function clearSearch() {
  document.getElementById("search").value = "";
  applyFilters();
}

function setStatusFilter(status) {
  currentStatus = status;
  findingsOnly = false;
  setActiveButton("");
  applyFilters();
}

function setFindingsFilter() {
  currentStatus = "";
  findingsOnly = true;
  setActiveButton("filter-findings");
  applyFilters();
}

function setRepoFilter(repo, jump) {
  currentRepo = repo || "";
  applyFilters();

  if (jump && repo) {
    const row = document.querySelector('tr.audit-row[data-repo="' + CSS.escape(repo) + '"]:not(.hidden)');
    if (row) {
      row.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }
}

function applyFilters() {
  const search = normalize(document.getElementById("search").value);
  const rows = Array.from(document.querySelectorAll("#audit-table tbody tr.audit-row"));
  let visible = 0;

  rows.forEach(row => {
    const status = row.dataset.status || "";
    const repo = row.dataset.repo || "";
    const rowText = normalize(row.innerText);

    let show = true;

    if (currentRepo && repo !== currentRepo) show = false;
    if (currentStatus && status !== currentStatus) show = false;
    if (findingsOnly && !(status === "WARN" || status === "FAIL")) show = false;
    if (search && !rowText.includes(search)) show = false;

    row.classList.toggle("hidden", !show);
    if (show) visible++;
  });

  document.getElementById("visible-count").innerText = visible + " visible row(s)";
}

function sortTable(column) {
  const table = document.getElementById("audit-table");
  const tbody = table.querySelector("tbody");
  const rows = Array.from(tbody.querySelectorAll("tr.audit-row"));

  if (sortState.column === column) {
    sortState.direction = sortState.direction * -1;
  }
  else {
    sortState.column = column;
    sortState.direction = 1;
  }

  const statusWeight = { "FAIL": 1, "WARN": 2, "INFO": 3, "PASS": 4 };

  rows.sort((a, b) => {
    const av = a.children[column].innerText.trim();
    const bv = b.children[column].innerText.trim();

    if (column === 3) {
      return ((statusWeight[av] || 99) - (statusWeight[bv] || 99)) * sortState.direction;
    }

    return av.localeCompare(bv, undefined, { numeric: true, sensitivity: "base" }) * sortState.direction;
  });

  rows.forEach(row => tbody.appendChild(row));
  applyFilters();
}

document.querySelectorAll("th.sortable").forEach(th => {
  th.addEventListener("click", () => sortTable(Number(th.dataset.column)));
});

applyFilters();
</script>
</body>
</html>
'@

$Html = $HtmlTemplate.
    Replace("__GENERATED_AT__", [System.Net.WebUtility]::HtmlEncode($GeneratedAt)).
    Replace("__TOTALS__", ($Totals -join "`n")).
    Replace("__REPO_BUTTONS__", ($RepositoryButtons -join "`n")).
    Replace("__REPOSITORY_SUMMARY_ROWS__", ($RepositorySummaryRows -join "`n")).
    Replace("__ROWS__", ($Rows -join "`n"))

$Html | Set-Content -Path $HtmlPath -Encoding UTF8

# Remove offline cloned repository data and intermediate per-repository folders by default.
# The final output folder is intentionally kept minimal:
# - github-security-audit-summary.csv
# - github-security-audit-summary.html
# - github-security-audit-summary.txt
if (-not $KeepOfflineData) {
    Get-ChildItem -Path $OutDir -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Audit completed." -ForegroundColor Green
Write-Host "Output folder: $OutDir" -ForegroundColor Cyan
Write-Host "CSV:  $CsvPath"
Write-Host "HTML: $HtmlPath"
Write-Host "TXT:  $TxtPath"
if (-not $KeepOfflineData) {
    Write-Host "Offline cloned repository data removed. Use -KeepOfflineData to keep intermediate folders." -ForegroundColor DarkGray
}




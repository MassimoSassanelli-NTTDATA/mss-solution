<#
.SYNOPSIS
    Generates WORKSPACE.md and REPOSITORY_CONTEXT.md locally, mirroring the output of the
    Copilot Cloud Agent setup workflow.

.DESCRIPTION
    The Copilot Cloud Agent's entry point (.github/workflows/copilot-setup-steps.yml) calls the
    reusable copilot-platform-setup workflow (.github/workflows/copilot-platform-setup.yml). That
    workflow checks out every repository and then generates WORKSPACE.md and REPOSITORY_CONTEXT.md
    from .github/copilot-platform.json.

    Locally the sub-repositories are already checked out as sibling folders (see
    bootstrap-platform.ps1), so this script only reproduces the file-generation step. The output
    format is kept byte-compatible with the workflow's generator so a local workspace matches what
    the cloud agent sees. In addition, it resolves the *actual* checked-out branch of each
    sub-repository and warns about context paths in the manifest that do not exist on disk.

    Both generated files are listed in .gitignore and must not be committed.

.PARAMETER RepoRoot
    Platform repository root (the folder that contains .github/copilot-platform.json and the
    sibling sub-repositories). Defaults to the parent of the scripts folder.

.PARAMETER ManifestPath
    Path to the platform manifest, relative to RepoRoot.

.PARAMETER CheckoutMode
    'all' (default, matches copilot-setup-steps.yml) or 'dependency-closure'.

.PARAMETER CurrentRepository
    Name reported as "Current repository" in WORKSPACE.md. Defaults to the RepoRoot folder name.
    Pass 'mms-solution' to match the cloud agent header exactly.

.PARAMETER DefaultBranch
    Fallback branch label used only when a sub-repository is not checked out. Defaults to 'develop'.

.PARAMETER WorkspaceRoot
    Value reported as "Workspace root" in WORKSPACE.md. Defaults to the resolved RepoRoot path.

.PARAMETER SkipValidation
    Skip the post-generation check that warns about missing context paths.

.PARAMETER Quiet
    Suppress informational output.

.EXAMPLE
    ./scripts/generate-workspace-context.ps1

.EXAMPLE
    ./scripts/generate-workspace-context.ps1 -CurrentRepository mms-solution -WorkspaceRoot mms-solution
#>
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ManifestPath = '.github/copilot-platform.json',
    [ValidateSet('all', 'dependency-closure')]
    [string]$CheckoutMode = 'all',
    [string]$CurrentRepository,
    [string]$DefaultBranch = 'develop',
    [string]$WorkspaceRoot,
    [switch]$SkipValidation,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Literal backtick, wrapped around values to produce Markdown inline code spans.
$BackTick = '`'

function Write-Info {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "[generate-workspace-context] $Message" }
}

function Format-Code {
    param([string]$Value)
    return "$BackTick$Value$BackTick"
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

function Get-Array {
    param($Object, [string]$Name)
    $value = Get-Prop $Object $Name
    if ($null -eq $value) { return @() }
    return @($value)
}

function Add-RepoWithDeps {
    param($Repos, [string]$Name)
    if ($script:selectedList -contains $Name) { return }
    if (-not $Repos.Contains($Name)) {
        throw "Repository '$Name' is referenced as a dependency but not defined in the manifest."
    }
    $script:selectedList += $Name
    foreach ($dep in $Repos[$Name].dependencies) { Add-RepoWithDeps $Repos $dep }
}

# --- Resolve defaults -------------------------------------------------------
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $CurrentRepository) { $CurrentRepository = Split-Path -Leaf $RepoRoot }
if (-not $WorkspaceRoot) { $WorkspaceRoot = $RepoRoot }

$manifestFull = Join-Path $RepoRoot $ManifestPath
if (-not (Test-Path -LiteralPath $manifestFull)) {
    throw "Manifest not found: $manifestFull"
}

$manifest = Get-Content -LiteralPath $manifestFull -Raw | ConvertFrom-Json
if (-not (Get-Prop $manifest 'repositories')) {
    throw "Manifest has no 'repositories' section: $manifestFull"
}

$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)

# --- Normalize repository metadata (preserving manifest order) --------------
$repos = [ordered]@{}
foreach ($property in $manifest.repositories.PSObject.Properties) {
    $name = $property.Name
    $meta = $property.Value
    $context = Get-Prop $meta 'context'

    $branch = Get-Prop $meta 'branch'
    if (-not $branch) { $branch = 'auto' }
    $checkoutPath = Get-Prop $meta 'checkoutPath'
    if (-not $checkoutPath) { $checkoutPath = $name }

    $repos[$name] = [pscustomobject]@{
        name              = $name
        role              = (Get-Prop $meta 'role')
        branch            = $branch
        checkoutPath      = $checkoutPath
        dependencies      = (Get-Array $meta 'dependencies')
        agentGuidance     = (Get-Array $meta 'agentGuidance')
        agentInstructions = (Get-Array $context 'agentInstructions')
        architectureDocs  = (Get-Array $context 'architectureDocs')
        adrs              = (Get-Array $context 'adrs')
        buildCommands     = (Get-Array $context 'buildCommands')
        testCommands      = (Get-Array $context 'testCommands')
    }
}

# --- Select repositories (same logic as the workflow) -----------------------
if ($CheckoutMode -eq 'all' -or -not $repos.Contains($CurrentRepository)) {
    $selected = @($repos.Keys)
}
else {
    $script:selectedList = @()
    Add-RepoWithDeps $repos $CurrentRepository
    $selected = $script:selectedList
}

# --- Resolve the actual local branch of each selected repository ------------
$results = foreach ($name in $selected) {
    $meta = $repos[$name]
    $full = Join-Path $RepoRoot $meta.checkoutPath
    $fallbackBranch = if ($meta.branch -and $meta.branch -ne 'auto') { $meta.branch } else { $DefaultBranch }

    if ($hasGit -and (Test-Path -LiteralPath (Join-Path $full '.git'))) {
        $branch = (& git -C $full rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $branch) {
            $branch = $fallbackBranch
            $status = 'local-unknown'
        }
        elseif ($branch -eq 'HEAD') {
            $status = 'local-detached'
        }
        else {
            $status = 'local'
        }
    }
    elseif (Test-Path -LiteralPath $full) {
        $branch = $fallbackBranch
        $status = 'local-nogit'
    }
    else {
        $branch = $fallbackBranch
        $status = 'missing'
        Write-Warning "Sub-repository not checked out: $($meta.checkoutPath) (expected at $full). Run bootstrap-platform.ps1."
    }

    [pscustomobject]@{
        Repo   = $name
        Path   = $meta.checkoutPath
        Branch = $branch
        Status = $status
        Deps   = ($meta.dependencies -join ',')
    }
}

# --- Build WORKSPACE.md -----------------------------------------------------
$ws = New-Object System.Collections.Generic.List[string]
$ws.Add('# Copilot Workspace Context')
$ws.Add('')
$ws.Add("Workspace root: $(Format-Code $WorkspaceRoot)")
$ws.Add("Checkout mode: $(Format-Code $CheckoutMode)")
$ws.Add("Current repository: $(Format-Code $CurrentRepository)")
$ws.Add('')
$ws.Add('## Checked-Out Repositories')
$ws.Add('')
$ws.Add('| Repository | Checkout Path | Branch | Resolution | Dependencies |')
$ws.Add('|---|---|---|---|---|')
foreach ($row in $results) {
    $deps = if ($row.Deps) { $row.Deps } else { '-' }
    $ws.Add("| $(Format-Code $row.Repo) | $(Format-Code $row.Path) | $(Format-Code $row.Branch) | $(Format-Code $row.Status) | $deps |")
}
$ws.Add('')
$ws.Add('## Source of Truth')
$ws.Add('')
$ws.Add('- GitHub Issues, Sub-Issues and PRs are authoritative.')
$ws.Add('- REPOSITORY_CONTEXT.md is generated at runtime from the platform manifest.')

# --- Build REPOSITORY_CONTEXT.md --------------------------------------------
$rc = New-Object System.Collections.Generic.List[string]
$rc.Add('# Repository Context')
$rc.Add('')
$rc.Add('This file is generated at runtime from `.github/copilot-platform.json` and tells agents which sub-repository instructions, ADRs and docs must be read, plus the platform rules and per-repository agent guidance they must follow.')
$rc.Add('')

$rules = Get-Prop $manifest 'rules'
$ruleProps = @()
if ($rules) { $ruleProps = @($rules.PSObject.Properties) }
if ($ruleProps.Count -gt 0) {
    $rc.Add('## Platform Rules')
    $rc.Add('')
    foreach ($ruleProp in $ruleProps) {
        $rc.Add("- **$($ruleProp.Name)**: $($ruleProp.Value)")
    }
    $rc.Add('')
}

foreach ($name in $selected) {
    $meta = $repos[$name]
    $checkout = $meta.checkoutPath

    $rc.Add("## $name")
    $rc.Add('')
    $rc.Add("Role: $($meta.role)")
    $rc.Add("Checkout path: $(Format-Code $checkout)")
    $rc.Add('')

    if (@($meta.agentGuidance).Count -gt 0) {
        $rc.Add('### Agent Guidance')
        foreach ($item in $meta.agentGuidance) { $rc.Add("- $item") }
        $rc.Add('')
    }

    $rc.Add('### Required Agent Instructions')
    foreach ($item in $meta.agentInstructions) { $rc.Add("- $(Format-Code "$checkout/$item")") }
    $rc.Add('')

    $rc.Add('### Architecture Docs')
    foreach ($item in $meta.architectureDocs) { $rc.Add("- $(Format-Code "$checkout/$item")") }
    $rc.Add('')

    $rc.Add('### ADRs')
    foreach ($item in $meta.adrs) { $rc.Add("- $(Format-Code "$checkout/$item")") }
    $rc.Add('')

    $rc.Add('### Build Commands')
    foreach ($item in $meta.buildCommands) { $rc.Add("- $(Format-Code $item)") }
    $rc.Add('')

    $rc.Add('### Test Commands')
    foreach ($item in $meta.testCommands) { $rc.Add("- $(Format-Code $item)") }
    $rc.Add('')
}

# --- Write files (UTF-8 without BOM, LF line endings) -----------------------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$wsPath = Join-Path $RepoRoot 'WORKSPACE.md'
$rcPath = Join-Path $RepoRoot 'REPOSITORY_CONTEXT.md'
[System.IO.File]::WriteAllText($wsPath, (($ws -join "`n") + "`n"), $utf8NoBom)
[System.IO.File]::WriteAllText($rcPath, (($rc -join "`n") + "`n"), $utf8NoBom)

Write-Info "Generated WORKSPACE.md          -> $wsPath"
Write-Info "Generated REPOSITORY_CONTEXT.md -> $rcPath"

# --- Validate referenced context paths --------------------------------------
if (-not $SkipValidation) {
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($name in $selected) {
        $meta = $repos[$name]
        $checkoutFull = Join-Path $RepoRoot $meta.checkoutPath
        foreach ($group in @('agentInstructions', 'architectureDocs', 'adrs')) {
            foreach ($item in $meta.$group) {
                if (-not (Test-Path -LiteralPath (Join-Path $checkoutFull $item))) {
                    $missing.Add("$($meta.checkoutPath)/$item")
                }
            }
        }
    }

    if ($missing.Count -gt 0) {
        Write-Warning "REPOSITORY_CONTEXT.md references $($missing.Count) context path(s) that do not exist on disk:"
        foreach ($entry in ($missing | Sort-Object -Unique)) { Write-Warning "  - $entry" }
        Write-Warning "These come from the 'context' entries in $ManifestPath. The cloud agent would see the same broken references. Fix the manifest or add the missing files."
    }
}

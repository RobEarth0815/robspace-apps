<#
.SYNOPSIS
    Sync labels in .github/labels.yml to the GitHub repository.
.DESCRIPTION
    Reads labels.yml, then upserts each label via the GitHub REST API.
    Existing labels not in the file are NOT deleted by default — pass -Prune to remove them.
.EXAMPLE
    ./scripts/sync-labels.ps1
    ./scripts/sync-labels.ps1 -Prune
.NOTES
    Requires gh CLI on PATH with a token that has 'repo' scope.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'RobEarth0815/robspace-apps',
    [string]$LabelsFile = (Join-Path $PSScriptRoot '..\.github\labels.yml'),
    [switch]$Prune
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "gh CLI not found on PATH."
}

if (-not (Test-Path $LabelsFile)) {
    throw "labels.yml not found at $LabelsFile"
}

# Hand-roll a minimal YAML parser for our simple labels.yml shape:
#   - name: "..."
#     color: "..."
#     description: "..."
$desiredLabels = @()
$current = $null
foreach ($line in Get-Content -LiteralPath $LabelsFile) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -match '^\s*-\s*name:\s*"?([^"]+)"?\s*$') {
        if ($current) { $desiredLabels += [pscustomobject]$current }
        $current = @{ name = $matches[1].Trim(); color = ''; description = '' }
        continue
    }
    if ($line -match '^\s*color:\s*"?([^"]+)"?\s*$') {
        $current.color = $matches[1].Trim()
        continue
    }
    if ($line -match '^\s*description:\s*"?([^"]+)"?\s*$') {
        $current.description = $matches[1].Trim()
        continue
    }
}
if ($current) { $desiredLabels += [pscustomobject]$current }

Write-Host "Parsed $($desiredLabels.Count) labels from $LabelsFile" -ForegroundColor Cyan

# Pull existing labels
$existing = gh api -X GET "repos/$Repo/labels" --paginate | ConvertFrom-Json
$existingByName = @{}
foreach ($e in $existing) { $existingByName[$e.name] = $e }

$created = 0; $updated = 0; $skipped = 0
foreach ($lbl in $desiredLabels) {
    if ($existingByName.ContainsKey($lbl.name)) {
        $e = $existingByName[$lbl.name]
        if ($e.color -ne $lbl.color -or $e.description -ne $lbl.description) {
            $encodedName = [uri]::EscapeDataString($lbl.name)
            gh api -X PATCH "repos/$Repo/labels/$encodedName" -f new_name=$($lbl.name) -f color=$($lbl.color) -f description=$($lbl.description) | Out-Null
            Write-Host "  ~ updated  $($lbl.name)" -ForegroundColor Yellow
            $updated++
        } else {
            $skipped++
        }
    } else {
        gh api -X POST "repos/$Repo/labels" -f name=$($lbl.name) -f color=$($lbl.color) -f description=$($lbl.description) | Out-Null
        Write-Host "  + created  $($lbl.name)" -ForegroundColor Green
        $created++
    }
}

if ($Prune) {
    $desiredNames = $desiredLabels.name
    foreach ($e in $existing) {
        if ($desiredNames -notcontains $e.name) {
            $encodedName = [uri]::EscapeDataString($e.name)
            gh api -X DELETE "repos/$Repo/labels/$encodedName" | Out-Null
            Write-Host "  - removed  $($e.name)" -ForegroundColor Red
        }
    }
}

Write-Host "Done. created=$created updated=$updated skipped=$skipped" -ForegroundColor Cyan

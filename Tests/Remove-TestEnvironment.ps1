# Remove-TestEnvironment.ps1 — Deletes the test resource group and all its resources.
#
# Usage:
#   .\Tests\Remove-TestEnvironment.ps1              # reads from tests.env.json
#   .\Tests\Remove-TestEnvironment.ps1 -ResourceGroupName rg-kvrep-test-abc123
#   .\Tests\Remove-TestEnvironment.ps1 -All         # deletes ALL rg-kvrep-test-* groups
#   .\Tests\Remove-TestEnvironment.ps1 -All -Force  # skip confirmation

[CmdletBinding()]
param(
    [string] $ResourceGroupName,
    [switch] $All,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($All) {
    # Delete every rg-kvrep-test-* resource group in the subscription
    $groups = az group list -o json | ConvertFrom-Json | Where-Object { $_.name -like 'rg-kvrep-test-*' }
    if ($groups.Count -eq 0) {
        Write-Host "No rg-kvrep-test-* resource groups found."
        exit 0
    }
    Write-Host "Found $($groups.Count) resource group(s):"
    $groups | ForEach-Object { Write-Host "  $($_.name)" }

    if (-not $Force) {
        $confirm = Read-Host "Delete ALL of the above? [y/N]"
        if ($confirm -ne 'y') { Write-Host 'Aborted.'; exit 0 }
    }
    foreach ($rg in $groups) {
        Write-Host "Deleting $($rg.name) (--no-wait)..."
        az group delete --name $rg.name --yes --no-wait
    }
    Write-Host "All delete operations submitted. Deletions run in the background."

    $envFile = "$PSScriptRoot/tests.env.json"
    if (Test-Path $envFile) { Remove-Item $envFile -Force; Write-Host "Removed tests.env.json" }
    exit 0
}

# Single resource group mode
if (-not $ResourceGroupName) {
    $envFile = "$PSScriptRoot/tests.env.json"
    if (-not (Test-Path $envFile)) {
        throw "tests.env.json not found. Specify -ResourceGroupName explicitly or use -All."
    }
    $env = Get-Content $envFile | ConvertFrom-Json
    $ResourceGroupName = $env.ResourceGroupName
}

$exists = az group exists --name $ResourceGroupName -o tsv
if ($exists -ne 'true') {
    Write-Host "Resource group '$ResourceGroupName' does not exist. Nothing to do."
    exit 0
}

Write-Host "Resource group to delete: $ResourceGroupName"

if (-not $Force) {
    $confirm = Read-Host "Delete '$ResourceGroupName' and ALL its resources? [y/N]"
    if ($confirm -ne 'y') { Write-Host 'Aborted.'; exit 0 }
}

Write-Host "Deleting resource group (this may take a few minutes)..."
az group delete --name $ResourceGroupName --yes --no-wait

# Remove local env file
$envFile = "$PSScriptRoot/tests.env.json"
if (Test-Path $envFile) {
    Remove-Item $envFile -Force
    Write-Host "Removed tests.env.json"
}

Write-Host "Resource group deletion initiated. Resources will be removed in the background."

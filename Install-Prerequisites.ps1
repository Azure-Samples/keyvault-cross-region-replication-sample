# Install-Prerequisites.ps1 — Installs or validates all tools required to deploy
# and test the Key Vault Cross-Region Replication sample.
#
# Supported platforms: Windows (winget), macOS (brew), Linux (apt / direct download).
# Already-installed tools are skipped.
#
# Run once before deploying:
#   .\Install-Prerequisites.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$results = [ordered]@{}

function Test-CommandExists ([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Write-Status ([string]$Tool, [string]$Status, [string]$Detail = '') {
    $colour = switch ($Status) {
        'OK'       { 'Green'  }
        'Installed'{ 'Cyan'   }
        'Skipped'  { 'Yellow' }
        default    { 'Red'    }
    }
    $msg = "  [$Status] $Tool"
    if ($Detail) { $msg += " — $Detail" }
    Write-Host $msg -ForegroundColor $colour
    $results[$Tool] = $Status
}

$isWindows = $PSVersionTable.Platform -ne 'Unix' -or $IsWindows
$isMacOS   = $IsMacOS
$isLinux   = $IsLinux

Write-Host "`nKey Vault Cross-Region Replication — Prerequisites Installer" -ForegroundColor White
Write-Host "─────────────────────────────────────────────────────────────`n"

# ── Azure CLI ─────────────────────────────────────────────────────────────────
Write-Host "Checking Azure CLI..."
if (Test-CommandExists 'az') {
    $ver = (az version | ConvertFrom-Json).'azure-cli'
    Write-Status 'Azure CLI' 'OK' "v$ver"
}
else {
    Write-Host "  Installing Azure CLI..."
    if ($isWindows)     { winget install --id Microsoft.AzureCLI -e --silent }
    elseif ($isMacOS)   { brew update; brew install azure-cli }
    else                {
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    }
    Write-Status 'Azure CLI' 'Installed'
}

# ── Azure Functions Core Tools (v4) ──────────────────────────────────────────
Write-Host "Checking Azure Functions Core Tools..."
if (Test-CommandExists 'func') {
    $ver = (func --version 2>&1)
    Write-Status 'Azure Functions Core Tools' 'OK' "v$ver"
}
else {
    Write-Host "  Installing Azure Functions Core Tools v4 via npm..."
    if (-not (Test-CommandExists 'npm')) {
        Write-Host "  npm not found — please install Node.js (https://nodejs.org) and re-run." -ForegroundColor Red
        Write-Status 'Azure Functions Core Tools' 'FAILED' 'npm not found'
    }
    else {
        npm install -g azure-functions-core-tools@4 --unsafe-perm true | Out-Null
        Write-Status 'Azure Functions Core Tools' 'Installed'
    }
}

# ── Azure PowerShell — Az.Accounts ───────────────────────────────────────────
Write-Host "Checking Az.Accounts PowerShell module..."
if (Get-Module Az.Accounts -ListAvailable | Where-Object { $_.Version -ge '3.0' }) {
    $ver = (Get-Module Az.Accounts -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-Status 'Az.Accounts' 'OK' "v$ver"
}
else {
    Write-Host "  Installing Az.Accounts..."
    Install-Module Az.Accounts -MinimumVersion '3.0' -Force -Scope CurrentUser -Repository PSGallery
    Write-Status 'Az.Accounts' 'Installed'
}

# ── Azure PowerShell — Az.KeyVault ───────────────────────────────────────────
Write-Host "Checking Az.KeyVault PowerShell module..."
if (Get-Module Az.KeyVault -ListAvailable | Where-Object { $_.Version -ge '6.0' }) {
    $ver = (Get-Module Az.KeyVault -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-Status 'Az.KeyVault' 'OK' "v$ver"
}
else {
    Write-Host "  Installing Az.KeyVault..."
    Install-Module Az.KeyVault -MinimumVersion '6.0' -Force -Scope CurrentUser -Repository PSGallery
    Write-Status 'Az.KeyVault' 'Installed'
}

# ── Pester v5 ─────────────────────────────────────────────────────────────────
Write-Host "Checking Pester..."
if (Get-Module Pester -ListAvailable | Where-Object { $_.Version -ge '5.0' }) {
    $ver = (Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-Status 'Pester' 'OK' "v$ver"
}
else {
    Write-Host "  Installing Pester v5..."
    Install-Module Pester -MinimumVersion '5.0' -Force -Scope CurrentUser -Repository PSGallery
    Write-Status 'Pester' 'Installed'
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n─────────────────────────────────────────────────────────────"
Write-Host "Summary:"
foreach ($k in $results.Keys) {
    $colour = if ($results[$k] -in 'OK','Installed') { 'Green' } else { 'Red' }
    Write-Host "  $k : $($results[$k])" -ForegroundColor $colour
}

$failures = $results.Values | Where-Object { $_ -eq 'FAILED' }
if ($failures) {
    Write-Host "`nOne or more prerequisites could not be installed. See output above." -ForegroundColor Red
    exit 1
}

Write-Host "`nAll prerequisites are ready. Next steps:" -ForegroundColor Green
Write-Host "  1. az login"
Write-Host "  2. az account set --subscription <id>"
Write-Host "  3. .\Tests\Deploy-TestEnvironment.ps1"
Write-Host "  4. Invoke-Pester Tests\Test-Replication.Tests.ps1 -Output Detailed`n"

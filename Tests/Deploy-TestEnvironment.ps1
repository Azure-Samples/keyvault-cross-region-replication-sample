# Deploy-TestEnvironment.ps1 — Deploys an isolated test environment and publishes the
# Function App. Writes Tests/tests.env.json for use by the Pester test suite.
#
# Usage (interactive):
#   az login
#   az account set --subscription <id>
#   .\Tests\Deploy-TestEnvironment.ps1
#
# Usage (CI / non-interactive):
#   .\Tests\Deploy-TestEnvironment.ps1 -Force -ResourceGroupName rg-kvrep-ci -Location westeurope

[CmdletBinding()]
param(
    [string] $ResourceGroupName,
    [string] $Location         = 'westeurope',
    [string] $TargetLocation   = 'swedencentral',
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Confirm subscription ──────────────────────────────────────────────────────
$sub = az account show | ConvertFrom-Json
if (-not $sub) { throw 'No active Azure subscription. Run: az login' }

Write-Host "Active subscription: $($sub.name) ($($sub.id))"

if (-not $Force) {
    $confirm = Read-Host 'Deploy test environment to this subscription? [y/N]'
    if ($confirm -ne 'y') { Write-Host 'Aborted.'; exit 0 }
}

# ── Generate unique resource names ───────────────────────────────────────────
# Use a deterministic suffix derived from subscription ID so repeated runs
# reuse the same names instead of creating new resource groups each time.
# Override with -ResourceGroupName to use a fully custom name.
$suffix = $sub.id.Replace('-', '').Substring(0, 8)

if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-kvrep-test-$suffix"
}

# ── Clean up previous test environment if it exists ──────────────────────────
$envFile = "$PSScriptRoot/tests.env.json"
if (Test-Path $envFile) {
    $prevEnv = Get-Content $envFile | ConvertFrom-Json
    if ($prevEnv.ResourceGroupName -ne $ResourceGroupName) {
        Write-Host "Previous test environment found: $($prevEnv.ResourceGroupName)"
        Write-Host "  Cleaning up (--no-wait)..."
        az group delete --name $prevEnv.ResourceGroupName --yes --no-wait 2>$null
        Remove-Item $envFile -Force
    }
}

$names = @{
    ResourceGroup      = $ResourceGroupName
    SourceKeyVault     = "kv-src-$suffix"
    TargetKeyVault     = "kv-tgt-$suffix"
    FunctionApp        = "func-kvrep-$suffix"
    StorageAccount     = "stkvrep$suffix"
    AppInsights        = "ai-kvrep-$suffix"
    LogAnalytics       = "la-kvrep-$suffix"
}

Write-Host "Resource group : $($names.ResourceGroup)"
Write-Host "Source KV      : $($names.SourceKeyVault)"
Write-Host "Target KV      : $($names.TargetKeyVault)"
Write-Host "Function App   : $($names.FunctionApp)"

# ── Create resource group ─────────────────────────────────────────────────────
Write-Host "`nCreating resource group..."
az group create --name $names.ResourceGroup --location $Location | Out-Null

# ── Deploy Bicep ──────────────────────────────────────────────────────────────
Write-Host "Deploying infrastructure (this takes ~3-5 minutes)..."

# ── Common Bicep parameters ───────────────────────────────────────────────────
$bicepParams = @(
    "sourceKeyVaultName=$($names.SourceKeyVault)",
    "targetKeyVaultNames=['$($names.TargetKeyVault)']",
    "targetLocations=['$TargetLocation']",
    "functionAppName=$($names.FunctionApp)",
    "storageAccountName=$($names.StorageAccount)",
    "appInsightsName=$($names.AppInsights)",
    "logAnalyticsWorkspaceName=$($names.LogAnalytics)"
)

# ── Pass 1: Deploy everything except Event Grid subscriptions ─────────────────
# Event Grid validates the Function endpoint during subscription creation, so we
# must publish the function code first and deploy Event Grid in a second pass.
Write-Host "Deploying infrastructure — pass 1 (no Event Grid)..."

az deployment group create `
    --resource-group  $names.ResourceGroup `
    --template-file   "$PSScriptRoot/../Infrastructure/main.bicep" `
    --parameters      @bicepParams `
    --parameters      deployEventGrid=false `
    --output none

if ($LASTEXITCODE -ne 0) { throw "Bicep deployment (pass 1) failed." }

Write-Host "Infrastructure deployed."

# ── Publish Function App ──────────────────────────────────────────────────────
# Refresh PATH so newly installed tools (e.g. func from MSI) are visible.
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('PATH', 'User')

Write-Host "Publishing Function App..."
Push-Location "$PSScriptRoot/../App"
try {
    # Capture output so we can detect deployment success independently of the
    # exit code. `func` exits 1 when trigger-sync fails (a known transient
    # condition), even though the code upload itself succeeded.
    $funcOutput = func azure functionapp publish $names.FunctionApp --powershell 2>&1
    $funcOutput | ForEach-Object { Write-Host $_ }

    if (-not ($funcOutput -match 'Deployment completed successfully')) {
        throw "func publish deployment failed. Check output above."
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Trigger sync reported an error (exit code $LASTEXITCODE). This is often transient — deployment itself succeeded."
    }
}
finally {
    Pop-Location
}

Write-Host "Function App published."

# ── Wait for Function App to warm up ─────────────────────────────────────────
# Event Grid validates function endpoints during subscription creation.
# On a Consumption plan the host needs time to cold-start after publish.
$funcProps = az functionapp show --name $names.FunctionApp --resource-group $names.ResourceGroup | ConvertFrom-Json
$healthUrl  = "https://$($funcProps.defaultHostName)/api/health"
Write-Host "Waiting for Function App to respond at $healthUrl ..."

$warmUpTimeout = 180  # seconds
$warmUpStart   = Get-Date
$ready         = $false
while (-not $ready -and ((Get-Date) - $warmUpStart).TotalSeconds -lt $warmUpTimeout) {
    try {
        $resp = Invoke-WebRequest -Uri $healthUrl -Method GET -TimeoutSec 10 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Write-Host "  Not ready yet, retrying in 15s..."
    Start-Sleep -Seconds 15
}
if (-not $ready) {
    Write-Warning "Function App did not respond on /api/health within $warmUpTimeout s. Proceeding anyway — Event Grid may need a retry."
} else {
    Write-Host "Function App is ready."
}

# ── Pass 2: Deploy Event Grid subscriptions ───────────────────────────────────
Write-Host "Deploying Event Grid subscriptions — pass 2..."

$deployOutput = az deployment group create `
    --resource-group  $names.ResourceGroup `
    --template-file   "$PSScriptRoot/../Infrastructure/main.bicep" `
    --parameters      @bicepParams `
    --parameters      deployEventGrid=true `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw "Bicep deployment (pass 2) failed." }

# ── Grant current user KV roles for local test execution ─────────────────────
# Pester tests create/read objects in the vaults — the runner needs data-plane access.
Write-Host "Granting current user Key Vault roles for test execution..."
$currentUserOid = az ad signed-in-user show --query id -o tsv 2>$null
if ($currentUserOid) {
    $srcScope = "/subscriptions/$($sub.id)/resourceGroups/$($names.ResourceGroup)/providers/Microsoft.KeyVault/vaults/$($names.SourceKeyVault)"
    $tgtScope = "/subscriptions/$($sub.id)/resourceGroups/$($names.ResourceGroup)/providers/Microsoft.KeyVault/vaults/$($names.TargetKeyVault)"
    # Source: Officer roles to create/update/delete test data
    @('Key Vault Secrets Officer', 'Key Vault Certificates Officer') | ForEach-Object {
        az role assignment create --assignee $currentUserOid --role $_ --scope $srcScope --output none 2>$null
    }
    # Target: Reader roles to verify replication results
    @('Key Vault Secrets User', 'Key Vault Certificate User') | ForEach-Object {
        az role assignment create --assignee $currentUserOid --role $_ --scope $tgtScope --output none 2>$null
    }
    Write-Host "Key Vault roles granted to current user ($currentUserOid)."
} else {
    Write-Warning "Could not determine current user OID. Grant Key Vault roles manually if running tests locally."
}

# ── Retrieve Function App URL ─────────────────────────────────────────────────
$functionAppUrl = "https://$($funcProps.defaultHostName)"

# ── Write tests.env.json ──────────────────────────────────────────────────────
$testEnv = [ordered]@{
    SubscriptionId      = $sub.id
    ResourceGroupName   = $names.ResourceGroup
    SourceKeyVaultName  = $names.SourceKeyVault
    TargetKeyVaultNames = @($names.TargetKeyVault)
    FunctionAppName     = $names.FunctionApp
    FunctionAppUrl      = $functionAppUrl
}

$outPath = "$PSScriptRoot/tests.env.json"
$testEnv | ConvertTo-Json -Depth 3 | Set-Content $outPath

Write-Host "`nTest environment ready."
Write-Host "Config written to: $outPath"
Write-Host "`nRun tests with:"
Write-Host "  Invoke-Pester Tests\Test-Replication.Tests.ps1 -Output Detailed"

using namespace System.Net

param($req, $TriggerMetadata)

Import-Module "$PSScriptRoot/../Modules/KvReplication.psm1" -Force

$sourceVault  = $env:SOURCE_KEYVAULT_NAME
$targetVaults = @()
try { $targetVaults = Get-TargetVaultNames } catch {}

$report = [ordered]@{
    status       = 'Healthy'
    timestamp    = (Get-Date -Format 'o')
    sourceVault  = @{ name = $sourceVault; status = 'Unknown' }
    targetVaults = @()
}

# Probe source vault
try {
    Get-AzKeyVaultSecret -VaultName $sourceVault -ErrorAction Stop | Select-Object -First 1 | Out-Null
    $report.sourceVault.status = 'Reachable'
}
catch {
    $report.status                = 'Degraded'
    $report.sourceVault.status    = "Unreachable: $($_.Exception.Message)"
}

# Probe each target vault
foreach ($target in $targetVaults) {
    $entry = [ordered]@{ name = $target; status = 'Unknown' }
    try {
        Get-AzKeyVaultSecret -VaultName $target -ErrorAction Stop | Select-Object -First 1 | Out-Null
        $entry.status = 'Reachable'
    }
    catch {
        $report.status = 'Degraded'
        $entry.status  = "Unreachable: $($_.Exception.Message)"
    }
    $report.targetVaults += $entry
}

$httpStatus = if ($report.status -eq 'Healthy') { [HttpStatusCode]::OK } else { [HttpStatusCode]::ServiceUnavailable }

Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
    StatusCode = $httpStatus
    Body       = ($report | ConvertTo-Json -Depth 4)
    Headers    = @{ 'Content-Type' = 'application/json' }
})

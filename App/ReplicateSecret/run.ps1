param($eventGridEvent, $TriggerMetadata)

Import-Module "$PSScriptRoot/../Modules/KvReplication.psm1" -Force

$secretName    = $eventGridEvent.data.ObjectName
$secretVersion = $eventGridEvent.data.Version
$sourceVault   = $eventGridEvent.data.VaultName

if ([string]::IsNullOrWhiteSpace($secretName) -or [string]::IsNullOrWhiteSpace($sourceVault)) {
    Write-Error "Invalid event payload: missing ObjectName or VaultName."
    return
}

try {
    $targetVaults = Get-TargetVaultNames
    Copy-KvSecret `
        -SourceVaultName  $sourceVault `
        -SecretName       $secretName `
        -SecretVersion    $secretVersion `
        -TargetVaultNames $targetVaults
}
catch {
    Write-ReplicationLog "Failed to replicate secret '$secretName': $_" `
        -Level Error `
        -Properties @{ sourceVault = $sourceVault; secretName = $secretName }
    throw
}

param($eventGridEvent, $TriggerMetadata)

Import-Module "$PSScriptRoot/../Modules/KvReplication.psm1" -Force

$certName    = $eventGridEvent.data.ObjectName
$certVersion = $eventGridEvent.data.Version
$sourceVault = $eventGridEvent.data.VaultName

if ([string]::IsNullOrWhiteSpace($certName) -or [string]::IsNullOrWhiteSpace($sourceVault)) {
    Write-Error "Invalid event payload: missing ObjectName or VaultName."
    return
}

try {
    $targetVaults = Get-TargetVaultNames
    Copy-KvCertificate `
        -SourceVaultName    $sourceVault `
        -CertificateName    $certName `
        -CertificateVersion $certVersion `
        -TargetVaultNames   $targetVaults
}
catch {
    Write-ReplicationLog "Failed to replicate certificate '$certName': $_" `
        -Level Error `
        -Properties @{ sourceVault = $sourceVault; certName = $certName }
    throw
}

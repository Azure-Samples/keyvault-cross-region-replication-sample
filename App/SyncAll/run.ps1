param($timer)

Import-Module "$PSScriptRoot/../Modules/KvReplication.psm1" -Force

$sourceVault  = $env:SOURCE_KEYVAULT_NAME
$targetVaults = Get-TargetVaultNames

Write-ReplicationLog "Starting full sync from '$sourceVault' to: $($targetVaults -join ', ')" `
    -Properties @{ trigger = if ($timer) { 'timer' } else { 'manual' } }

$results = @{ secrets = 0; certificates = 0; skipped = 0; failures = 0 }

# ── Secrets ──────────────────────────────────────────────────────────────────
try {
    $sourceSecrets = Get-AzKeyVaultSecret -VaultName $sourceVault
    foreach ($s in $sourceSecrets) {
        try {
            $current = Get-AzKeyVaultSecret -VaultName $sourceVault -Name $s.Name
            foreach ($target in $targetVaults) {
                $existing = Get-AzKeyVaultSecret -VaultName $target -Name $s.Name -ErrorAction SilentlyContinue
                if (-not $existing -or $existing.Version -ne $current.Version) {
                    Copy-KvSecret -SourceVaultName $sourceVault -SecretName $s.Name `
                        -SecretVersion $current.Version -TargetVaultNames @($target)
                    $results.secrets++
                }
                else { $results.skipped++ }
            }
        }
        catch {
            Write-ReplicationLog "Sync failed for secret '$($s.Name)': $_" -Level Error
            $results.failures++
        }
    }
}
catch {
    Write-ReplicationLog "Failed to list secrets from '$sourceVault': $_" -Level Error
    $results.failures++
}

# ── Certificates ─────────────────────────────────────────────────────────────
try {
    $sourceCerts = Get-AzKeyVaultCertificate -VaultName $sourceVault
    foreach ($c in $sourceCerts) {
        try {
            $current = Get-AzKeyVaultCertificate -VaultName $sourceVault -Name $c.Name
            foreach ($target in $targetVaults) {
                $existing = Get-AzKeyVaultCertificate -VaultName $target -Name $c.Name -ErrorAction SilentlyContinue
                if (-not $existing -or $existing.Version -ne $current.Version) {
                    Copy-KvCertificate -SourceVaultName $sourceVault -CertificateName $c.Name `
                        -CertificateVersion $current.Version -TargetVaultNames @($target)
                    $results.certificates++
                }
                else { $results.skipped++ }
            }
        }
        catch {
            Write-ReplicationLog "Sync failed for certificate '$($c.Name)': $_" -Level Error
            $results.failures++
        }
    }
}
catch {
    Write-ReplicationLog "Failed to list certificates from '$sourceVault': $_" -Level Error
    $results.failures++
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-ReplicationLog "Full sync completed" -Properties $results

if ($results.failures -gt 0) {
    throw "Full sync completed with $($results.failures) failure(s). Check Application Insights for details."
}

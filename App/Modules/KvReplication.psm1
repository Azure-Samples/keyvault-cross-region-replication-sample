# KvReplication.psm1 — Shared module for Key Vault cross-region replication.
# Imported by all Function App functions. Provides retry, logging, and per-object-type copy helpers.
# Supports secrets and certificates. Keys are out of scope (see README).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Executes a script block with exponential back-off retry, honouring 429 Retry-After headers.
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$MaxAttempts        = 3,
        [int]$InitialDelaySeconds = 2
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return (& $ScriptBlock)
        }
        catch {
            if ($attempt -ge $MaxAttempts) { throw }

            $delay = $InitialDelaySeconds * [Math]::Pow(2, $attempt - 1)

            if ($_.Exception.Message -match '429|TooManyRequests|throttl') {
                $delay = [Math]::Max($delay, 30)
                Write-Warning "Rate-limited by Key Vault API. Waiting ${delay}s before retry $($attempt + 1)/$MaxAttempts."
            }
            elseif ($_.Exception.Message -match '503|ServiceUnavailable|temporarily unavailable') {
                $delay = [Math]::Max($delay, 15)
                Write-Warning "Key Vault temporarily unavailable. Waiting ${delay}s before retry $($attempt + 1)/$MaxAttempts."
            }
            else {
                Write-Warning "Attempt $attempt failed: $($_.Exception.Message). Retrying in ${delay}s ($($attempt + 1)/$MaxAttempts)."
            }

            Start-Sleep -Seconds $delay
        }
    }
}

<#
.SYNOPSIS
    Writes a structured JSON log entry.
    In Azure Functions, Write-Host routes to Application Insights traces.
    Write-Error routes to Application Insights exceptions.
#>
function Write-ReplicationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Information', 'Warning', 'Error')][string]$Level = 'Information',
        [hashtable]$Properties = @{}
    )

    $entry = [ordered]@{
        timestamp = (Get-Date -Format 'o')
        level     = $Level
        message   = $Message
    }
    foreach ($k in $Properties.Keys) { $entry[$k] = $Properties[$k] }

    $json = $entry | ConvertTo-Json -Compress -Depth 3

    switch ($Level) {
        'Error'   { Write-Error   $json }
        'Warning' { Write-Warning $json }
        default   { Write-Host    $json }
    }
}

<#
.SYNOPSIS
    Returns the list of target vault names from the TARGET_KEYVAULT_NAMES environment variable
    (comma-separated).
#>
function Get-TargetVaultNames {
    [CmdletBinding()]
    param()

    $raw = $env:TARGET_KEYVAULT_NAMES
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Environment variable 'TARGET_KEYVAULT_NAMES' is not set or empty."
    }
    return @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

<#
.SYNOPSIS
    Copies a Key Vault secret from the source vault to one or more target vaults.
#>
function Copy-KvSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]   $SourceVaultName,
        [Parameter(Mandatory)][string]   $SecretName,
        [string]                          $SecretVersion,
        [Parameter(Mandatory)][string[]] $TargetVaultNames
    )

    Write-ReplicationLog "Replicating secret '$SecretName'" -Properties @{
        objectType  = 'secret'
        sourceVault = $SourceVaultName
        secretName  = $SecretName
        version     = $SecretVersion
    }

    $getParams = @{ VaultName = $SourceVaultName; Name = $SecretName; AsPlainText = $true }
    if ($SecretVersion) { $getParams['Version'] = $SecretVersion }
    $plainValue  = Invoke-WithRetry { Get-AzKeyVaultSecret @getParams }
    $secureValue = ConvertTo-SecureString $plainValue -AsPlainText -Force

    foreach ($target in $TargetVaultNames) {
        Invoke-WithRetry {
            Set-AzKeyVaultSecret -VaultName $target -Name $SecretName -SecretValue $secureValue | Out-Null
        }
        Write-ReplicationLog "Secret '$SecretName' replicated to '$target'" -Properties @{
            objectType  = 'secret'
            sourceVault = $SourceVaultName
            targetVault = $target
            secretName  = $SecretName
        }
    }
}

<#
.SYNOPSIS
    Copies a Key Vault certificate to one or more target vaults via the secret endpoint.
    Key Vault stores certificates internally as base64-encoded PFX secrets.
    The certificate's private key must be exportable.
#>
function Copy-KvCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]   $SourceVaultName,
        [Parameter(Mandatory)][string]   $CertificateName,
        [string]                          $CertificateVersion,
        [Parameter(Mandatory)][string[]] $TargetVaultNames
    )

    Write-ReplicationLog "Replicating certificate '$CertificateName'" -Properties @{
        objectType  = 'certificate'
        sourceVault = $SourceVaultName
        certName    = $CertificateName
        version     = $CertificateVersion
    }

    # Retrieve the certificate as base64-encoded PFX via the secret endpoint
    $getParams = @{ VaultName = $SourceVaultName; Name = $CertificateName; AsPlainText = $true }
    if ($CertificateVersion) { $getParams['Version'] = $CertificateVersion }
    $base64Pfx = Invoke-WithRetry { Get-AzKeyVaultSecret @getParams }

    $pfxBytes       = [Convert]::FromBase64String($base64Pfx)
    $certCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
    $certCollection.Import(
        $pfxBytes,
        $null,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    )

    foreach ($target in $TargetVaultNames) {
        Invoke-WithRetry {
            Import-AzKeyVaultCertificate -VaultName $target -Name $CertificateName `
                -CertificateCollection $certCollection | Out-Null
        }
        Write-ReplicationLog "Certificate '$CertificateName' replicated to '$target'" -Properties @{
            objectType  = 'certificate'
            sourceVault = $SourceVaultName
            targetVault = $target
            certName    = $CertificateName
        }
    }
}

Export-ModuleMember -Function `
    Invoke-WithRetry, `
    Write-ReplicationLog, `
    Get-TargetVaultNames, `
    Copy-KvSecret, `
    Copy-KvCertificate

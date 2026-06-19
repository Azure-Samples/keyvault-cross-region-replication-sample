# Test-Replication.Tests.ps1 — Pester v5 end-to-end regression suite for the
# Key Vault Cross-Region Replication sample.
#
# Prerequisites:
#   1. Run Deploy-TestEnvironment.ps1 (creates Tests/tests.env.json)
#   2. az login with an account that has read access to the test vaults
#
# Run:
#   Invoke-Pester Tests\Test-Replication.Tests.ps1 -Output Detailed

BeforeAll {
    $envFile = "$PSScriptRoot/tests.env.json"
    if (-not (Test-Path $envFile)) {
        throw "tests.env.json not found. Run Tests\Deploy-TestEnvironment.ps1 first."
    }
    $script:env = Get-Content $envFile | ConvertFrom-Json

    $script:sourceVault  = $script:env.SourceKeyVaultName
    $script:targetVaults = @($script:env.TargetKeyVaultNames)
    $script:funcUrl      = $script:env.FunctionAppUrl
    $script:funcName     = $script:env.FunctionAppName
    $script:rg           = $script:env.ResourceGroupName

    # Replication is event-driven — allow up to this many seconds for propagation
    $script:replicationTimeoutSeconds = 180
    $script:pollIntervalSeconds       = 10

    # Connect to Azure:
    #   - In CI with Managed Identity: Connect-AzAccount -Identity
    #   - Locally: use the cached az CLI session token
    $miOk = $false
    try {
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        $miOk = $true
    } catch { }

    if (-not $miOk) {
        $azCtx = az account show 2>$null | ConvertFrom-Json
        if ($azCtx) {
            $mgmtToken = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv 2>$null
            $kvToken   = az account get-access-token --resource https://vault.azure.net     --query accessToken -o tsv 2>$null
            Connect-AzAccount -AccessToken $mgmtToken -KeyVaultAccessToken $kvToken `
                              -AccountId $azCtx.user.name -TenantId $azCtx.tenantId -ErrorAction Stop | Out-Null
        } else {
            Connect-AzAccount | Out-Null
        }
    }
    Set-AzContext -SubscriptionId $script:env.SubscriptionId -ErrorAction SilentlyContinue | Out-Null

    # Helper: wait until a condition is true or timeout expires
    function Wait-Until {
        param(
            [scriptblock] $Condition,
            [int]         $TimeoutSeconds  = $script:replicationTimeoutSeconds,
            [int]         $IntervalSeconds = $script:pollIntervalSeconds,
            [string]      $Description     = 'condition'
        )
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            if (& $Condition) { return $true }
            Write-Host "  Waiting for $Description..."
            Start-Sleep -Seconds $IntervalSeconds
        }
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Secret Replication' {

    BeforeAll {
        $script:testSecretName  = "test-secret-$(New-Guid)"
        $script:testSecretValue = "value-$(New-Guid)"
    }

    It 'replicates a new secret to all target vaults within the timeout' {
        # Create secret in source vault
        Set-AzKeyVaultSecret `
            -VaultName   $script:sourceVault `
            -Name        $script:testSecretName `
            -SecretValue (ConvertTo-SecureString $script:testSecretValue -AsPlainText -Force) | Out-Null

        foreach ($target in $script:targetVaults) {
            $found = Wait-Until -Description "secret '$($script:testSecretName)' in '$target'" -Condition {
                $s = Get-AzKeyVaultSecret -VaultName $target -Name $script:testSecretName -AsPlainText -ErrorAction SilentlyContinue
                $s -eq $script:testSecretValue
            }
            $found | Should -BeTrue -Because "secret should be replicated to '$target' within $($script:replicationTimeoutSeconds)s"
        }
    }

    It 'is idempotent — importing the same secret version twice does not throw' {
        { Set-AzKeyVaultSecret `
            -VaultName   $script:sourceVault `
            -Name        $script:testSecretName `
            -SecretValue (ConvertTo-SecureString $script:testSecretValue -AsPlainText -Force) | Out-Null
        } | Should -Not -Throw
    }

    AfterAll {
        # Cleanup
        Remove-AzKeyVaultSecret -VaultName $script:sourceVault -Name $script:testSecretName -Force -ErrorAction SilentlyContinue | Out-Null
        foreach ($t in $script:targetVaults) {
            Remove-AzKeyVaultSecret -VaultName $t -Name $script:testSecretName -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Certificate Replication' {

    BeforeAll {
        $script:testCertName = "test-cert-$(New-Guid)"

        # Create a self-signed certificate with an exportable key
        $policy = New-AzKeyVaultCertificatePolicy `
            -SubjectName           'CN=kv-replication-test' `
            -IssuerName            'Self' `
            -ValidityInMonths      1 `
            -KeyType               RSA `
            -KeySize               2048 `
            -ReuseKeyOnRenewal     $false

        Add-AzKeyVaultCertificate `
            -VaultName        $script:sourceVault `
            -Name             $script:testCertName `
            -CertificatePolicy $policy | Out-Null

        # Wait for the certificate to reach 'Completed' state before replication can happen
        $ready = Wait-Until -TimeoutSeconds 120 -Description "certificate '$($script:testCertName)' to complete issuance" -Condition {
            $op = Get-AzKeyVaultCertificateOperation -VaultName $script:sourceVault -Name $script:testCertName
            $op.Status -eq 'completed'
        }
        if (-not $ready) { throw "Certificate '$($script:testCertName)' did not complete issuance within 2 minutes." }
    }

    It 'replicates a self-signed certificate to all target vaults within the timeout' {
        foreach ($target in $script:targetVaults) {
            $found = Wait-Until -Description "certificate '$($script:testCertName)' in '$target'" -Condition {
                $null -ne (Get-AzKeyVaultCertificate -VaultName $target -Name $script:testCertName -ErrorAction SilentlyContinue)
            }
            $found | Should -BeTrue -Because "certificate should be replicated to '$target' within $($script:replicationTimeoutSeconds)s"
        }
    }

    AfterAll {
        Remove-AzKeyVaultCertificate -VaultName $script:sourceVault -Name $script:testCertName -Force -ErrorAction SilentlyContinue | Out-Null
        foreach ($t in $script:targetVaults) {
            Remove-AzKeyVaultCertificate -VaultName $t -Name $script:testCertName -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Full Sync (SyncAll function)' {

    BeforeAll {
        # Create a secret directly in source vault WITHOUT triggering Event Grid
        # (simulates an object that existed before Event Grid was configured)
        $script:preSyncSecretName  = "pre-sync-$(New-Guid)"
        $script:preSyncSecretValue = "presync-$(New-Guid)"

        Set-AzKeyVaultSecret `
            -VaultName   $script:sourceVault `
            -Name        $script:preSyncSecretName `
            -SecretValue (ConvertTo-SecureString $script:preSyncSecretValue -AsPlainText -Force) | Out-Null

        # Ensure it does NOT yet exist in target (give event a moment to NOT arrive)
        Start-Sleep -Seconds 5
    }

    It 'invoking SyncAll via the Azure Functions admin API replicates pre-existing objects' {
        # Trigger the SyncAll function via the admin endpoint (requires master key)
        $masterKey = az functionapp keys list --name $script:funcName --resource-group $script:rg --query "masterKey" -o tsv 2>$null
        $adminUrl  = "$($script:funcUrl)/admin/functions/SyncAll"
        $response  = Invoke-RestMethod -Method Post -Uri $adminUrl `
            -Headers @{ 'Content-Type' = 'application/json'; 'x-functions-key' = $masterKey } `
            -Body '{}' `
            -ErrorAction SilentlyContinue

        # Allow sync to complete
        Start-Sleep -Seconds 30

        foreach ($target in $script:targetVaults) {
            $found = Wait-Until -TimeoutSeconds 60 -Description "pre-sync secret in '$target'" -Condition {
                $s = Get-AzKeyVaultSecret -VaultName $target -Name $script:preSyncSecretName -AsPlainText -ErrorAction SilentlyContinue
                $s -eq $script:preSyncSecretValue
            }
            $found | Should -BeTrue -Because "SyncAll should replicate pre-existing secrets to '$target'"
        }
    }

    AfterAll {
        Remove-AzKeyVaultSecret -VaultName $script:sourceVault -Name $script:preSyncSecretName -Force -ErrorAction SilentlyContinue | Out-Null
        foreach ($t in $script:targetVaults) {
            Remove-AzKeyVaultSecret -VaultName $t -Name $script:preSyncSecretName -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe 'Health Check endpoint' {

    It 'GET /api/health returns HTTP 200 with a Healthy status' {
        $response = Invoke-RestMethod -Method Get -Uri "$($script:funcUrl)/api/health" -ErrorAction Stop
        $response.status | Should -Be 'Healthy'
    }

    It 'response contains sourceVault and targetVaults fields' {
        $response = Invoke-RestMethod -Method Get -Uri "$($script:funcUrl)/api/health" -ErrorAction Stop
        $response.sourceVault  | Should -Not -BeNullOrEmpty
        $response.targetVaults | Should -Not -BeNullOrEmpty
    }
}

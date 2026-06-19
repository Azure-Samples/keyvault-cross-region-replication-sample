# Azure Key Vault Cross-Region Replication

This sample demonstrates how to replicate Azure Key Vault **secrets** and **certificates** across regions and geographies in near-real time using an event-driven Azure Function (PowerShell) and Azure Event Grid.

Azure Key Vault has no native active-active cross-region sync. This sample provides a deployable, production-oriented reference implementation using a serverless, event-driven pattern. It covers:

- Near-real-time replication via Event Grid triggers
- Periodic full-sync and reconciliation (catches any missed events)
- Application Insights observability with automated failure alerts
- A health check endpoint for operational monitoring
- End-to-end Pester test suite with local and CI/CD validation

## Table of Contents

- [Azure Key Vault Cross-Region Replication](#azure-key-vault-cross-region-replication)
  - [Table of Contents](#table-of-contents)
  - [Architecture](#architecture)
  - [Prerequisites](#prerequisites)
  - [Getting Started](#getting-started)
    - [1. Install prerequisites](#1-install-prerequisites)
    - [2. Log in to Azure](#2-log-in-to-azure)
    - [3. Deploy the test environment and run validation](#3-deploy-the-test-environment-and-run-validation)
    - [4. Run the Pester test suite](#4-run-the-pester-test-suite)
    - [5. Deploy to production](#5-deploy-to-production)
    - [6. Teardown test environment](#6-teardown-test-environment)
  - [How It Works](#how-it-works)
    - [Secrets](#secrets)
    - [Certificates](#certificates)
    - [Retry and Resilience](#retry-and-resilience)
    - [Event Grid Events](#event-grid-events)
  - [Required Permissions](#required-permissions)
  - [Known Limitations](#known-limitations)
  - [Folder Structure](#folder-structure)
  - [Background: Why This Pattern](#background-why-this-pattern)
    - [Secrets and Certificates](#secrets-and-certificates)
    - [Why the native backup/restore cmdlets do not work cross-geography](#why-the-native-backuprestore-cmdlets-do-not-work-cross-geography)
    - [Why the secret endpoint is used for certificates](#why-the-secret-endpoint-is-used-for-certificates)
    - [Related Microsoft samples and references](#related-microsoft-samples-and-references)
  - [References](#references)

---

## Architecture

An Event Grid System Topic on the source Key Vault triggers an Azure Function whenever a new secret or certificate version is created. The Function reads the object from the source vault and imports it into one or more target vaults in any region or geography.

**Secret / Certificate replication (same pattern for both):**

```
Source Key Vault
   │
   │  Microsoft.KeyVault.{Secret|Certificate}NewVersionCreated
   ▼
Azure Event Grid (System Topic)
   │
   │  HTTP POST (event payload)
   ▼
Azure Function (PowerShell) — Replicate{Secret|Certificate}
   │
   ├── Read object from source KV
   │
   ├── Write to Target KV — Region A
   │
   └── Write to Target KV — Region B / Geography
```

**Reconciliation (catches missed events):**

```
Timer trigger (every 6h, configurable)
   ▼
Azure Function (PowerShell) — SyncAll
   │
   ├── Enumerate all secrets / certificates in source KV
   ├── Compare with each target KV
   └── Replicate any missing or outdated objects
```

---

## Prerequisites

Run the prerequisites installer to check and install all required tools:

```powershell
.\Install-Prerequisites.ps1
```

The script installs (or validates) the following:

| Tool                                                                                                | Minimum version |
| --------------------------------------------------------------------------------------------------- | --------------- |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)                                | latest          |
| [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local) | v4              |
| Az.Accounts PowerShell module                                                                       | 3.x             |
| Az.KeyVault PowerShell module                                                                       | 6.x             |
| [Pester](https://pester.dev) (test suite)                                                           | 5.x             |

You also need:
- An Azure subscription with **Contributor** access
- Source Key Vault certificates created with an **exportable** private key policy

---

## Getting Started

### 1. Install prerequisites

```powershell
.\Install-Prerequisites.ps1
```

### 2. Log in to Azure

```powershell
az login
az account set --subscription <your-subscription-id>
```

### 3. Deploy the test environment and run validation

This deploys an isolated resource group, publishes the Function App, and writes `Tests/tests.env.json`:

```powershell
.\Tests\Deploy-TestEnvironment.ps1
```

### 4. Run the Pester test suite

```powershell
Invoke-Pester Tests\Test-Replication.Tests.ps1 -Output Detailed
```

All tests should pass. Copilot will iterate on failures automatically (requirement: you only need to validate once at the end).

### 5. Deploy to production

Update `Infrastructure/main.bicepparam` with your production Key Vault names and regions, then:

```powershell
# Create or target your production resource group
az group create --name rg-kv-replication --location westeurope

# Deploy infrastructure
az deployment group create \
  --resource-group rg-kv-replication \
  --template-file  Infrastructure/main.bicep \
  --parameters     Infrastructure/main.bicepparam

# Publish the Function App
cd App
func azure functionapp publish <your-function-app-name> --powershell
```

### 6. Teardown test environment

```powershell
.\Tests\Remove-TestEnvironment.ps1
```

---

## How It Works

### Secrets

The Function reads the secret value via `Get-AzKeyVaultSecret` and writes it to each target vault with `Set-AzKeyVaultSecret`. Secrets replicate across all Azure geographies and subscriptions with no restrictions.

### Certificates

Key Vault stores every certificate internally as a secret in base64-encoded PFX format (`application/x-pkcs12`). The Function retrieves the full certificate including the private key via the **secret endpoint** (`Get-AzKeyVaultSecret`) and calls `Import-AzKeyVaultCertificate` on each target vault. This approach works across all Azure geographies and subscriptions.

### Retry and Resilience

All Key Vault API calls are wrapped in an exponential back-off retry helper (`Invoke-WithRetry`). Rate-limit (429) and service-unavailability (503) responses are detected and handled with appropriate wait times before retrying.

### Event Grid Events

| Object type | Trigger event                                     | Optional alerting events                      |
| ----------- | ------------------------------------------------- | --------------------------------------------- |
| Secret      | `Microsoft.KeyVault.SecretNewVersionCreated`      | `SecretNearExpiry`, `SecretExpired`           |
| Certificate | `Microsoft.KeyVault.CertificateNewVersionCreated` | `CertificateNearExpiry`, `CertificateExpired` |

Events are only raised for **new versions**. Object deletion is not covered — see [Known Limitations](#known-limitations).

---

## Required Permissions

The Function's **system-assigned Managed Identity** requires the following RBAC assignments (provisioned automatically by the Bicep template):

| Vault  | Role                          | Covers                                |
| ------ | ----------------------------- | ------------------------------------- |
| Source | Key Vault Secrets User        | Read secrets and certificate PFX data |
| Source | Key Vault Certificate User    | List and read certificates            |
| Target | Key Vault Secrets Officer     | Create/update secrets                 |
| Target | Key Vault Certificate Officer | Import certificates                   |

---

## Known Limitations

| Limitation                                | Detail                                                                                                                                                      |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Non-exportable certificates               | If the certificate's private key is HSM-backed and non-exportable, only the public certificate (DER/CER) can be copied — the full PFX cannot be replicated. |
| Object deletion not synced                | Event Grid does not emit events for deletion. Deletion sync requires a separate reconciliation mechanism (e.g. scheduled job or Monitor alert).             |
| At-least-once delivery                    | Event Grid guarantees at-least-once delivery. The Function is designed to be idempotent — importing the same version twice does not cause errors.           |
| No cross-subscription network restriction | The Managed Identity approach works across subscriptions, but private endpoint configurations on source or target vaults must allow Function App egress.    |
| Latency                                   | Near-real-time — typically seconds to low minutes, depending on Event Grid delivery SLA and Function cold-start.                                            |

---

## Folder Structure

| Path                                       | Description                                                        |
| ------------------------------------------ | ------------------------------------------------------------------ |
| `App/`                                     | Azure Functions app (PowerShell)                                   |
| `App/Modules/KvReplication.psm1`           | Shared replication, retry, and logging helpers                     |
| `App/Replicate{Secret\|Certificate}/`     | Event-driven replication functions (one per object type)           |
| `App/SyncAll/`                             | Timer-triggered full-sync and reconciliation function              |
| `App/HealthCheck/`                         | HTTP health check endpoint (`GET /api/health`)                     |
| `Infrastructure/`                          | Bicep infrastructure templates                                     |
| `Infrastructure/main.bicep`                | Main orchestrator — deploys all resources                          |
| `Infrastructure/main.bicepparam`           | Default parameters (West Europe → Sweden Central)                  |
| `Infrastructure/modules/`                  | Bicep modules: keyvault, functionapp, eventgrid, appinsights, rbac |
| `Tests/`                                   | End-to-end test suite                                              |
| `Tests/Deploy-TestEnvironment.ps1`         | Deploys an isolated test environment and writes `tests.env.json`   |
| `Tests/Remove-TestEnvironment.ps1`         | Tears down the test resource group                                 |
| `Tests/Test-Replication.Tests.ps1`         | Pester v5 regression tests                                         |
| `Tests/infra/`                             | Bicep parameters for the test environment                          |
| `.github/workflows/ci.yml`                 | GitHub Actions CI/CD pipeline                                      |
| `Install-Prerequisites.ps1`                | Cross-platform prerequisites installer                             |

---

## Background: Why This Pattern

Azure Key Vault has no native mechanism for active cross-region or cross-geography replication of secrets or certificates. The table below summarises why the Azure Function + Event Grid pattern is the only viable option:

### Secrets and Certificates

| Option                          | Cross-geography              | Auto-sync                | Verdict                       |
| ------------------------------- | ---------------------------- | ------------------------ | ----------------------------- |
| Native KV geo-replication       | Paired region only           | Yes (DR/failover only)   | Not applicable                |
| KV Backup / Restore cmdlets     | **No** — same geography only | No (point-in-time)       | Not applicable                |
| Azure Backup service            | N/A                          | N/A                      | Not available for KV objects  |
| **Azure Function + Event Grid** | **Yes**                      | **Yes (near real-time)** | **Recommended**               |

### Why the native backup/restore cmdlets do not work cross-geography

`Restore-AzKeyVaultCertificate` has a hard platform constraint:

> _"The key vault must use the **same subscription** and be in an Azure region in the **same geography**."_  
> — [Microsoft Docs](https://learn.microsoft.com/powershell/module/az.keyvault/restore-azkeyvaultcertificate)

Backups are also point-in-time encrypted blobs that cannot be decrypted outside of Azure, and they do not auto-sync.

### Why the secret endpoint is used for certificates

Key Vault stores every certificate as a secret internally in base64-encoded PFX format. Accessing the secret endpoint retrieves the full certificate including the private key — as long as the caller has `secrets/get` permission. This avoids needing a separate export step and is the canonical cross-region copy pattern cited in the [official Event Grid tutorial](https://learn.microsoft.com/azure/key-vault/general/event-grid-tutorial).

### Related Microsoft samples and references

| Reference                                                                                                                                       | What it covers                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| [Receive and respond to KV notifications with Event Grid](https://learn.microsoft.com/azure/key-vault/general/event-grid-tutorial)              | End-to-end tutorial: KV Event Grid → PowerShell webhook. Closest official example to the replication flow.       |
| [Automate secret rotation — single credential](https://learn.microsoft.com/azure/key-vault/secrets/tutorial-rotation)                           | Event Grid `SecretNearExpiry` → Azure Function (PowerShell). Shows the function trigger + KV read/write pattern. |
| [Azure-Samples/KeyVault-Rotation-StorageAccountKey-PowerShell](https://github.com/Azure-Samples/KeyVault-Rotation-StorageAccountKey-PowerShell) | Official GitHub sample: deployable PowerShell Function App triggered by KV Event Grid events.                    |

---

## References

- [Monitoring Key Vault with Azure Event Grid](https://learn.microsoft.com/azure/key-vault/general/event-grid-overview)
- [Azure Key Vault as Event Grid source — event schema](https://learn.microsoft.com/azure/event-grid/event-schema-key-vault)
- [Reliability in Azure Key Vault — custom multi-region solutions](https://learn.microsoft.com/azure/reliability/reliability-key-vault#resilience-to-region-wide-failures)
- [Azure Key Vault backup and restore — limitations](https://learn.microsoft.com/azure/key-vault/general/backup#limitations)
- [Restore-AzKeyVaultCertificate](https://learn.microsoft.com/powershell/module/az.keyvault/restore-azkeyvaultcertificate)
- [Import-AzKeyVaultCertificate](https://learn.microsoft.com/powershell/module/az.keyvault/import-azkeyvaultcertificate)


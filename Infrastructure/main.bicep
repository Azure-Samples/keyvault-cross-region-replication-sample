// main.bicep — Orchestrates all resources for the Key Vault Cross-Region Replication sample.
//
// Deploys:
//   • Source Key Vault (current resource group location)
//   • One or more target Key Vaults (configurable locations)
//   • Azure Function App (PowerShell, Consumption plan)
//   • Event Grid System Topic + 2 subscriptions (Secret, Certificate)
//   • Application Insights + Log Analytics + alert rules
//   • RBAC assignments for the Function App's Managed Identity

targetScope = 'resourceGroup'

@description('Azure region for the source Key Vault and Function App.')
param location string = resourceGroup().location

@description('Name of the source Key Vault.')
param sourceKeyVaultName string

@description('Names of the target Key Vaults (one per target region).')
param targetKeyVaultNames array

@description('Azure regions for the target Key Vaults. Must match the length of targetKeyVaultNames.')
param targetLocations array

@description('Name of the Function App.')
param functionAppName string

@description('Name of the Storage Account used by the Function App.')
param storageAccountName string

@description('Name of the Application Insights resource.')
param appInsightsName string

@description('Name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string

@description('Timer cron expression for the full-sync reconciliation function. Default: every 6 hours.')
param syncSchedule string = '0 0 */6 * * *'

@description('Optional email address to receive replication failure alerts.')
param alertEmailAddress string = ''

@description('When false, skips Event Grid subscription deployment. Set to false on first deploy before function code is published.')
param deployEventGrid bool = true

// ── Source Key Vault ──────────────────────────────────────────────────────────
module sourceKv 'modules/keyvault.bicep' = {
    name: 'sourceKv'
    params: {
        name:     sourceKeyVaultName
        location: location
    }
}

// ── Target Key Vaults ─────────────────────────────────────────────────────────
module targetKvs 'modules/keyvault.bicep' = [for (kvName, i) in targetKeyVaultNames: {
    name: 'targetKv-${i}'
    params: {
        name:     kvName
        location: targetLocations[i]
    }
}]

// ── Monitoring ────────────────────────────────────────────────────────────────
module monitoring 'modules/appinsights.bicep' = {
    name: 'monitoring'
    params: {
        name:                       appInsightsName
        location:                   location
        logAnalyticsWorkspaceName:  logAnalyticsWorkspaceName
        alertEmailAddress:          alertEmailAddress
    }
}

// ── Function App ──────────────────────────────────────────────────────────────
module funcApp 'modules/functionapp.bicep' = {
    name: 'functionApp'
    params: {
        name:                        functionAppName
        location:                    location
        storageAccountName:          storageAccountName
        appInsightsConnectionString: monitoring.outputs.connectionString
        sourceKeyVaultName:          sourceKeyVaultName
        targetKeyVaultNames:         targetKeyVaultNames
        syncSchedule:                syncSchedule
    }
    dependsOn: [ sourceKv ]
}

// ── RBAC ──────────────────────────────────────────────────────────────────────
module rbac 'modules/rbac.bicep' = {
    name: 'rbac'
    params: {
        functionAppPrincipalId: funcApp.outputs.principalId
        sourceKeyVaultName:     sourceKeyVaultName
        targetKeyVaultNames:    targetKeyVaultNames
    }
    dependsOn: [ sourceKv, targetKvs ]
}

// ── Event Grid ────────────────────────────────────────────────────────────────
// Deployed in a second pass (after func publish) because Event Grid validates
// the function endpoint during subscription creation.
module eventGrid 'modules/eventgrid.bicep' = if (deployEventGrid) {
    name: 'eventGrid'
    params: {
        sourceKeyVaultName: sourceKeyVaultName
        sourceKeyVaultId:   sourceKv.outputs.id
        functionAppId:      funcApp.outputs.functionAppId
        location:           location
    }
    dependsOn: [ rbac ]
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output functionAppName    string = funcApp.outputs.functionAppName
output sourceKeyVaultUri  string = sourceKv.outputs.uri
output appInsightsName    string = appInsightsName

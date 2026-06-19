// modules/functionapp.bicep — Storage Account, Consumption hosting plan, and PowerShell Function App.

param name string
param location string
param storageAccountName string
param appInsightsConnectionString string
param sourceKeyVaultName string
param targetKeyVaultNames array
param syncSchedule string = '0 0 */6 * * *'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
    name: storageAccountName
    location: location
    sku: { name: 'Standard_LRS' }
    kind: 'StorageV2'
    properties: {
        minimumTlsVersion: 'TLS1_2'
        allowBlobPublicAccess: false
        supportsHttpsTrafficOnly: true
        // Shared-key access is blocked by subscription policy; use identity-based connections.
        allowSharedKeyAccess: false
    }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
    name: '${name}-plan'
    location: location
    sku: {
        name: 'Y1'
        tier: 'Dynamic'
    }
    properties: {}
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
    name: name
    location: location
    kind: 'functionapp'
    identity: {
        type: 'SystemAssigned'
    }
    properties: {
        serverFarmId: hostingPlan.id
        httpsOnly: true
        siteConfig: {
            ftpsState: 'Disabled'
            minTlsVersion: '1.2'
            powerShellVersion: '7.4'
            appSettings: [
                // Identity-based storage (shared-key access is blocked by subscription policy)
                { name: 'AzureWebJobsStorage__accountName',  value: storageAccount.name }
                { name: 'AzureWebJobsStorage__credential',   value: 'managedidentity' }
                // Run from package — avoids Azure Files content share (also uses identity)
                { name: 'WEBSITE_RUN_FROM_PACKAGE',          value: '1' }
                { name: 'FUNCTIONS_EXTENSION_VERSION',       value: '~4' }
                { name: 'FUNCTIONS_WORKER_RUNTIME',          value: 'powershell' }
                { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
                { name: 'SOURCE_KEYVAULT_NAME',   value: sourceKeyVaultName }
                { name: 'TARGET_KEYVAULT_NAMES',  value: join(targetKeyVaultNames, ',') }
                { name: 'SyncSchedule',           value: syncSchedule }
            ]
        }
    }
}

output functionAppId   string = functionApp.id
output functionAppName string = functionApp.name
output principalId     string = functionApp.identity.principalId

// ── Storage RBAC for identity-based AzureWebJobsStorage ──────────────────────
// Storage Blob Data Owner  — run-from-package blob read + webjobs blobs
// Storage Queue Data Contributor — webjobs queues
// Storage Table Data Contributor — webjobs tables
var storageBlobDataOwner        = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageQueueDataContributor = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributor = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

resource blobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name:  guid(storageAccount.id, functionApp.name, storageBlobDataOwner)
    scope: storageAccount
    properties: {
        roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwner)
        principalId:   functionApp.identity.principalId
        principalType: 'ServicePrincipal'
    }
}

resource queueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name:  guid(storageAccount.id, functionApp.name, storageQueueDataContributor)
    scope: storageAccount
    properties: {
        roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributor)
        principalId:   functionApp.identity.principalId
        principalType: 'ServicePrincipal'
    }
}

resource tableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name:  guid(storageAccount.id, functionApp.name, storageTableDataContributor)
    scope: storageAccount
    properties: {
        roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributor)
        principalId:   functionApp.identity.principalId
        principalType: 'ServicePrincipal'
    }
}

// modules/keyvault.bicep — Deploys a single Azure Key Vault with RBAC authorisation.

param name string
param location string
param skuName string = 'standard'
param softDeleteRetentionInDays int = 7

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
    name: name
    location: location
    properties: {
        sku: {
            family: 'A'
            name: skuName
        }
        tenantId: subscription().tenantId
        enableRbacAuthorization: true
        enableSoftDelete: true
        softDeleteRetentionInDays: softDeleteRetentionInDays
        enabledForDeployment: false
        enabledForDiskEncryption: false
        enabledForTemplateDeployment: false
        publicNetworkAccess: 'Enabled'
    }
}

output id   string = keyVault.id
output name string = keyVault.name
output uri  string = keyVault.properties.vaultUri

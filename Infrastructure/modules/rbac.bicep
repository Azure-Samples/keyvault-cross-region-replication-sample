// modules/rbac.bicep — Assigns the minimum required RBAC roles to the Function App's
// system-assigned Managed Identity on the source and target Key Vaults.

param functionAppPrincipalId string
param sourceKeyVaultName     string
param targetKeyVaultNames    array

// ── Built-in role definition IDs ────────────────────────────────────────────
var roleIds = {
    // Source vault — read access
    keyVaultSecretsUser      : '4633458b-17de-408a-b874-0445c86b69e6'  // secrets/get + list
    keyVaultCertificateUser  : 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'  // certificates/get + list

    // Target vaults — write access to create/import objects
    keyVaultSecretsOfficer   : 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'  // secrets full CRUD
    keyVaultCertOfficer      : 'a4417e6f-fecd-4de8-b567-7b0420556985'  // certificates full CRUD
}

// ── Source vault ─────────────────────────────────────────────────────────────
resource sourceKv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
    name: sourceKeyVaultName
}

resource sourceSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name: guid(sourceKv.id, functionAppPrincipalId, roleIds.keyVaultSecretsUser)
    scope: sourceKv
    properties: {
        roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultSecretsUser)
        principalId:   functionAppPrincipalId
        principalType: 'ServicePrincipal'
    }
}

resource sourceCertUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name: guid(sourceKv.id, functionAppPrincipalId, roleIds.keyVaultCertificateUser)
    scope: sourceKv
    properties: {
        roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultCertificateUser)
        principalId:   functionAppPrincipalId
        principalType: 'ServicePrincipal'
    }
}

// ── Target vaults ─────────────────────────────────────────────────────────────
resource targetKvs 'Microsoft.KeyVault/vaults@2023-07-01' existing = [for kvName in targetKeyVaultNames: {
    name: kvName
}]

resource targetSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (kvName, i) in targetKeyVaultNames: {
    name: guid(targetKvs[i].id, functionAppPrincipalId, roleIds.keyVaultSecretsOfficer)
    scope: targetKvs[i]
    properties: {
        roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultSecretsOfficer)
        principalId:   functionAppPrincipalId
        principalType: 'ServicePrincipal'
    }
}]

resource targetCertOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (kvName, i) in targetKeyVaultNames: {
    name: guid(targetKvs[i].id, functionAppPrincipalId, roleIds.keyVaultCertOfficer)
    scope: targetKvs[i]
    properties: {
        roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultCertOfficer)
        principalId:   functionAppPrincipalId
        principalType: 'ServicePrincipal'
    }
}]

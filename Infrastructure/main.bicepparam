// main.bicepparam — Default parameters for West Europe → Sweden Central deployment.
// Adjust names and regions to match your environment.

using './main.bicep'

param sourceKeyVaultName       = 'kv-replication-source'
param targetKeyVaultNames      = [ 'kv-replication-target-sc' ]
param targetLocations          = [ 'swedencentral' ]
param functionAppName          = 'func-kv-replication'
param storageAccountName       = 'stkvreplication'
param appInsightsName          = 'ai-kv-replication'
param logAnalyticsWorkspaceName = 'la-kv-replication'
param alertEmailAddress        = ''   // Set to your ops email to enable failure alerts

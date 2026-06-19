// modules/eventgrid.bicep — Event Grid System Topic on the source Key Vault
// and two event subscriptions (Secret and Certificate NewVersionCreated).

param sourceKeyVaultName string
param sourceKeyVaultId   string
param functionAppId      string
param location           string

resource systemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
    name: '${sourceKeyVaultName}-events'
    location: location
    properties: {
        source:    sourceKeyVaultId
        topicType: 'Microsoft.KeyVault.vaults'
    }
}

resource secretSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
    parent: systemTopic
    name: 'kv-secret-replication'
    properties: {
        destination: {
            endpointType: 'AzureFunction'
            properties: {
                resourceId:                  '${functionAppId}/functions/ReplicateSecret'
                maxEventsPerBatch:           1
                preferredBatchSizeInKilobytes: 64
            }
        }
        filter: {
            includedEventTypes: [ 'Microsoft.KeyVault.SecretNewVersionCreated' ]
        }
        retryPolicy: {
            maxDeliveryAttempts:      30
            eventTimeToLiveInMinutes: 1440
        }
    }
}

resource certificateSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
    parent: systemTopic
    name: 'kv-certificate-replication'
    properties: {
        destination: {
            endpointType: 'AzureFunction'
            properties: {
                resourceId:                  '${functionAppId}/functions/ReplicateCertificate'
                maxEventsPerBatch:           1
                preferredBatchSizeInKilobytes: 64
            }
        }
        filter: {
            includedEventTypes: [ 'Microsoft.KeyVault.CertificateNewVersionCreated' ]
        }
        retryPolicy: {
            maxDeliveryAttempts:      30
            eventTimeToLiveInMinutes: 1440
        }
    }
}

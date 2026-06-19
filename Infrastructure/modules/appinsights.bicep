// modules/appinsights.bicep — Log Analytics workspace + Application Insights + alert rules.

param name string
param location string
param logAnalyticsWorkspaceName string
param alertEmailAddress string = ''

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
    name: logAnalyticsWorkspaceName
    location: location
    properties: {
        sku: { name: 'PerGB2018' }
        retentionInDays: 30
    }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
    name: name
    location: location
    kind: 'web'
    properties: {
        Application_Type: 'web'
        WorkspaceResourceId: logAnalytics.id
        RetentionInDays: 30
        DisableIpMasking: false
    }
}

// Action group — required even when no email is configured (alert rule references it)
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
    name: '${name}-alerts'
    location: 'global'
    properties: {
        groupShortName: 'KvRepAlert'
        enabled: true
        emailReceivers: empty(alertEmailAddress) ? [] : [
            {
                name: 'on-call'
                emailAddress: alertEmailAddress
                useCommonAlertSchema: true
            }
        ]
    }
}

// Alert: replication failures logged as errors in Application Insights
resource replicationFailureAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
    name: '${name}-replication-failures'
    location: location
    properties: {
        displayName: 'KV Replication — Function Errors'
        description: 'Fires when any replication function logs an error to Application Insights.'
        severity: 1
        enabled: true
        scopes: [ appInsights.id ]
        evaluationFrequency: 'PT5M'
        windowSize: 'PT15M'
        criteria: {
            allOf: [
                {
                    query: 'exceptions | where outerMessage has "Failed to replicate" | summarize AggregatedValue = count() by bin(timestamp, 5m)'
                    timeAggregation: 'Count'
                    operator: 'GreaterThan'
                    threshold: 0
                    failingPeriods: {
                        numberOfEvaluationPeriods: 1
                        minFailingPeriodsToAlert: 1
                    }
                }
            ]
        }
        autoMitigate: false
        actions: {
            actionGroups: [ actionGroup.id ]
        }
    }
}

// Alert: sync failures (thrown by SyncAll function)
resource syncFailureAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
    name: '${name}-sync-failures'
    location: location
    properties: {
        displayName: 'KV Replication — Sync Failures'
        description: 'Fires when the periodic full-sync function reports failures.'
        severity: 2
        enabled: true
        scopes: [ appInsights.id ]
        evaluationFrequency: 'PT15M'
        windowSize: 'PT30M'
        criteria: {
            allOf: [
                {
                    query: 'exceptions | where outerMessage has "Full sync completed with" | summarize AggregatedValue = count() by bin(timestamp, 15m)'
                    timeAggregation: 'Count'
                    operator: 'GreaterThan'
                    threshold: 0
                    failingPeriods: {
                        numberOfEvaluationPeriods: 1
                        minFailingPeriodsToAlert: 1
                    }
                }
            ]
        }
        autoMitigate: false
        actions: {
            actionGroups: [ actionGroup.id ]
        }
    }
}

output id               string = appInsights.id
output connectionString string = appInsights.properties.ConnectionString
output instrumentationKey string = appInsights.properties.InstrumentationKey

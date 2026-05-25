param location string
param environment string
param workload string
param tags object

var suffix = '${workload}-${environment}'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${suffix}-ops'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'trdops'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
  }
}

resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'ma-${suffix}-critical-platform-errors'
  location: 'global'
  tags: tags
  properties: {
    description: 'Placeholder alert for critical platform errors. Add scoped AKS/API resources after deployment.'
    severity: 2
    enabled: false
    scopes: [law.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: []
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

output logAnalyticsWorkspaceId string = law.id
output logAnalyticsWorkspaceName string = law.name
output applicationInsightsId string = appi.id
output applicationInsightsConnectionString string = appi.properties.ConnectionString

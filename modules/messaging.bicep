param location string
param environment string
param workload string
param tags object
param logAnalyticsWorkspaceId string
param privateEndpointSubnetId string
param privateDnsZoneIds object

var suffix = '${workload}-${environment}'

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'sb-${suffix}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
    capacity: 1
  }
  properties: {
    zoneRedundant: true
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: '1.2'
    disableLocalAuth: true
  }
}

var topics = [
  'order-events'
  'execution-reports'
  'reconciliation-events'
  'wallet-events'
  'audit-events'
]

resource sbTopics 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = [for topicName in topics: {
  parent: sb
  name: topicName
  properties: {
    defaultMessageTimeToLive: 'P14D'
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    enableExpress: false
    enablePartitioning: false
    requiresDuplicateDetection: true
    supportOrdering: true
  }
}]

resource outboxQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: sb
  name: 'outbox-dispatch'
  properties: {
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P7D'
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    requiresDuplicateDetection: true
  }
}

resource eh 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: 'evhns-${suffix}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 2
  }
  properties: {
    isAutoInflateEnabled: true
    maximumThroughputUnits: 10
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: '1.2'
    disableLocalAuth: true
  }
}

var eventHubs = [
  { name: 'market-data'; partitions: 16; retention: 3 }
  { name: 'prices'; partitions: 8; retention: 3 }
  { name: 'orders-stream'; partitions: 8; retention: 7 }
  { name: 'blockchain-confirmations'; partitions: 8; retention: 7 }
]

resource hubs 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = [for hub in eventHubs: {
  parent: eh
  name: hub.name
  properties: {
    partitionCount: hub.partitions
    retentionDescription: {
      cleanupPolicy: 'Delete'
      retentionTimeInHours: hub.retention * 24
    }
  }
}]

resource sbPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${sb.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'servicebus-privatelink'
        properties: {
          privateLinkServiceId: sb.id
          groupIds: ['namespace']
        }
      }
    ]
  }
}

resource sbDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: sbPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'servicebus', properties: { privateDnsZoneId: privateDnsZoneIds.serviceBus } }
    ]
  }
}

resource ehPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${eh.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'eventhub-privatelink'
        properties: {
          privateLinkServiceId: eh.id
          groupIds: ['namespace']
        }
      }
    ]
  }
}

resource ehDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: ehPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'servicebus-compatible', properties: { privateDnsZoneId: privateDnsZoneIds.serviceBus } }
    ]
  }
}

resource sbDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${sb.name}'
  scope: sb
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [ { category: 'OperationalLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

resource ehDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${eh.name}'
  scope: eh
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [ { category: 'ArchiveLogs', enabled: true } { category: 'OperationalLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

output serviceBusNamespaceId string = sb.id
output eventHubNamespaceId string = eh.id

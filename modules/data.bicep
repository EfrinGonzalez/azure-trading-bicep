param location string
param environment string
param workload string
param tags object
param logAnalyticsWorkspaceId string
param privateEndpointSubnetId string
param privateDnsZoneIds object

@secure()
param sqlAdminPassword string = newGuid()

var suffix = '${workload}-${environment}'
var unique = uniqueString(resourceGroup().id)

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: 'sql-${suffix}-${unique}'
  location: location
  tags: tags
  properties: {
    administratorLogin: 'sqladminuser'
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    restrictOutboundNetworkAccess: 'Enabled'
  }
}

resource tradingDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: 'sqldb-${suffix}-core'
  location: location
  tags: tags
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368
    zoneRedundant: false
  }
}

resource sqlPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${sqlServer.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'sql-privatelink'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: ['sqlServer']
        }
      }
    ]
  }
}

resource sqlDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: sqlPe
  name: 'default'
  properties: { privateDnsZoneConfigs: [ { name: 'sql', properties: { privateDnsZoneId: privateDnsZoneIds.sql } } ] }
}

resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: 'redis-${suffix}-${unique}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'Premium', family: 'P', capacity: 1 }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

resource redisPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${redis.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      { name: 'redis-privatelink', properties: { privateLinkServiceId: redis.id, groupIds: ['redisCache'] } }
    ]
  }
}

resource redisDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: redisPe
  name: 'default'
  properties: { privateDnsZoneConfigs: [ { name: 'redis', properties: { privateDnsZoneId: privateDnsZoneIds.redis } } ] }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${workload}${environment}${unique}'
  location: location
  tags: tags
  sku: { name: 'Standard_ZRS' }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: { blob: { enabled: true } file: { enabled: true } }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource storageBlobPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${storage.name}-blob'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [ { name: 'blob', properties: { privateLinkServiceId: storage.id, groupIds: ['blob'] } } ]
  }
}
resource storageDfsPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${storage.name}-dfs'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [ { name: 'dfs', properties: { privateLinkServiceId: storage.id, groupIds: ['dfs'] } } ]
  }
}

resource blobDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: storageBlobPe
  name: 'default'
  properties: { privateDnsZoneConfigs: [ { name: 'blob', properties: { privateDnsZoneId: privateDnsZoneIds.blob } } ] }
}
resource dfsDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: storageDfsPe
  name: 'default'
  properties: { privateDnsZoneConfigs: [ { name: 'dfs', properties: { privateDnsZoneId: privateDnsZoneIds.dfs } } ] }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: 'cosmos-${suffix}-${unique}'
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    enableAutomaticFailover: true
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [ { locationName: location, failoverPriority: 0, isZoneRedundant: false } ]
  }
}

resource sqlDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${sqlServer.name}'
  scope: sqlServer
  properties: { workspaceId: logAnalyticsWorkspaceId, logs: [ { category: 'SQLSecurityAuditEvents', enabled: true } ], metrics: [ { category: 'AllMetrics', enabled: true } ] }
}

output sqlServerId string = sqlServer.id
output sqlDatabaseId string = tradingDb.id
output redisId string = redis.id
output dataLakeStorageId string = storage.id
output cosmosDbId string = cosmos.id

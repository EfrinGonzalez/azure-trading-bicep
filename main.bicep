targetScope = 'subscription'

@description('Azure region for all resources.')
param location string = 'westeurope'

@description('Deployment environment name.')
param environment string = 'prod'

@description('Short workload name used in resource naming.')
param workload string = 'trading'

@description('Optional object id of the platform/security administrator group for Key Vault access policies / RBAC assignments.')
param adminObjectId string = ''

@description('CIDR prefixes for the hub and spoke networks.')
param addressSpaces object = {
  hub: '10.10.0.0/16'
  trading: '10.20.0.0/16'
  data: '10.30.0.0/16'
  security: '10.40.0.0/16'
}

@description('Common tags applied to all resources.')
param tags object = {
  workload: 'regulated-crypto-trading-platform'
  environment: 'prod'
  owner: 'architecture'
  dataClassification: 'confidential'
  managedBy: 'bicep'
}

var rgNames = {
  network: 'rg-${workload}-${environment}-network'
  platform: 'rg-${workload}-${environment}-platform'
  data: 'rg-${workload}-${environment}-data'
  security: 'rg-${workload}-${environment}-security'
  observability: 'rg-${workload}-${environment}-observability'
}

resource rgNetwork 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgNames.network
  location: location
  tags: tags
}

resource rgPlatform 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgNames.platform
  location: location
  tags: tags
}

resource rgData 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgNames.data
  location: location
  tags: tags
}

resource rgSecurity 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgNames.security
  location: location
  tags: tags
}

resource rgObservability 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgNames.observability
  location: location
  tags: tags
}

module observability 'modules/observability.bicep' = {
  name: 'observability-${environment}'
  scope: rgObservability
  params: {
    location: location
    environment: environment
    workload: workload
    tags: tags
  }
  dependsOn: [
    rgObservability
  ]
}

module network 'modules/network.bicep' = {
  name: 'network-${environment}'
  scope: rgNetwork
  params: {
    location: location
    environment: environment
    workload: workload
    tags: tags
    addressSpaces: addressSpaces
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
  }
  dependsOn: [
    rgNetwork
  ]
}

module security 'modules/security.bicep' = {
  name: 'security-${environment}'
  scope: rgSecurity
  params: {
    location: location
    environment: environment
    workload: workload
    tags: tags
    adminObjectId: adminObjectId
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointSubnetId: network.outputs.securityPrivateEndpointSubnetId
  }
  dependsOn: [
    rgSecurity
  ]
}

module data 'modules/data.bicep' = {
  name: 'data-${environment}'
  scope: rgData
  params: {
    location: location
    environment: environment
    workload: workload
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointSubnetId: network.outputs.dataPrivateEndpointSubnetId
    privateDnsZoneIds: network.outputs.privateDnsZoneIds
  }
  dependsOn: [
    rgData
  ]
}

module messaging 'modules/messaging.bicep' = {
  name: 'messaging-${environment}'
  scope: rgPlatform
  params: {
    location: location
    environment: environment
    workload: workload
    tags: tags
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    privateEndpointSubnetId: network.outputs.tradingPrivateEndpointSubnetId
    privateDnsZoneIds: network.outputs.privateDnsZoneIds
  }
  dependsOn: [
    rgPlatform
  ]
}

module aks 'modules/aks.bicep' = {
  name: 'aks-${environment}'
  scope: rgPlatform
  params: {
    location: location
    environment: environment
    workload: workload
    tags: tags
    aksSubnetId: network.outputs.aksSubnetId
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
    applicationInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    keyVaultId: security.outputs.keyVaultId
    keyVaultName: security.outputs.keyVaultName
    privateEndpointSubnetId: network.outputs.tradingPrivateEndpointSubnetId
    privateDnsZoneIds: network.outputs.privateDnsZoneIds
  }
  dependsOn: [
    rgPlatform
  ]
}

output resourceGroups object = rgNames
output hubVnetId string = network.outputs.hubVnetId
output tradingVnetId string = network.outputs.tradingVnetId
output aksClusterName string = aks.outputs.aksClusterName
output keyVaultName string = security.outputs.keyVaultName
output acrLoginServer string = aks.outputs.acrLoginServer

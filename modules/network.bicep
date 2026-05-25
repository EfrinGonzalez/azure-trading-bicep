param location string
param environment string
param workload string
param tags object
param addressSpaces object
param logAnalyticsWorkspaceId string

var suffix = '${workload}-${environment}'

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${suffix}-hub'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressSpaces.hub] }
    subnets: [
      { name: 'AzureFirewallSubnet', properties: { addressPrefix: '10.10.0.0/24' } }
      { name: 'GatewaySubnet', properties: { addressPrefix: '10.10.1.0/24' } }
      { name: 'AzureBastionSubnet', properties: { addressPrefix: '10.10.2.0/24' } }
      { name: 'snet-shared-private-endpoints', properties: { addressPrefix: '10.10.3.0/24', privateEndpointNetworkPolicies: 'Disabled' } }
    ]
  }
}

resource tradingVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${suffix}-trading'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressSpaces.trading] }
    subnets: [
      { name: 'snet-aks', properties: { addressPrefix: '10.20.0.0/22' } }
      { name: 'snet-api-management', properties: { addressPrefix: '10.20.4.0/24' } }
      { name: 'snet-private-endpoints', properties: { addressPrefix: '10.20.5.0/24', privateEndpointNetworkPolicies: 'Disabled' } }
    ]
  }
}

resource dataVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${suffix}-data'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressSpaces.data] }
    subnets: [
      { name: 'snet-data-private-endpoints', properties: { addressPrefix: '10.30.0.0/24', privateEndpointNetworkPolicies: 'Disabled' } }
      { name: 'snet-data-services', properties: { addressPrefix: '10.30.1.0/24' } }
    ]
  }
}

resource securityVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${suffix}-security'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [addressSpaces.security] }
    subnets: [
      { name: 'snet-security-private-endpoints', properties: { addressPrefix: '10.40.0.0/24', privateEndpointNetworkPolicies: 'Disabled' } }
      { name: 'snet-security-ops', properties: { addressPrefix: '10.40.1.0/24' } }
    ]
  }
}

resource fwPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${suffix}-azfw'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource fwPolicy 'Microsoft.Network/firewallPolicies@2023-11-01' = {
  name: 'afwp-${suffix}'
  location: location
  tags: tags
  properties: {
    threatIntelMode: 'Deny'
    dnsSettings: { enableProxy: true }
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
  name: 'afw-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'AZFW_VNet', tier: 'Standard' }
    firewallPolicy: { id: fwPolicy.id }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: { id: '${hubVnet.id}/subnets/AzureFirewallSubnet' }
          publicIPAddress: { id: fwPip.id }
        }
      }
    ]
  }
}

resource natPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${suffix}-nat'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nat 'Microsoft.Network/natGateways@2023-11-01' = {
  name: 'nat-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIpAddresses: [{ id: natPip.id }]
  }
}

resource rtSpokes 'Microsoft.Network/routeTables@2023-11-01' = {
  name: 'rt-${suffix}-spokes-to-firewall'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'default-to-azure-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

resource nsgAks 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${suffix}-aks'
  location: location
  tags: tags
  properties: { securityRules: [] }
}

resource peerHubToTrading 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hubVnet
  name: 'peer-hub-to-trading'
  properties: { remoteVirtualNetwork: { id: tradingVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true, allowGatewayTransit: true }
}
resource peerTradingToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: tradingVnet
  name: 'peer-trading-to-hub'
  properties: { remoteVirtualNetwork: { id: hubVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true, useRemoteGateways: false }
}
resource peerHubToData 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hubVnet
  name: 'peer-hub-to-data'
  properties: { remoteVirtualNetwork: { id: dataVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true }
}
resource peerDataToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: dataVnet
  name: 'peer-data-to-hub'
  properties: { remoteVirtualNetwork: { id: hubVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true }
}
resource peerHubToSecurity 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hubVnet
  name: 'peer-hub-to-security'
  properties: { remoteVirtualNetwork: { id: securityVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true }
}
resource peerSecurityToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: securityVnet
  name: 'peer-security-to-hub'
  properties: { remoteVirtualNetwork: { id: hubVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true }
}

var privateDnsZones = [
  'privatelink.vaultcore.azure.net'
  'privatelink.database.windows.net'
  'privatelink.redis.cache.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.dfs.core.windows.net'
  'privatelink.servicebus.windows.net'
  'privatelink.eventgrid.azure.net'
  'privatelink.azurecr.io'
  'privatelink.${location}.azmk8s.io'
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zoneName in privateDnsZones: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource dnsHubLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, i) in privateDnsZones: {
  parent: dnsZones[i]
  name: 'link-hub'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: hubVnet.id } }
}]

resource dnsTradingLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, i) in privateDnsZones: {
  parent: dnsZones[i]
  name: 'link-trading'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: tradingVnet.id } }
}]

resource dnsDataLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, i) in privateDnsZones: {
  parent: dnsZones[i]
  name: 'link-data'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: dataVnet.id } }
}]

resource dnsSecurityLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, i) in privateDnsZones: {
  parent: dnsZones[i]
  name: 'link-security'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: securityVnet.id } }
}]

resource fwDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${firewall.name}'
  scope: firewall
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AzureFirewallApplicationRule', enabled: true }
      { category: 'AzureFirewallNetworkRule', enabled: true }
      { category: 'AzureFirewallDnsProxy', enabled: true }
    ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

// VPN Gateway / ExpressRoute Gateway placeholder: GatewaySubnet is provisioned in hub VNet.
// Deploy VpnGateway or ExpressRouteGateway based on concrete connectivity requirements.

output hubVnetId string = hubVnet.id
output tradingVnetId string = tradingVnet.id
output dataVnetId string = dataVnet.id
output securityVnetId string = securityVnet.id
output aksSubnetId string = '${tradingVnet.id}/subnets/snet-aks'
output tradingPrivateEndpointSubnetId string = '${tradingVnet.id}/subnets/snet-private-endpoints'
output dataPrivateEndpointSubnetId string = '${dataVnet.id}/subnets/snet-data-private-endpoints'
output securityPrivateEndpointSubnetId string = '${securityVnet.id}/subnets/snet-security-private-endpoints'
output privateDnsZoneIds object = {
  keyVault: dnsZones[0].id
  sql: dnsZones[1].id
  redis: dnsZones[2].id
  blob: dnsZones[3].id
  dfs: dnsZones[4].id
  serviceBus: dnsZones[5].id
  eventGrid: dnsZones[6].id
  acr: dnsZones[7].id
  aks: dnsZones[8].id
}

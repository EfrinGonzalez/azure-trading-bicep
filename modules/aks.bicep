param location string
param environment string
param workload string
param tags object
param aksSubnetId string
param logAnalyticsWorkspaceId string
param applicationInsightsConnectionString string
param keyVaultId string
param keyVaultName string
param privateEndpointSubnetId string
param privateDnsZoneIds object

var suffix = '${workload}-${environment}'
var unique = uniqueString(resourceGroup().id)

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'acr${workload}${environment}${unique}'
  location: location
  tags: tags
  sku: { name: 'Premium' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: { status: 'enabled' }
      trustPolicy: { type: 'Notary', status: 'disabled' }
      retentionPolicy: { days: 30, status: 'enabled' }
    }
  }
}

resource acrPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${acr.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'acr-privatelink'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: ['registry']
        }
      }
    ]
  }
}

resource acrDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: acrPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'acr', properties: { privateDnsZoneId: privateDnsZoneIds.acr } }
    ]
  }
}

resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${suffix}-aks'
  location: location
  tags: tags
}

resource kubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${suffix}-kubelet'
  location: location
  tags: tags
}

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: 'aks-${suffix}'
  location: location
  tags: union(tags, {
    applicationInsightsConnectionString: applicationInsightsConnectionString
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: 'aks-${suffix}'
    kubernetesVersion: ''
    enableRBAC: true
    oidcIssuerProfile: { enabled: true }
    workloadIdentityProfile: { enabled: true }
    apiServerAccessProfile: {
      enablePrivateCluster: true
      enablePrivateClusterPublicFQDN: false
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      outboundType: 'userAssignedNATGateway'
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: 3
        vmSize: 'Standard_D4s_v5'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        availabilityZones: ['1', '2', '3']
        enableAutoScaling: true
        minCount: 3
        maxCount: 6
        vnetSubnetID: aksSubnetId
        osDiskSizeGB: 128
        maxPods: 50
      }
      {
        name: 'trading'
        mode: 'User'
        count: 3
        vmSize: 'Standard_D8s_v5'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        availabilityZones: ['1', '2', '3']
        enableAutoScaling: true
        minCount: 3
        maxCount: 12
        vnetSubnetID: aksSubnetId
        osDiskSizeGB: 128
        maxPods: 50
        nodeLabels: {
          workload: 'trading-services'
        }
      }
    ]
    autoScalerProfile: {
      scanInterval: '10s'
      scaleDownDelayAfterAdd: '10m'
    }
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
        securityMonitoring: { enabled: true }
      }
      workloadIdentity: { enabled: true }
    }
  }
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultId, aks.id, 'KeyVaultSecretsUser')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: aksIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: 'apim-${suffix}-${unique}'
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: 'platform-ops@example.invalid'
    publisherName: 'Trading Platform Operations'
    publicNetworkAccess: 'Disabled'
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: replace(aksSubnetId, 'snet-aks', 'snet-api-management')
    }
  }
}

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: 'waf-${suffix}'
  location: 'global'
  tags: tags
  sku: { name: 'Premium_AzureFrontDoor' }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleSetAction: 'Block'
        }
      ]
    }
  }
}

resource afdProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: 'afd-${suffix}-${unique}'
  location: 'global'
  tags: tags
  sku: { name: 'Premium_AzureFrontDoor' }
}

resource aksDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${aks.name}'
  scope: aks
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'kube-apiserver', enabled: true }
      { category: 'kube-audit', enabled: true }
      { category: 'kube-controller-manager', enabled: true }
      { category: 'cluster-autoscaler', enabled: true }
    ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

output aksClusterName string = aks.name
output aksClusterId string = aks.id
output acrLoginServer string = acr.properties.loginServer
output apiManagementName string = apim.name
output frontDoorProfileId string = afdProfile.id
output keyVaultNameForCsi string = keyVaultName

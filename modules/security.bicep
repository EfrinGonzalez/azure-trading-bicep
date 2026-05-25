param location string
param environment string
param workload string
param tags object
param adminObjectId string = ''
param logAnalyticsWorkspaceId string
param privateEndpointSubnetId string

var suffix = '${workload}-${environment}'
var tenantId = subscription().tenantId

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${suffix}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'premium'
    }
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource kvDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${kv.name}'
  scope: kv
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AuditEvent', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

resource kvPe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${kv.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'kv-privatelink'
        properties: {
          privateLinkServiceId: kv.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

// Placeholder for stricter custody-grade key management. Managed HSM deployment normally requires
// dedicated capacity, private endpoint DNS, role assignments and operational ceremony.
resource managedHsm 'Microsoft.KeyVault/managedHSMs@2023-07-01' = {
  name: 'mhsm-${suffix}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    family: 'B'
    name: 'Standard_B1'
  }
  properties: {
    tenantId: tenantId
    initialAdminObjectIds: empty(adminObjectId) ? [] : [adminObjectId]
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

// Defender for Cloud / regulatory policy assignments should normally be managed at management group scope.
output keyVaultId string = kv.id
output keyVaultName string = kv.name
output managedHsmId string = managedHsm.id

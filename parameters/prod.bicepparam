using '../main.bicep'

param location = 'westeurope'
param environment = 'prod'
param workload = 'trading'
param adminObjectId = ''
param addressSpaces = {
  hub: '10.10.0.0/16'
  trading: '10.20.0.0/16'
  data: '10.30.0.0/16'
  security: '10.40.0.0/16'
}
param tags = {
  workload: 'regulated-crypto-trading-platform'
  environment: 'prod'
  owner: 'architecture'
  dataClassification: 'confidential'
  managedBy: 'bicep'
  criticality: 'tier-0-trading'
}

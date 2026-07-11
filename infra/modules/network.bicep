// Network: VNet + 3 subnets (Container Apps, private endpoints, Postgres delegation)
// and the private DNS zones used by Key Vault, AI Services, and Postgres.

param vnetName string
param location string

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.20.0.0/16'] }
    subnets: [
      {
        name: 'aca'
        properties: {
          addressPrefix: '10.20.0.0/23' // /23 required for Container Apps env
          // Workload-profiles Container Apps environments require this delegation.
          delegations: [
            {
              name: 'aca-delegation'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
      {
        name: 'pe'
        properties: {
          addressPrefix: '10.20.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'postgres'
        properties: {
          addressPrefix: '10.20.3.0/24'
          delegations: [
            {
              name: 'pgdelegation'
              properties: { serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers' }
            }
          ]
        }
      }
    ]
  }
}

resource dnsKv 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}
// An AI Services 'account' private endpoint resolves across multiple zones.
// We call the OpenAI endpoint (.openai.azure.com), so that zone is REQUIRED;
// the others are included for completeness (cognitiveservices, services.ai).
var aiZoneNames = [
  'privatelink.openai.azure.com'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.services.ai.azure.com'
]
resource dnsAi 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in aiZoneNames: {
  name: z
  location: 'global'
}]
resource dnsPg 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
}

resource linkKv 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsKv
  name: 'kv-link'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}
resource linkAi 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (z, i) in aiZoneNames: {
  parent: dnsAi[i]
  name: 'ai-link'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}]
resource linkPg 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsPg
  name: 'pg-link'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}

output vnetId string = vnet.id
output acaSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'aca')
output peSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'pe')
output pgSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'postgres')
output dnsKvId string = dnsKv.id
output dnsAiZoneIds array = [for (z, i) in aiZoneNames: dnsAi[i].id]
output dnsPgId string = dnsPg.id

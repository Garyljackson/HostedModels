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
        properties: { addressPrefix: '10.20.0.0/23' } // /23 required for Container Apps env
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
resource dnsAi 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.services.ai.azure.com'
  location: 'global'
}
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
resource linkAi 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsAi
  name: 'ai-link'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnet.id } }
}
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
output dnsAiId string = dnsAi.id
output dnsPgId string = dnsPg.id

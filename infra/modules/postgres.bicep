// PostgreSQL Flexible Server (private, via delegated subnet) + litellm database.

param name string
param location string
param delegatedSubnetId string
param dnsZoneId string
param adminLogin string
@secure()
param adminPassword string

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: { storageSizeGB: 32 }
    network: {
      delegatedSubnetResourceId: delegatedSubnetId
      privateDnsZoneArmResourceId: dnsZoneId
    }
    highAvailability: { mode: 'Disabled' } // PoC: single instance
  }
}

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: 'litellm'
  properties: { charset: 'UTF8', collation: 'en_US.utf8' }
}

output fqdn string = pg.properties.fullyQualifiedDomainName
output name string = pg.name

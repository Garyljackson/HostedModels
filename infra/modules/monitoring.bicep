// Log Analytics workspace (metadata-only operational logs).

param name string
param location string
param retentionInDays int = 30

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionInDays
  }
}

output name string = law.name
output id string = law.id
output customerId string = law.properties.customerId

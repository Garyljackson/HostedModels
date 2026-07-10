// AI Services account (private) + GPT-class deployment + private endpoint.
// NOTE: Qwen3-Coder-Next (open-weight) is often a SERVERLESS deployment
// (Microsoft.MachineLearningServices) rather than a CognitiveServices
// deployment — provision it separately and wire its endpoint/key into
// litellm-config.yaml. See TODO below.

param name string
param location string
param peSubnetId string
param dnsZoneId string

@description('GPT-class model name to deploy (confirm availability in region).')
param gptModelName string = 'gpt-4o'
@description('GPT-class model version.')
param gptModelVersion string = '2024-11-20'
param gptCapacity int = 20

resource aiSvc 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny' }
  }
}

resource gpt 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiSvc
  name: 'gpt-class'
  sku: { name: 'GlobalStandard', capacity: gptCapacity }
  properties: {
    model: { format: 'OpenAI', name: gptModelName, version: gptModelVersion }
  }
}

// TODO(Qwen3-Coder-Next): deploy the open-weight serverless endpoint, then set
// its api_base/key in litellm-config.yaml under model_name: qwen3-coder.

resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${name}-pe'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'ai'
        properties: { privateLinkServiceId: aiSvc.id, groupIds: ['account'] }
      }
    ]
  }
}
resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'ai', properties: { privateDnsZoneId: dnsZoneId } }
    ]
  }
}

output endpoint string = aiSvc.properties.endpoint
output name string = aiSvc.name

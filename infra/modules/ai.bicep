// AI Services account (private) + GPT-class deployment + private endpoint.
// NOTE: Qwen3-Coder-Next (open-weight) is often a SERVERLESS deployment
// (Microsoft.MachineLearningServices) rather than a CognitiveServices
// deployment — provision it separately and wire its endpoint/key into
// litellm-config.yaml. See TODO below.

param name string
param location string
param peSubnetId string
param dnsZoneId string

@description('GPT-class model name to deploy (confirm availability + quota in region).')
param gptModelName string = 'gpt-5.4'
@description('GPT-class model version.')
param gptModelVersion string = '2026-03-05'
param gptCapacity int = 20

@description('''Deploy the open-weight Qwen model. Default OFF: in australiaeast on
this subscription qwen3-32b is not deployable as a standard endpoint (deploy layer
rejects GlobalStandard despite the catalog, and only finetune quota exists). To
enable: request base-inference quota, confirm the region-supported SKU (support
case, given the catalog/deploy mismatch), then set true. Qwen3-Coder-Next is
Marketplace/serverless — a separate mechanism.''')
param deployQwen bool = false
@description('Open-weight model. In eastus2/swedencentral the available standard deployment is qwen3-32b (format Alibaba). Qwen3-Coder-Next is Marketplace/serverless and not a standard deployment here.')
param qwenModelName string = 'qwen3-32b'
param qwenModelFormat string = 'Alibaba'
param qwenModelVersion string = '1'
param qwenCapacity int = 20

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

// Open-weight standard deployment. In eastus2 / swedencentral / australiaeast the
// available Qwen standard deployment is qwen3-32b (format Alibaba). Qwen3-Coder-Next
// is Marketplace/serverless and NOT a standard deployment in these regions — it
// would require a serverlessEndpoint resource + Marketplace subscription.
resource qwen 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployQwen) {
  parent: aiSvc
  name: 'qwen3-32b'
  sku: { name: 'GlobalStandard', capacity: qwenCapacity }
  properties: {
    model: { format: qwenModelFormat, name: qwenModelName, version: qwenModelVersion }
  }
  dependsOn: [ gpt ] // serialize deployments on the same account
}

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

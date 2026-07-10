// =============================================================================
// LLM Gateway PoC — Phase 0/1 infrastructure (governance-representative)
// Orchestrator. Resources live in ./modules/*.bicep.
//
// PoC target: Australia East. what-if validated 2026-07-11 (23 create, 1 unsupported).
//   * `bicep build main.bicep` (syntax) + `az deployment group what-if` (plan).
//   * GPT model = gpt-5.4 (GA + quota in Australia East).
//   * Open-weight (Qwen) is a CONDITIONAL deploy (deployQwen, default off) —
//     not deployable in AU (SKU + quota). See modules/ai.bicep.
//   * Provisions GPT-class only. Claude is Phase 2 (not available in any AU region).
// =============================================================================

targetScope = 'resourceGroup'

@description('Short prefix for resource names, e.g. "llmgw".')
param prefix string = 'llmgw'

@description('Azure region. East US 2 / Sweden Central recommended (Foundry Claude in Phase 2).')
param location string = resourceGroup().location

@description('Container image for the LiteLLM proxy.')
param litellmImage string = 'ghcr.io/berriai/litellm:main-stable'

@description('Postgres administrator login.')
param pgAdminLogin string = 'llmgwadmin'

@secure()
param pgAdminPassword string
@secure()
param litellmMasterKey string

var suffix = uniqueString(resourceGroup().id)
var names = {
  law: '${prefix}-law'
  vnet: '${prefix}-vnet'
  uami: '${prefix}-uami'
  kv: take(replace('${prefix}kv${suffix}', '-', ''), 24)
  pg: '${prefix}-pg-${suffix}'
  ai: '${prefix}-ai-${suffix}'
  acaEnv: '${prefix}-aca-env'
  acaApp: '${prefix}-litellm'
}
var pgFqdn = '${names.pg}.postgres.database.azure.com'
var litellmConfig = loadTextContent('litellm-config.yaml')
var aiOpenAiEndpoint = 'https://${names.ai}.openai.azure.com'

module network 'modules/network.bicep' = {
  name: 'network'
  params: { vnetName: names.vnet, location: location }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: { name: names.uami, location: location }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: { name: names.law, location: location }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: names.kv
    location: location
    appPrincipalId: identity.outputs.principalId
    peSubnetId: network.outputs.peSubnetId
    dnsZoneId: network.outputs.dnsKvId
    litellmMasterKey: litellmMasterKey
    databaseUrl: 'postgresql://${pgAdminLogin}:${pgAdminPassword}@${pgFqdn}:5432/litellm?sslmode=require'
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    name: names.pg
    location: location
    delegatedSubnetId: network.outputs.pgSubnetId
    dnsZoneId: network.outputs.dnsPgId
    adminLogin: pgAdminLogin
    adminPassword: pgAdminPassword
  }
}

module ai 'modules/ai.bicep' = {
  name: 'ai'
  params: {
    name: names.ai
    location: location
    peSubnetId: network.outputs.peSubnetId
    dnsZoneId: network.outputs.dnsAiId
    appPrincipalId: identity.outputs.principalId
  }
}

module containerapp 'modules/containerapp.bicep' = {
  name: 'containerapp'
  params: {
    envName: names.acaEnv
    appName: names.acaApp
    location: location
    acaSubnetId: network.outputs.acaSubnetId
    logAnalyticsWorkspaceName: monitoring.outputs.name
    userAssignedIdentityId: identity.outputs.id
    keyVaultUri: keyvault.outputs.vaultUri
    image: litellmImage
    litellmConfigContent: litellmConfig
    aiOpenAiEndpoint: aiOpenAiEndpoint
    appClientId: identity.outputs.clientId
  }
  dependsOn: [ postgres ]
}

output gatewayUrl string = containerapp.outputs.url
output aiServicesEndpoint string = ai.outputs.endpoint
output keyVaultName string = keyvault.outputs.name
output identityClientId string = identity.outputs.clientId

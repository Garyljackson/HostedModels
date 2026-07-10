// Key Vault (private, RBAC) + secrets + Secrets User role for the app identity
// + private endpoint into the VNet.

param name string
param location string
param appPrincipalId string
param peSubnetId string
param dnsZoneId string

@secure()
param litellmMasterKey string
@secure()
param azureAiApiKey string
@secure()
param databaseUrl string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices' }
    // Testing-friendly: soft-delete is mandatory, so keep the window short and
    // do NOT enable purge protection (omitted on purpose) — lets you purge and
    // reuse the name during create/delete cycles. See infra/teardown.ps1.
    softDeleteRetentionInDays: 7
  }
}

resource sMaster 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'litellm-master-key'
  properties: { value: litellmMasterKey }
}
resource sAiKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'azure-ai-api-key'
  properties: { value: azureAiApiKey }
}
resource sDbUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'database-url'
  properties: { value: databaseUrl }
}

// Key Vault Secrets User
var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
resource rbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, appPrincipalId, kvSecretsUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${name}-pe'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'kv'
        properties: { privateLinkServiceId: kv.id, groupIds: ['vault'] }
      }
    ]
  }
}
resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'kv', properties: { privateDnsZoneId: dnsZoneId } }
    ]
  }
}

output vaultUri string = kv.properties.vaultUri
output name string = kv.name

// Container Apps environment (VNet-integrated) + LiteLLM app (public ingress).
// Secrets are pulled from Key Vault via the user-assigned managed identity.

param envName string
param appName string
param location string
param acaSubnetId string
param logAnalyticsWorkspaceName string
param userAssignedIdentityId string
param keyVaultUri string
param image string

// Reference the existing LAW to read its shared key locally (kept out of outputs).
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource acaEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnetId
      internal: false // public ingress for the gateway; backends stay private
    }
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${userAssignedIdentityId}': {} }
  }
  properties: {
    managedEnvironmentId: acaEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 4000
        transport: 'auto' // supports SSE streaming
        allowInsecure: false
      }
      secrets: [
        {
          name: 'litellm-master-key'
          keyVaultUrl: '${keyVaultUri}secrets/litellm-master-key'
          identity: userAssignedIdentityId
        }
        {
          name: 'azure-ai-api-key'
          keyVaultUrl: '${keyVaultUri}secrets/azure-ai-api-key'
          identity: userAssignedIdentityId
        }
        {
          name: 'database-url'
          keyVaultUrl: '${keyVaultUri}secrets/database-url'
          identity: userAssignedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'litellm'
          image: image
          resources: { cpu: json('1.0'), memory: '2Gi' }
          // TODO: mount litellm-config.yaml (model_list, budgets, metadata-only
          // logging) — bake into a custom image or mount a volume, then start
          // LiteLLM with `--config /app/config.yaml`.
          env: [
            { name: 'LITELLM_MASTER_KEY', secretRef: 'litellm-master-key' }
            { name: 'AZURE_API_KEY', secretRef: 'azure-ai-api-key' }
            { name: 'AZURE_AI_API_KEY', secretRef: 'azure-ai-api-key' }
            { name: 'DATABASE_URL', secretRef: 'database-url' }
            { name: 'STORE_MODEL_IN_DB', value: 'True' }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output url string = 'https://${app.properties.configuration.ingress.fqdn}'

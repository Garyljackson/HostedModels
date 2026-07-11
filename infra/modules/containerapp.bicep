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
@secure() // Container Apps secret value expects a secure input (config has no real secrets, but this satisfies the linter)
@description('LiteLLM config.yaml content, mounted into the container as a file.')
param litellmConfigContent string
@description('Azure OpenAI endpoint of the AI Services account (injected as AZURE_API_BASE).')
param aiOpenAiEndpoint string
@description('Client ID of the user-assigned identity (for DefaultAzureCredential / AZURE_CLIENT_ID).')
param appClientId string
@description('Revision suffix (a hash of the config) so config changes auto-create a new revision. Container Apps does not restart replicas on a secret-value change.')
param revisionSuffix string

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
          name: 'database-url'
          keyVaultUrl: '${keyVaultUri}secrets/database-url'
          identity: userAssignedIdentityId
        }
        {
          // The LiteLLM config, mounted as a file via a Secret volume (below).
          name: 'litellm-config'
          value: litellmConfigContent
        }
      ]
    }
    template: {
      revisionSuffix: revisionSuffix
      containers: [
        {
          name: 'litellm'
          image: image
          resources: { cpu: json('1.0'), memory: '2Gi' }
          // Start LiteLLM against the mounted config (model_list + metadata-only logging).
          args: [ '--config', '/app/config/config.yaml', '--port', '4000' ]
          env: [
            { name: 'LITELLM_MASTER_KEY', secretRef: 'litellm-master-key' }
            { name: 'AZURE_API_BASE', value: aiOpenAiEndpoint }
            // Keyless auth: AZURE_CLIENT_ID selects the user-assigned identity for DefaultAzureCredential.
            { name: 'AZURE_CLIENT_ID', value: appClientId }
            { name: 'DATABASE_URL', secretRef: 'database-url' }
            { name: 'STORE_MODEL_IN_DB', value: 'True' }
          ]
          volumeMounts: [
            { volumeName: 'config', mountPath: '/app/config' }
          ]
        }
      ]
      volumes: [
        {
          // Secret volume mounts the litellm-config secret as /app/config/config.yaml
          name: 'config'
          storageType: 'Secret'
          secrets: [
            { secretRef: 'litellm-config', path: 'config.yaml' }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output url string = 'https://${app.properties.configuration.ingress.fqdn}'

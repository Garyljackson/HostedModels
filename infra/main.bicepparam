using './main.bicep'

param prefix = 'llmgw'
param location = 'eastus2' // or 'swedencentral'
param litellmImage = 'ghcr.io/berriai/litellm:main-stable'
param pgAdminLogin = 'llmgwadmin'

// Secrets — pass via environment variables at deploy time; do NOT hardcode.
//   PowerShell:  $env:PG_ADMIN_PASSWORD = '...'  (etc.)
//   Then:        az deployment group create -g <rg> -f main.bicep -p main.bicepparam
param pgAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD')
param litellmMasterKey = readEnvironmentVariable('LITELLM_MASTER_KEY')
param azureAiApiKey = readEnvironmentVariable('AZURE_AI_API_KEY')

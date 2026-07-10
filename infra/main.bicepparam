using './main.bicep'

param prefix = 'llmgw'
param location = 'australiaeast' // closest to Brisbane; PoC data stays in-country
param litellmImage = 'ghcr.io/berriai/litellm:main-stable'
param pgAdminLogin = 'llmgwadmin'

// Secrets — pass via environment variables at deploy time; do NOT hardcode.
//   PowerShell:  $env:PG_ADMIN_PASSWORD = '...'  (etc.)
//   Then:        az deployment group create -g <rg> -f main.bicep -p main.bicepparam
param pgAdminPassword = readEnvironmentVariable('PG_ADMIN_PASSWORD')
param litellmMasterKey = readEnvironmentVariable('LITELLM_MASTER_KEY')
// AI Services auth is keyless (managed identity) — no AI key param needed.

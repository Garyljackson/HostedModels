# Teardown for PoC create/delete cycles.
#
# Recommended pattern: use a UNIQUE resource-group name per test iteration.
# Because resource names derive from uniqueString(resourceGroup().id), a new RG
# name yields new names and there are NO soft-delete collisions — just delete
# the RG. This script also PURGES the soft-deletable resources (Key Vault,
# AI Services) so you can safely REUSE the same RG name if you prefer.
#
# Usage:
#   ./teardown.ps1 -ResourceGroup <rg> [-Prefix llmgw] [-Location eastus2]

param(
  [Parameter(Mandatory = $true)][string]$ResourceGroup,
  [string]$Prefix = 'llmgw',
  [string]$Location = 'eastus2'
)

Write-Host "Deleting resource group '$ResourceGroup' (cascades ordering)..." -ForegroundColor Cyan
az group delete --name $ResourceGroup --yes

# --- Purge soft-deleted Key Vaults (name stays reserved otherwise) ---
Write-Host "Purging soft-deleted Key Vaults matching '$Prefix'..." -ForegroundColor Cyan
$kvs = az keyvault list-deleted --query "[?starts_with(name, '$Prefix')].name" -o tsv
foreach ($kv in $kvs) {
  if ($kv) {
    Write-Host "  purge Key Vault: $kv"
    az keyvault purge --name $kv --location $Location
  }
}

# --- Purge soft-deleted AI Services / Cognitive accounts (holds subdomain) ---
Write-Host "Purging soft-deleted AI Services accounts matching '$Prefix'..." -ForegroundColor Cyan
$aiJson = az cognitiveservices account list-deleted --query "[?starts_with(name, '$Prefix')].{name:name, rg:resourceGroup, loc:location}" -o json
if ($aiJson) {
  foreach ($a in ($aiJson | ConvertFrom-Json)) {
    if ($a.name) {
      Write-Host "  purge AI account: $($a.name)"
      az cognitiveservices account purge --name $a.name --resource-group $a.rg --location $a.loc
    }
  }
}

Write-Host "Done." -ForegroundColor Green
Write-Host "Note: Log Analytics soft-deletes ~14 days; a unique RG name per run avoids name collisions." -ForegroundColor Yellow

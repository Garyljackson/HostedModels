# Infrastructure — LLM Gateway PoC (Bicep)

Phase 0/1 infrastructure for the PoC: LiteLLM gateway on Azure Container Apps
fronting Foundry **GPT-class (`gpt-5.4`)** in **Australia East**, governance-representative
(private backends, public gateway ingress). Open-weight (Qwen) is a conditional
deployment (`deployQwen`, default off — not deployable in AU). **Claude is Phase 2**
and not available in any AU region.

> **Status:** deployed and validated end-to-end in `australiaeast` — a `gpt-5.4`
> completion returns 200 via keyless managed identity over the private path.

**Operational notes:**
- **Config changes auto-deploy.** The container's revision suffix is a hash of
  `litellm-config.yaml`, so editing the config and redeploying creates a new revision.
  (Container Apps does **not** restart replicas on a bare secret-value change — the hash
  forces it.) **Master-key rotation is not hashed** — after rotating, force a new revision
  manually (`az containerapp update --set-env-vars ...`).
- **`gpt-5.4` needs `max_completion_tokens`, not `max_tokens`.** `model_info.base_model:
  azure/gpt-5` tells LiteLLM the family so it auto-maps the parameter for tools that send
  `max_tokens`.
- **Model naming.** Client-facing name is `gpt-5.4` (devs see the exact model); the Azure
  deployment is `gpt-5-4` (dots aren't allowed in deployment names).

## Layout

```
infra/
  main.bicep            # orchestrator (thin) — wires the modules together
  main.bicepparam       # parameters; secrets via env vars (readEnvironmentVariable)
  litellm-config.yaml   # LiteLLM model_list + metadata-only logging + budgets
  modules/
    network.bicep       # VNet, 3 subnets, private DNS zones + links
    identity.bicep      # user-assigned managed identity
    monitoring.bicep    # Log Analytics workspace
    keyvault.bicep      # Key Vault (private) + secrets + Secrets User RBAC + PE
    postgres.bicep      # PostgreSQL Flexible Server (private) + litellm DB
    ai.bicep            # AI Services account (private) + GPT deployment + PE
    containerapp.bicep  # Container Apps env (VNet-integrated) + LiteLLM app
```

## Prerequisites

- Azure CLI (`az`) with the Bicep extension, and permissions to create the above.
- A resource group.
- Region: **Australia East** (set in `main.bicepparam`). Claude Phase 2 would need East US 2 / Sweden Central.

## Deploy

```powershell
# 1. Secrets via environment variables (never commit these)
$env:PG_ADMIN_PASSWORD = '<strong-password>'
$env:LITELLM_MASTER_KEY = '<random-master-key>'
$env:AZURE_AI_API_KEY   = '<ai-services-key>'   # from the AI Services account

# 2. Validate (compile + plan)
az bicep build --file infra/main.bicep
az deployment group what-if -g <rg> -f infra/main.bicep -p infra/main.bicepparam

# 3. Deploy
az deployment group create -g <rg> -f infra/main.bicep -p infra/main.bicepparam
```

Outputs include `gatewayUrl` (the LiteLLM endpoint), `aiServicesEndpoint`,
`keyVaultName`, and `identityClientId`.

## Testing: create / delete cycles

Some resources **soft-delete** (the name is reserved after deletion): **Key Vault**,
**AI Services**, and **Log Analytics**. Redeploying the same name collides until
the reserved copy is purged. This template is set up to make cycling easy:

- **Purge protection is NOT enabled** on Key Vault (so you can purge freely), and
  soft-delete retention is set to **7 days**.
- **No API Management** (the slow-to-delete resource) is used.

**Recommended: a unique resource-group name per iteration.** All names derive from
`uniqueString(resourceGroup().id)`, so a fresh RG name → fresh resource names →
no soft-delete collisions. Tear down by deleting the RG.

To reuse the *same* RG name, purge the soft-deletables afterward:

```powershell
./infra/teardown.ps1 -ResourceGroup <rg> -Prefix llmgw -Location eastus2
```

> ⚠️ **Check org Azure Policy first.** Some tenants force purge protection on Key
> Vaults or deny purges. If yours does, you can't purge before the retention
> window — use unique RG *and* Key Vault names per iteration instead.

## Running costs (estimate — left running idle, AUD)

Rough monthly cost with the stack deployed in **Australia East** but under no real
load. From the Azure Retail Prices API (2026-07-11); Container Apps and Log
Analytics are estimates — confirm against Azure Cost Management.

| Component | ~AUD/month |
|-----------|-----------|
| PostgreSQL Flexible Server B1ms + 32 GB storage | ~34 |
| Container App (1 vCPU / 2 GiB, `minReplicas: 1`, always-on) | ~20–35 |
| 2 × private endpoints (Key Vault, AI Services) | ~21 |
| Private DNS zones (5) | ~4 |
| Log Analytics | ~1–5 |
| Key Vault | <1 |
| `gpt-5.4` tokens | usage-based (negligible when idle) |
| **Idle total** | **~A$80–100/month** |

Dominated by Postgres, the always-on container, and the two private endpoints;
token spend is on top and scales with pilot usage.

**Cost levers:** set `minReplicas: 0` (in `modules/containerapp.bicep`) to scale the
gateway to zero when idle — cold-start tradeoff; stop Postgres between sessions; or
tear down entirely (`./teardown.ps1 -ResourceGroup <rg>`) and redeploy (~10 min) for
~A$0 between test sessions.

## Before the pilot

1. **Smoke-test the deployment.** Confirm a `gpt-5.4` request returns 200 (keyless MI →
   Azure OpenAI): check container logs for a token acquired (no `DefaultAzureCredential
   failed`), then call the gateway. On a 403, broaden the identity's role from
   `Cognitive Services OpenAI User` to `Cognitive Services User`.
2. **Quota.** Default Foundry PAYGO limits suit a small pilot; confirm `gpt-5.4` quota
   covers your expected concurrency and request an increase if needed.
3. **Provision developer keys.** Per-developer virtual keys with budgets (manual or
   scripted for the pilot; Entra-group automation is a production-phase item — F11).
4. **Verify governance** (see `docs/EVALUATION.md` §6): backend resources not publicly
   reachable; no prompt/completion content in any sink.

**Optional — enable Qwen (open-weight):** not deployable in Australia East today (the
deploy layer rejects the `GlobalStandard` SKU for `qwen3-32b`, and only *finetune* quota
exists). To enable: request base-inference quota + resolve the SKU with support, set
`deployQwen=true`, and uncomment the entry in `litellm-config.yaml`. Qwen3-Coder-Next is
Marketplace/serverless (not in AU).

## Notes

- `bicep build main.bicep` compiled with **0 errors / 0 warnings** (CLI 0.44.1).
- The database connection string is assembled in `main.bicep` and stored as a
  Key Vault secret; the app reads it via managed identity — the password is never
  emitted as an output.
- Deferred past the PoC: HA/multi-region, Front Door/WAF, full provisioning
  automation, and Claude/Claude Code (Phase 2).

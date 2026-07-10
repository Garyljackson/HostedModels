# Infrastructure — LLM Gateway PoC (Bicep)

Phase 0/1 infrastructure for the PoC: LiteLLM gateway on Azure Container Apps
fronting Foundry **GPT-class + Qwen3-Coder-Next** models, governance-representative
(private backends, public gateway ingress). **Claude is Phase 2** and not deployed here.

> **Status: skeleton.** `bicep build` passes cleanly, but this has **not** been
> deployed end-to-end. Validate with `what-if` and confirm the TODO items before
> a real deployment.

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
- Decide region: **East US 2** or **Sweden Central**.

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

## Post-deploy / TODO (must resolve before the pilot)

1. **AZURE_AI_API_KEY chicken-and-egg.** The AI Services key exists only after the
   account is created. Either deploy in two passes (infra first, then read the key
   and store it), or switch LiteLLM to **managed-identity** auth against AI Services
   and drop the key. Confirm which LiteLLM supports for your Foundry route.
2. **GPT model.** Confirm `gptModelName` / `gptModelVersion` in `modules/ai.bicep`
   are available in the region; adjust capacity.
3. **Qwen3-Coder-Next.** Provision the open-weight serverless endpoint (separate
   from the CognitiveServices deployment), then set its `api_base`/key in
   `litellm-config.yaml` under `model_name: qwen3-coder`.
4. **LiteLLM config mounting.** `containerapp.bicep` runs the stock image; wire in
   `litellm-config.yaml` (bake a custom image, or mount a volume) and start with
   `--config /app/config.yaml`.
5. **Verify governance during the eval** (see `docs/EVALUATION.md` §6): backend
   resources not publicly reachable; no prompt/completion content in any sink.
6. **Provisioning:** create per-developer virtual keys with budgets (pilot can be
   manual/scripted; automation is a production-Phase concern).

## Notes

- `bicep build main.bicep` compiled with **0 errors / 0 warnings** (CLI 0.44.1).
- The database connection string is assembled in `main.bicep` and stored as a
  Key Vault secret; the app reads it via managed identity — the password is never
  emitted as an output.
- Deferred past the PoC: HA/multi-region, Front Door/WAF, full provisioning
  automation, and Claude/Claude Code (Phase 2).

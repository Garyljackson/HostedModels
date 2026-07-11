# Technical Design Document — Internal LLM Gateway for Coding Tools

**Status:** Draft — **Proof-of-Concept / evaluation stage**
**Owner:** garyljackson@gmail.com
**Last updated:** 2026-07-11
**Companions:** `PRD.md` (product), `EVALUATION.md` (PoC success criteria & go/no-go)

---

## 1. Summary

A self-hosted **LiteLLM** proxy (MIT core) running on **Azure Container Apps** fronts **Microsoft Foundry** model deployments. LiteLLM presents both an OpenAI-compatible and an Anthropic-compatible (`/v1/messages`) API on one endpoint. Only the gateway ingress is public (virtual-key auth); Foundry, PostgreSQL, Key Vault, and logging are private (VNet + private endpoints). Access is gated by Entra ID group membership via provisioning automation; cost/usage are controlled by per-key/per-team budgets in LiteLLM with metadata-only logging. Infrastructure is provisioned with **Bicep**.

**Phasing & region:** The PoC runs in **Australia East** (residency-first) and serves **GPT-class only** (`gpt-5.4`) — the only model deployable in AU. **Open-weight (Qwen) is deferred** (not deployable in AU: deploy layer rejects the SKU + no base-inference quota). **Claude + Claude Code are deferred to Phase 2 and are not available in any AU region** (in-tenant Claude = East US 2 / Sweden Central) — enabling them means leaving AU residency. LiteLLM is model-agnostic, so adding models later is additive.

## 2. Platform facts & constraints

| Area | Detail |
|------|--------|
| Claude on Microsoft Foundry | Two hosting modes: **Hosted on Azure** (in-tenant) and **Hosted on Anthropic infrastructure** (external). Only Hosted-on-Azure keeps inference in-tenant. Hosted-on-Azure Claude (`claude-opus-4-8`, `claude-sonnet-5`, `claude-haiku-4-5`) is in **East US 2 / Sweden Central**, not AU. |
| AU region availability | **Australia East is the only AU region with Foundry models.** In AU, GPT is deployable (`gpt-5.4`, GlobalStandard); **Qwen is not** (deploy layer rejects the SKU + no base-inference quota); **Claude is absent from every AU region**. |
| LiteLLM → Foundry routing | `azure/` route for Azure OpenAI (GPT); `azure_ai/` for Claude/open-weight (`api_base` `…/anthropic` or `…/models`). Auth: **managed identity (keyless)** or API key. |
| LiteLLM endpoints | One endpoint serves both OpenAI-compatible (`/v1/chat/completions`) and Anthropic (`/v1/messages`) formats. |
| Claude Code env vars (Phase 2) | `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, and `ANTHROPIC_DEFAULT_HAIKU_MODEL` (fast/background). |
| LiteLLM license | **MIT core** (free, self-hosted). Enterprise is only needed for SSO beyond 5 users, audit logs, RBAC, SLA — not used here. |

## 3. Architecture

```mermaid
flowchart TB
    dev["Developer coding tools<br/>OpenCode · Cline · Continue<br/>(Claude Code — Phase 2)"]

    subgraph public["Public ingress"]
        gw["LiteLLM Gateway — Azure Container Apps<br/>—<br/>OpenAI-compat /v1/chat/completions<br/>Anthropic-compat /v1/messages<br/>streaming (SSE) · model routing<br/>virtual keys · budgets · rate limits<br/>metadata-only logging"]
    end

    subgraph vnet["Private VNet — public network access disabled"]
        foundry["Microsoft Foundry (Australia East)<br/>gpt-5.4 (GPT-class) — launch<br/>Qwen — deferred (not deployable in AU)<br/>Claude — Phase 2 (not available in AU)"]
        pg[("PostgreSQL Flexible Server<br/>keys · spend · budgets")]
        kv["Key Vault<br/>Foundry / DB credentials"]
        logs["Log Analytics / Storage<br/>metadata only"]
    end

    dev -->|"HTTPS 443 · virtual-key auth"| gw
    gw -->|"VNet integration · Private Endpoint"| foundry
    gw -->|"private networking"| pg
    gw -->|"managed identity · Private Endpoint"| kv
    gw -->|"Private Endpoint"| logs
```

## 4. Model catalog & routing

**PoC (Australia East):** only **GPT-class** (`gpt-5.4`) is deployable in-region — the authoritative config is `infra/litellm-config.yaml`. Open-weight (Qwen) is wired into the Bicep as a **conditional** deployment (`deployQwen`, default off) but is not deployable in AU today.

**Phase 2 (non-AU) governance rule:** if Claude is added, use only **Hosted on Azure** Claude deployments (East US 2 / Sweden Central; Data Zone Standard US for US residency) so inference stays in-tenant — never the "Hosted on Anthropic infrastructure" variants for governed traffic. This leaves Australian residency.

LiteLLM maps friendly names to Foundry deployments; clients see only the friendly names (F12). Illustrative shape (authoritative config in `infra/litellm-config.yaml`):

```yaml
model_list:
  # === LAUNCH (Australia East): GPT-class only, standard Azure billing ===
  - model_name: gpt-class
    litellm_params:
      model: azure/gpt-class                         # AOAI deployment (model gpt-5.4)
      api_base: os.environ/AZURE_API_BASE            # injected from AI Services endpoint
      api_version: "2024-10-21"
      # keyless: managed identity (litellm_settings.enable_azure_ad_token_refresh)

  # DEFERRED — open-weight Qwen (not deployable in AU: SKU rejected + no base quota)
  # - model_name: qwen3-32b
  #   litellm_params:
  #     model: azure_ai/qwen3-32b
  #     api_base: https://<resource>.services.ai.azure.com/models
  #     api_key: os.environ/AZURE_AI_API_KEY

  # === PHASE 2 (deferred): Claude, Hosted on Azure (in-tenant) — enables Claude Code ===
  # Requires Azure Marketplace/CCU subscription before deploying.
  - model_name: claude-opus-4-8            # Claude Code main model
    litellm_params:
      model: azure_ai/claude-opus-4-8
      api_base: https://<resource>.services.ai.azure.com/anthropic
      api_key: os.environ/AZURE_API_KEY    # or Entra AD token / service principal

  - model_name: claude-fast                # Claude Code background/fast model
    litellm_params:
      model: azure_ai/claude-haiku-4-5
      api_base: https://<resource>.services.ai.azure.com/anthropic
      api_key: os.environ/AZURE_API_KEY

  - model_name: claude-sonnet-5            # mid-tier option
    litellm_params:
      model: azure_ai/claude-sonnet-5
      api_base: https://<resource>.services.ai.azure.com/anthropic
      api_key: os.environ/AZURE_API_KEY

litellm_settings:
  drop_params: true
```

> Verify exact env-var names (`AZURE_API_KEY` vs `AZURE_AI_API_KEY`) and the open-weight `api_base` shape at build; LiteLLM's Azure AI vs Azure OpenAI routes differ slightly.

> **Adding a model? Set its price in AUD (required for correct budgets).** Every model's
> `model_info` must carry `input_cost_per_token` / `output_cost_per_token` in **AUD** (see
> `infra/litellm-config.yaml`). Without them, LiteLLM falls back to a USD estimate from its
> built-in cost map — or **$0** for a model it doesn't recognise — so **budgets and per-key
> spend would be wrong**. Derive the AUD rate from Azure's list price × the **~1.45 AUD/USD**
> multiplier (or your EA price sheet), then verify with the `x-litellm-response-cost` response
> header. For GPT-5 / reasoning models also set `base_model` so `max_tokens` is mapped to
> `max_completion_tokens`.

## 5. Capacity & throughput (important — Phase 2 / Claude)

> Applies when Claude is added in Phase 2. Launch (GPT-class/open-weight) uses standard Azure OpenAI / Foundry quotas — size those separately.

Default **pay-as-you-go** quota per Claude model on Foundry (subscription-level, shared across regions):

| Model (Hosted on Azure) | Default RPM | Default ITPM (uncached input) |
|-------------------------|-------------|-------------------------------|
| `claude-opus-4-8` | 40 | 40,000 |
| `claude-sonnet-5` | 40 | 40,000 |
| `claude-haiku-4-5` | 80 | 80,000 |

**Risk:** agentic coding tools (Claude Code) are request- and input-token-heavy. For <50 engineers, **40 RPM / 40k ITPM on Opus can become a bottleneck** under concurrent use. Mitigations, in order:
1. Route background/fast work to `claude-haiku-4-5` (higher limits) — Claude Code does this natively via `ANTHROPIC_DEFAULT_HAIKU_MODEL`.
2. Submit a **quota-increase request** (Azure form) for Opus.
3. An **Enterprise/MCA-E** agreement raises defaults dramatically (2,000 RPM / 2,000,000 ITPM).
4. LiteLLM handles 429s with retry/backoff and can spill to a secondary model.

Billing is via **Claude Consumption Units (CCU)** through **Azure Marketplace** — requires a Marketplace subscription and the permissions to subscribe to model offerings. (This is still pay-as-you-go; PTU-style reservations deferred.)

## 6. Client configuration

### 6.1 Claude Code (Anthropic-compatible) — Phase 2 (requires Claude models)

```bash
export ANTHROPIC_BASE_URL="https://<gateway-host>"           # LiteLLM /v1/messages
export ANTHROPIC_AUTH_TOKEN="<developer-virtual-key>"        # LiteLLM virtual key (Bearer)
export ANTHROPIC_MODEL="claude-opus-4-8"                     # main model (gateway alias)
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-fast"           # background/fast model (gateway alias)
```

Or via `~/.claude/settings.json` (`env` block) for a managed default. `ANTHROPIC_AUTH_TOKEN` (not `ANTHROPIC_API_KEY`) is correct for a gateway that issues its own keys.

### 6.2 OpenAI-format tools (OpenCode, Cline, Continue, Aider, Goose, Zed)

```
Base URL: https://<gateway-host>/v1
API key:  <developer-virtual-key>
Model:    gpt-class          (PoC; Qwen + Claude deferred)
```

A short onboarding README per blessed tool is a Phase 2 deliverable.

## 7. Authentication & key lifecycle

- **How the two layers connect (important):** developers authenticate to the gateway with a **virtual key**, **not** an Entra token per request — LiteLLM (MIT core) has **no per-request Entra SSO** on the data plane. Entra governs only *who is issued a key*. There is **no built-in LiteLLM↔Entra integration**; the link is a provisioning job **we build**.
- **Developer auth:** LiteLLM **virtual key** (Bearer). All client requests authenticate with this key.
- **Provisioning automation (glue we build):** a scheduled job reads the approved **Entra ID group** via the Microsoft Graph API and ensures a virtual key exists per member (LiteLLM key API); revokes keys for removed members (F11). This is our own automation, not a LiteLLM feature. No LiteLLM Enterprise SSO required.
- **Admin access:** LiteLLM **master key** in Key Vault, held by 1–2 platform admins. (Note: LiteLLM SSO is free for ≤5 users if we later want Entra login on the admin UI — but master-key admin is the baseline, no Enterprise dependency.)
- **Immediate offboarding:** in addition to the scheduled Entra sync, an on-demand revoke path (script/webhook) revokes a key immediately when someone leaves.
- **Rotation:** virtual keys per developer; master key on schedule + admin offboarding; Foundry/DB creds via Key Vault.

## 8. Cost control (two independent layers)

1. **Azure billing mode:** pay-as-you-go via CCU/Marketplace. One aggregate Azure bill.
2. **Gateway budgets:** LiteLLM enforces **per-developer** and **per-team** monthly budgets, attributes spend per key/user/team/model, and blocks on breach (F7). Per-key rate limits (F8) cap runaway usage independent of budget.

## 9. Usage visibility

- **Admins:** LiteLLM dashboard — spend by key/user/team/model.
- **Developers:** self-service view of their own key's spend vs budget via LiteLLM API (optionally wrapped as a `mycost` CLI). Metadata only — no content needed. All MIT-core features.

## 10. Logging & retention

- **Metadata only (F10, N3):** token counts, model, user/key, team, timestamp, cost, status. **Prompt/completion text never persisted** — disable content logging in LiteLLM; verify no content sink in Postgres/Log Analytics/Storage.
- **Retention:** operational metadata per standard policy; no content to purge.
- **Verification:** design review + periodic audit that no content sinks exist.

## 11. Networking & security

- **Only public surface:** LiteLLM Container Apps ingress (443), authenticated by virtual keys.
- **Foundry:** public network access **disabled**; reached only via **Private Endpoint** from the VNet (N1, N2).
- **Container App:** deployed into a **VNet-integrated** Container Apps environment; outbound calls to Foundry/DB/Key Vault stay on the private network.
- **PostgreSQL:** private networking only.
- **Key Vault + Log Analytics/Storage:** Private Endpoints.
- **Managed identity (keyless):** the Container App's **user-assigned** identity (a) reads the master key + DB URL from Key Vault, and (b) authenticates to Azure OpenAI directly via Entra — it holds the **Cognitive Services OpenAI User** role on the AI Services account, and LiteLLM mints tokens with `enable_azure_ad_token_refresh: true` (DefaultAzureCredential; `AZURE_CLIENT_ID` selects the identity). **No AI key** is stored anywhere. User-assigned (not system-assigned) so roles can be granted *before* the app exists → single-pass deploy (N7).
- **Optional (deferred) hardening:** IP allowlist on Container Apps ingress (free); Front Door **Standard** (~$35/mo custom WAF rules) before ever considering **Premium** (~$330/mo). Not baseline (N5).

## 12. Deployment & IaC (Bicep)

- **Bicep** provisions: VNet + subnets + private endpoints; Foundry resource + Claude (Hosted on Azure) + GPT + open-weight deployments; Container Apps env + app; Postgres Flexible Server; Key Vault; Log Analytics; managed identity + role assignments; Azure Marketplace subscription for Claude offerings.
- **Config:** LiteLLM `config.yaml` (model list, budgets, logging) in repo; secrets via Key Vault references resolved by managed identity.
- **CI/CD:** container build+deploy pipeline for the LiteLLM image/config; Bicep pipeline for infrastructure.

## 13. Observability

- LiteLLM request metrics (latency, tokens, errors, spend) → Log Analytics (metadata only).
- Alerts: budget-threshold breaches; elevated Foundry 429/5xx (quota pressure); gateway health.
- Dashboard: spend by team, request volume, error/429 rates, top models.

## 14. Availability & failure behavior

- **Launch:** single-region best-effort (N6). Container Apps handles gateway scaling.
- **Foundry 429 (quota):** LiteLLM retry/backoff; clear error to client; optional spill to a secondary model. Expect this until quota is raised (see §5).
- **HA / multi-region:** deferred until justified by scale.

## 15. Data governance summary

- Inference runs on **Hosted on Azure** Claude deployments **inside our tenant** (optionally Data Zone Standard US for residency); **not** on Anthropic-infrastructure variants or external provider APIs.
- No prompt/completion content retained anywhere.
- All backend resources private; only a key-authenticated gateway is exposed.
- Blessed-tool policy prevents hybrid-SaaS tools from exfiltrating prompts.
- **Due diligence:** review Microsoft's "Data, privacy, and security for Claude models in Foundry" and "Compare Azure-hosted vs Anthropic-hosted" pages before sign-off.

## 16. Open items

- **Entra-group provisioning automation** — the Graph → LiteLLM key-API sync (F11) is designed but not built; pilot keys are provisioned manually.
- **Immediate-offboarding revoke** — on-demand key revocation alongside the scheduled Entra sync.
- **Cost reconciliation** — confirm the AUD per-token rates against Azure Cost Management once billing data lands (see `EVALUATION.md` §5.3).
- **Phase 2 (Claude, non-AU):** Azure Marketplace/CCU subscription; quota sizing (default Foundry PAYGO limits likely need an increase or an Enterprise/MCA-E agreement); and confirming the data-residency posture against Microsoft's Claude data-privacy / hosting-comparison pages.

---

*Product context in `PRD.md`.*

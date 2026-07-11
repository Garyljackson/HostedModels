# Product Requirements Document — Internal LLM Gateway for Coding Tools

**Status:** Draft v1 — **Proof-of-Concept / evaluation stage** (go/no-go before any production deployment)
**Owner:** garyljackson@gmail.com
**Last updated:** 2026-07-10
**Companions:** `TDD.md` (design), `EVALUATION.md` (PoC success criteria & go/no-go)

---

## 1. Overview

We will stand up a centrally governed **LLM gateway** in Azure that lets employees use AI coding tools (Claude Code, OpenCode, and other approved clients) against company-controlled, Azure-hosted models. The gateway provides a single approved endpoint with identity-based access, per-developer and per-team cost controls, usage visibility, and a data-governance guarantee that code and prompts stay within our Azure tenant.

The product is **not** "a hosted model" — it is the **gateway/control plane** that ties approved coding tools to Azure-hosted models while enforcing access, cost, and governance policy.

## 2. Problem statement

Engineers want to use modern AI coding tools, but ungoverned adoption creates four problems this project solves:

1. **Data governance** — with direct-to-vendor SaaS tools, proprietary code and prompts leave our control. We need inference to stay in-tenant.
2. **Cost control & visibility** — uncontrolled per-seat SaaS spend with no per-team attribution and no spend caps.
3. **Standardization & access control** — no single approved endpoint, no identity-based gating, inconsistent model access.
4. **Vendor flexibility** — inability to route across multiple models (Claude, GPT, open-weight) without changing what engineers install.

## 3. Goals

- Provide **one approved endpoint** that approved coding tools point at.
- Keep **inference in-tenant** on Azure AI Foundry; no proprietary code/prompts sent to external provider APIs.
- Enforce **identity-based access** — Entra ID group membership governs *who is issued* a gateway (virtual) key, via provisioning automation we build. Developers authenticate per request with the key, not an Entra token (LiteLLM has no per-request Entra SSO).
- Provide **per-developer and per-team budgets**, spend attribution, and self-service usage visibility.
- Support **model choice** (Claude, GPT-class, open-weight) through **one endpoint and API format** — developers switch models by changing the model name, not by switching tools or SDKs.
- Operate at **low cost and low ops burden** appropriate for <50 engineers.

## 4. Non-goals

- **Not** integrating GitHub Copilot. Copilot is SaaS-locked to GitHub's backend and cannot route to our gateway. If Copilot is desired, it is procured separately and governed separately (out of scope here).
- **Not** hosting/training our own foundation models.
- **Not** building a custom IDE plugin or client. We rely on existing tools' custom-endpoint support.
- **Not** exposing external/public provider APIs (Anthropic, OpenAI direct) at launch — would break the in-tenant guarantee.

## 5. Key decisions (locked)

| Area | Decision |
|------|----------|
| Gateway | **LiteLLM**, self-hosted on Azure Container Apps. **MIT core only — no Enterprise dependency at launch.** |
| Region | **Australia East** (closest to Brisbane; residency-first). The only AU region with Foundry models. |
| Models (launch) | **GPT-class only** — Azure OpenAI `gpt-5.4` in Australia East. Standard Azure billing, no Marketplace/CCU. |
| Model naming | **Transparent, version-pinned** — clients use the real model name (`gpt-5.4`), not an opaque alias, so developers know exactly what they call. Upgrades add the new name alongside the old (migration window) rather than swapping silently. Trade-off: model upgrades touch client config (accepted for transparency). |
| Open-weight (deferred) | Qwen **not deployable in AU** (deploy layer rejects the SKU + no base-inference quota; Qwen3-Coder-Next is Marketplace/serverless). Needs a quota/SKU support case, or a non-AU region. |
| Models (deferred phase) | **Claude** (`claude-opus-4-8` + `claude-haiku-4-5` + `claude-sonnet-5`) is **not available in any AU region** — in-tenant Claude is East US 2 / Sweden Central only. Enabling Claude Code means leaving AU residency (+ Marketplace/CCU). |
| Claude Code | **Deferred** to the Claude phase (Claude Code requires Claude models). |
| Scale | < 50 engineers. |
| IaC | **Bicep**. |
| GitHub Copilot | **Dropped** (cannot route through the gateway). |
| Billing mode | **Pay-as-you-go** to start; Provisioned Throughput (PTU) deferred. |
| Cost control | Per-developer + per-team monthly budgets enforced in LiteLLM. |
| Logging | **Metadata only** — token counts, model, user, timestamp, cost. **No prompt/completion content retained.** |
| Network | LiteLLM ingress **public + virtual-key auth**; all other resources **private** (VNet + private endpoints). |
| Data residency | Inference stays in-tenant on Foundry; no direct external provider calls. |
| WAF / Front Door | **Deferred** optional hardening (cost-sensitive — see §11). |

## 6. Users & personas

- **Developer** — installs an approved coding tool, receives a virtual key, configures the tool to point at the gateway, uses AI assistance for code generation/editing. Can view their own usage vs budget.
- **Team lead** — needs visibility into their team's spend and budget.
- **Platform admin (1–2 people)** — provisions/revokes keys, manages models and budgets, monitors overall usage and cost, holds the LiteLLM master key.
- **Security / compliance** — needs assurance that code/prompts stay in-tenant, access is identity-gated, and no sensitive content is retained.

## 7. Functional requirements

| ID | Requirement |
|----|-------------|
| F1 | Expose an **OpenAI-compatible** API (`/v1/chat/completions`, etc.) for OpenAI-format clients. |
| F2 | Expose an **Anthropic-compatible** API (`/v1/messages`) for Claude Code. |
| F3 | Support **streaming (SSE)** end-to-end on both API formats. |
| F4 | Route requests to **Azure AI Foundry** model deployments by model name. |
| F5 | Offer multiple models via one endpoint. Target: GPT-class, open-weight, and (non-AU) Claude tiers. **AU PoC ships GPT-class (`gpt-5.4`) only** — open-weight/Claude gated by regional availability. |
| F6 | Issue **per-developer virtual keys**; authenticate all client requests by key. |
| F7 | Enforce **per-developer and per-team monthly budgets**; block/deny when exceeded. |
| F8 | Enforce **per-key rate limits**. |
| F9 | Track **spend and usage** per key/user/team/model; expose to admins (dashboard) and to developers (self-service view of their own usage). |
| F10 | Log **metadata only**; never persist prompt or completion text. |
| F11 | Provision/deprovision keys based on **Entra ID group membership** via an automation **we build** (reads the group via Microsoft Graph → creates/revokes keys via the LiteLLM key API). Entra governs *who is issued a key*; developers still authenticate **per request with the virtual key, not an Entra token** — there is no built-in LiteLLM↔Entra SSO on MIT core. |
| F12 | Centralize model management at the gateway (add / route / retire models in one place). **Naming is transparent** — clients use version-pinned names (e.g. `gpt-5.4`) so developers know the exact model they're calling. New models are exposed immediately as new names; **upgrades/retirements expose the new name alongside the old with a migration window**, rather than silently swapping the model behind a stable alias. |

## 8. Non-functional requirements

| ID | Requirement |
|----|-------------|
| N1 | **Data residency:** all inference and stored operational data remain within our Azure tenant/region. |
| N2 | **Network isolation:** only the gateway ingress is public; Foundry, database, secrets, and logs are private. |
| N3 | **No content retention:** no prompt/completion text stored anywhere in the system. |
| N4 | **Low ops burden:** managed/serverless services preferred; suitable for a 1–2 person platform team. |
| N5 | **Cost efficiency:** PAYGO billing; no fixed high-cost components (no Premium WAF) at launch. |
| N6 | **Availability:** best-effort single-region at launch; graceful failure when Foundry rate-limits (clear error, no data loss). |
| N7 | **Secret hygiene:** model/database credentials in Key Vault; prefer managed identity over static keys. |
| N8 | **License:** MIT-core LiteLLM only; no proprietary Enterprise dependency. |

## 9. Supported coding tools

The gateway supports **any client that can target a custom OpenAI- or Anthropic-compatible endpoint with an API key.** To preserve the in-tenant guarantee, the organization blesses the **full-fit** tier (all traffic routes through the gateway) and discourages hybrid-SaaS tools that route some features through vendor clouds.

- **Blessed (full-fit — recommended):** OpenCode, Cline, Continue.dev, Aider, Goose, Zed assistant at launch; **Claude Code** joins in **Phase 2** (requires Claude models).
- **Discouraged (hybrid SaaS — partial traffic leaves tenant):** Cursor, Cody, JetBrains AI Assistant. Allowed only with explicit risk acceptance.
- **Unsupported (SaaS-locked):** GitHub Copilot, Windsurf, Amp.

> This ecosystem moves quickly; the blessed list is reviewed periodically.

## 10. Success metrics

- ≥ 80% of active engineers onboarded to the gateway within one quarter of launch.
- 100% of blessed-tool traffic routed in-tenant (zero external-provider egress of code/prompts).
- Monthly cost visible and attributable per developer and per team.
- Zero prompt/completion content retained (verified by design + audit).
- No budget-driven cost overruns (spend caps enforced).

## 11. Risks & open questions

| Risk / question | Notes / mitigation |
|-----------------|--------------------|
| **Metadata-only logging limits abuse/debug investigation** | Accepted trade-off for privacy. If an incident requires content, there is no retained record — mitigate with rate limits + budgets as preventive controls. |
| **Public gateway ingress** | Protected by virtual keys + per-key rate limits; optional IP allowlist via Container Apps ingress at no extra cost. Front Door/WAF deferred due to cost (~$330/mo Premium). Revisit if exposure broadens or abuse appears. |
| **Foundry model availability** | ✅ Verified (2026-07-10): `claude-opus-4-8`, `claude-haiku-4-5`, `claude-sonnet-5` are **Hosted on Azure (GA)** in East US 2 / Sweden Central. Use only Hosted-on-Azure variants for governed traffic; Data Zone Standard (US) for US residency. |
| **Australia regional availability (verified 2026-07-11)** | Australia East is the **only** AU region with Foundry models. In AU **only GPT is deployable** (`gpt-5.4`; quota 3000, 150 used). Qwen not deployable (SKU rejected + no base-inference quota); Claude absent from all AU regions. An AU-resident PoC is therefore **GPT-only**; the open-weight arm + Claude require a non-AU region or awaiting AU availability. |
| **Foundry throughput / quota** | AU `gpt-5.4` quota is ample for the PoC (3000, 150 used). For Phase 2 Claude (non-AU), default PAYGO (e.g. Opus 40 RPM / 40k input-TPM) may bottleneck — route background to Haiku, request an increase, or an Enterprise/MCA-E agreement (2,000 RPM / 2M ITPM). |
| **Billing via Azure Marketplace (CCU)** | Claude on Foundry bills in Claude Consumption Units via Azure Marketplace; requires a Marketplace subscription and subscribe permissions. Deferred to **Phase 2** — off the launch critical path (this is the reason Claude is deferred). |
| **No Claude Code at launch** | Claude Code requires Claude models, which arrive in Phase 2. Launch tools are the OpenAI-format blessed set. Accepted trade-off for faster time-to-launch. |
| **LiteLLM MIT/Enterprise boundary shifts** | Due-diligence item: confirm current feature split before build; design assumes MIT-core capabilities only. Admin UI SSO forgone (master-key admin access instead). |
| **PAYGO rate limits under load** | Best-effort throughput; if latency/quota issues appear, evaluate PTUs (deferred). |
| **Single region / availability** | Launch is single-region best-effort. HA/multi-region deferred until justified by scale. |
| **Hybrid-SaaS tool leakage** | Blessed-list policy + developer education; discourage Cursor/Windsurf/Copilot for governed work. |

## 12. Phased rollout

1. **Phase 0 — Foundation:** Bicep for VNet + private endpoints, Foundry resource, Container Apps env, Postgres, Key Vault, managed identity, Log Analytics — in **Australia East**. Deploy **GPT-class** (`gpt-5.4`, standard Azure billing).
2. **Phase 1 — Gateway MVP (GPT-only):** LiteLLM deployed, `gpt-class` routed, virtual keys, budgets, metadata logging, streaming verified. Pilot with 3–5 engineers using **OpenAI-format tools** (OpenCode / Cline / Continue). Entra-group provisioning automation; self-service usage view. *(Open-weight deferred — not deployable in AU.)*
3. **Phase 2 — Add Claude + Claude Code:** Provision Azure Marketplace/CCU subscription; add Hosted-on-Azure Claude deployments (`claude-opus-4-8`, `claude-haiku-4-5`, `claude-sonnet-5`); route Claude Code; size/raise Foundry quota. Purely additive — no re-architecture.
4. **Phase 3 — Harden & scale:** Optional IP allowlist / Front Door, refine budgets, capacity review, evaluate PTUs if needed.

---

*Technical design in `TDD.md`.*

# HostedModels — Internal LLM Gateway

A centrally governed **LLM gateway** in Azure that lets employees use AI coding
tools against company-controlled, in-tenant models — with identity-based access,
per-developer/team cost controls, and metadata-only logging.

> **Status: Proof-of-Concept / evaluation.** This repo is a validated design + a
> deployable-skeleton for a time-boxed PoC that produces a **go / no-go** decision
> before any production rollout. Bicep compiles clean; it has not been deployed
> end-to-end.

## What it is

A self-hosted **LiteLLM** proxy on **Azure Container Apps** fronting **Microsoft
Foundry** models. It exposes one endpoint (OpenAI- and Anthropic-compatible) that
approved tools point at. Only the gateway is public; models, database, secrets,
and logs are private (VNet + private endpoints).

- **Launch (PoC):** **Australia East, GPT-class only** — Azure OpenAI `gpt-5.4`,
  standard Azure billing. Tools: Continue, Cline, OpenCode (OpenAI-format).
- **Not available in AU:** open-weight (Qwen — SKU/quota) and **Claude** are absent
  from all Australia regions; in-tenant Claude is East US 2 / Sweden Central only.
  Adding them means leaving AU residency (a Phase-2 decision).
- **Phase 2 (non-AU):** Hosted-on-Azure **Claude** via Azure Marketplace/CCU →
  enables **Claude Code** — but only in a non-AU region.
- **Dropped:** GitHub Copilot (SaaS-locked; can't route through the gateway).

## Repository layout

```
docs/
  PRD.md              Product requirements + locked decisions
  TDD.md              Technical design + architecture diagram
  EVALUATION.md       PoC plan + go/no-go success criteria
  ONBOARDING.md       Pilot participant setup guide
  READOUT-TEMPLATE.md End-of-pilot decision one-pager
infra/
  main.bicep          Orchestrator (thin) + main.bicepparam
  modules/            network · identity · monitoring · keyvault · postgres · ai · containerapp
  litellm-config.yaml Model routing + metadata-only logging + budgets
  teardown.ps1        RG delete + purge soft-deletables for test cycles
  README.md           Deploy steps, TODOs, create/delete-cycle guidance
```

## PoC → production path

1. **Phase 0 — Foundation:** deploy infra (VNet + private endpoints, Container Apps,
   Postgres, Key Vault, Log Analytics, GPT `gpt-5.4` deployment) in **Australia East**.
2. **Phase 1 — Gateway MVP (GPT-only):** LiteLLM live, virtual keys, budgets,
   metadata logging, streaming; pilot 5–8 engineers on OpenAI-format tools.
3. **Phase 2 (non-AU) — Add Claude + Claude Code:** in East US 2 / Sweden Central
   (Claude isn't in AU), Marketplace/CCU subscription, quota sizing. Trades AU residency.
4. **Phase 3 — Harden & scale:** IP allowlist / Front Door (optional), provisioning
   automation, capacity review.

## Quickstart

```powershell
# Validate the templates (no Azure login needed)
az bicep build --file infra/main.bicep

# Plan against a real subscription
az login
$env:PG_ADMIN_PASSWORD='<pw>'; $env:LITELLM_MASTER_KEY='<key>'; $env:AZURE_AI_API_KEY='<key>'
az deployment group what-if -g <rg> -f infra/main.bicep -p infra/main.bicepparam

# Deploy
az deployment group create -g <rg> -f infra/main.bicep -p infra/main.bicepparam

# Tear down a test iteration
./infra/teardown.ps1 -ResourceGroup <rg>
```

See `infra/README.md` for the must-resolve TODOs (AI-Services key bootstrap,
config mounting) and `docs/ONBOARDING.md` to connect a tool.

## Prerequisites

- Azure CLI (`az`) with Bicep, and permissions to create the resources.
- An Azure Marketplace subscription is required **only** for Phase 2 (Claude).

## Key references

- Design rationale & decisions → `docs/PRD.md`, `docs/TDD.md`
- What "validated" means → `docs/EVALUATION.md`

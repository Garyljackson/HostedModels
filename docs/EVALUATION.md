# Evaluation Plan — Internal LLM Gateway Proof of Concept

**Status:** Draft v1
**Owner:** garyljackson@gmail.com
**Last updated:** 2026-07-11
**Companions:** `PRD.md`, `TDD.md`

---

## 1. Purpose

This is a **time-boxed proof of concept** to validate whether a self-hosted LiteLLM gateway fronting Azure/Foundry models is worth deploying for internal coding tools. It produces evidence for a **go / no-go / iterate** decision. It is **not** a production rollout.

The system under evaluation is described in `PRD.md` and `TDD.md`. This document defines **what "validated" means** and how we measure it.

## 2. Hypotheses to validate

1. **Technical:** blessed coding tools work through the gateway against in-tenant Foundry models, with streaming, routing, keys, budgets, and metadata logging all functioning.
2. **Adoption:** the developer experience is good enough that engineers actually use it and want to keep it.
3. **Cost:** spend is acceptable, predictable, and attributable per developer/team, with enforceable caps.
4. **Governance:** inference stays in-tenant, no prompt/completion content is retained, and access is identity/key-gated — demonstrably.

## 3. PoC scope

**Governance-representative** — the PoC keeps the private-networking + in-tenant posture so the governance hypothesis is genuinely tested (not stubbed).

### In scope
- LiteLLM gateway on Azure Container Apps (VNet-integrated), Bicep-provisioned.
- **Models:** **GPT-class only** — Azure OpenAI `gpt-5.4` in **Australia East** (standard Azure billing). Open-weight (Qwen) and Claude are **not deployable in AU** and are out of scope for this PoC (see `PRD.md` regional-availability risk).
- **Tools:** OpenCode, Cline, Continue (OpenAI-format blessed set).
- Private endpoints for Foundry, Postgres, Key Vault, logging; public gateway ingress with virtual-key auth.
- Per-dev/per-team budgets, rate limits, metadata-only logging, self-service usage view.
- Manual/scripted key provisioning for the pilot cohort.

### Deferred past the PoC (only if it graduates)
- Claude models + Claude Code (+ Marketplace/CCU subscription, Foundry quota increase).
- Full Entra-group provisioning automation (manual key issuance is fine for the pilot).
- HA / multi-region, Front Door/WAF, PTUs.

## 4. Pilot design

| Parameter | Proposed |
|-----------|----------|
| Participants | 5–8 engineers (mix of seniority; volunteers who will actually use it) |
| Duration | 3–4 weeks of active use |
| Tools | OpenCode, Cline, Continue (each participant picks ≥1) |
| Models | GPT-class (`gpt-5.4`) — single model available in AU |
| Region | **Australia East** (in-country residency) |

## 5. Success criteria (go/no-go)

Thresholds below are proposed defaults — confirm/adjust before the pilot starts.

### 5.1 Technical feasibility (mostly binary)
| Criterion | Target |
|-----------|--------|
| All 3 tools connect and complete real coding tasks via the gateway | Pass |
| Streaming works end-to-end (no buffering-induced failures) | Pass |
| Model routing by name; swap model without client change | Pass |
| Virtual keys authenticate; unauthenticated/over-budget requests rejected | Pass |
| Gateway errors not attributable to upstream quota | < 2% of requests |

### 5.2 Developer experience & adoption
| Criterion | Target |
|-----------|--------|
| Time to first successful request (following onboarding README) | < 15 min |
| Active usage during pilot | ≥ 70% of participants active ≥ 3 days/week |
| Perceived latency & output quality (weekly survey, 1–5) | median ≥ 4 |
| "Would you want to keep using this?" | ≥ 70% yes |

### 5.3 Cost
| Criterion | Target |
|-----------|--------|
| Per-dev/per-team spend visible and accurate | Reconciles with Azure bill within ~5% |
| Budget caps prevent overspend | Demonstrated (request blocked at cap) |
| Extrapolated monthly cost at full <50-dev scale | Within agreed budget expectation |

### 5.4 Governance & security
| Criterion | Target |
|-----------|--------|
| Inference runs on in-tenant Foundry deployments | Verified (config + traffic) |
| Backend resources not publicly reachable; only gateway ingress exposed | Verified (network test) |
| Metadata-only: no prompt/completion content in any store | Verified (audit of Postgres/Log Analytics/Storage) |
| Keys tied to identities; revocation takes effect | Verified |

## 6. Measurement & data collection

- **Technical:** test checklist + observed error rates from Log Analytics (metadata).
- **Adoption:** LiteLLM usage metrics (requests/active days per key) + a short weekly survey.
- **Cost:** LiteLLM spend reports reconciled against the Azure cost view; extrapolation model.
- **Governance:** a documented verification pass — network reachability tests, a data-sink audit confirming no content, and a key-revocation test.

## 7. Exit decision framework

At the end of the timebox, score each of the four dimensions:

- **Go →** all four meet threshold. Proceed to a production plan: add Claude/Claude Code (Marketplace/CCU + quota), provisioning automation, and hardening (`PRD.md` §12 Phase 2–3).
- **Iterate →** core value is proven but specific gaps exist (e.g. DX friction, a cost surprise). Fix the named gaps and re-test the affected dimension(s).
- **No-go →** a driver fundamentally fails (e.g. governance can't be demonstrated, or engineers won't adopt). Stop or pivot the approach.

Document the score, evidence, and decision in a short evaluation readout.

## 8. Risks to evaluation validity

| Risk | Mitigation |
|------|------------|
| Single-model / Claude absence skews judgment | The AU PoC runs one model (`gpt-5.4`) — the only one deployable in-country. It tests the **gateway pattern + DX**, not model breadth or Claude Code. Don't read "single model / not Claude" as "gateway failed"; multi-model routing and Claude are gated by AU regional availability, not the design. |
| Too few / unrepresentative participants | Recruit genuine daily coders across seniority; 5–8 minimum. |
| Short timebox hides adoption drop-off | Track daily active use, not just onboarding; 3–4 weeks minimum. |
| Cost extrapolation inaccurate | Base projection on measured per-dev tokens, note assumptions, add a margin. |
| Governance "verified" by assertion, not test | Require the concrete verification pass in §6, not a design review alone. |

---

*System design in `TDD.md`; product context in `PRD.md`.*

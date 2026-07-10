# PoC Readout — LLM Gateway Evaluation

Fill this in at the end of the pilot. Keep it to ~1–2 pages. Criteria come from
`EVALUATION.md` §5. Decision framework in `EVALUATION.md` §7.

---

**Pilot window:** `<start> – <end>`
**Participants:** `<n>` engineers (`<mix/teams>`)
**Tools used:** `<Continue / Cline / OpenCode / ...>`
**Models:** `gpt-class` (Australia East; single model — Qwen/Claude not available in AU)
**Author / date:** `<name> / <date>`

## Recommendation

> **Decision: `GO` / `ITERATE` / `NO-GO`**
>
> `<2–4 sentence rationale — what the evidence shows and why this decision.>`

## Scorecard

| Dimension | Result | Evidence (link/where) |
|-----------|--------|-----------------------|
| Technical feasibility | Pass / Partial / Fail | |
| Developer experience & adoption | Pass / Partial / Fail | |
| Cost | Pass / Partial / Fail | |
| Governance & security | Pass / Partial / Fail | |

## 1. Technical feasibility

| Criterion | Target | Result |
|-----------|--------|--------|
| 3 tools connect & complete real tasks | Pass | |
| Streaming works end-to-end | Pass | |
| Model routing / swap without client change | Pass | |
| Keys authenticate; over-budget/unauth rejected | Pass | |
| Gateway errors (non-quota) | < 2% | |

Notes: `<...>`

## 2. Developer experience & adoption

| Criterion | Target | Result |
|-----------|--------|--------|
| Time to first successful request | < 15 min | |
| Active usage | ≥ 70% active ≥ 3 days/week | |
| Perceived latency & quality (1–5) | median ≥ 4 | |
| "Would you keep using it?" | ≥ 70% yes | |

Notes / representative quotes: `<...>`

## 3. Cost

| Criterion | Target | Result |
|-----------|--------|--------|
| Per-dev/team spend accurate | Reconciles within ~5% of Azure bill | |
| Budget caps prevent overspend | Demonstrated | |
| Extrapolated monthly cost @ full <50-dev scale | Within budget expectation | |

Cost summary: total pilot spend `<$>`; per-active-dev/day `<$>`; projected monthly
at `<n>` devs `<$>`. Assumptions: `<...>`

## 4. Governance & security

| Criterion | Target | Result |
|-----------|--------|--------|
| Inference on in-tenant Foundry deployments | Verified | |
| Backends not publicly reachable; only gateway exposed | Verified (network test) | |
| Metadata-only: no content in any store | Verified (sink audit) | |
| Keys tied to identity; revocation works | Verified | |

Verification method & findings: `<...>`

## Key findings & risks discovered

- `<what surprised us — good or bad>`
- `<quota / latency / cost / DX issues>`
- `<anything that would change the production design>`

## Decision & next steps

- **If GO →** production plan: add Claude/Claude Code (Marketplace/CCU + quota
  sizing), provisioning automation, hardening (`PRD.md` §12 Phase 2–3). Owners/dates: `<...>`
- **If ITERATE →** named gaps to fix and re-test: `<...>`
- **If NO-GO →** rationale and alternative considered: `<...>`

## Validity notes

- This PoC tested the **gateway pattern** in **Australia East** with a **single
  model** (GPT `gpt-5.4`) — the only model deployable in AU. Open-weight (Qwen)
  and Claude/Claude Code were out of scope (not available in AU). "Single model /
  not Claude" ≠ "gateway failed" — judge the pattern and DX, not model breadth.
- `<other caveats: pilot size, duration, representativeness>`

---
date: 2026-08-20
topic: recovery-v1-timing-hooper
status: ready-for-product-review
origin: docs/plans/2026-08-13-001-feat-gt5-physio-dict-file-capture-plan.md (complete)
physio_evidence: capture:POC-2026-08-16-physio-probe
parallel: docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md
---

# Recovery v1 — sleep timing + Hooper-4 (post physio POC)

## Summary

Ship the first honest Recovery product cut that Fathom can ground on GT5-A07 **without** Huawei Health exclusive bind: **TruSleep overnight timing** + **Hooper-4 morning wellness**. Do **not** surface overnight HRV, sleep RR, sleep SpO₂, or overnight avg HR as companion metrics — physio capture POC marked those `ABSENT-companion` / `ABSENT-overnight-summary` (watch UI may still show them). No opaque recovery score. No intensity coaching.

This is the product packaging of what the physio POC unlocked and what it closed. Hooper-4 requirements remain the detailed survey SoT; this doc is the **parent Recovery v1** scope a product agent should review before planning/implementation.

## Problem Frame

Owner wants morning recovery guidance from the GT5 companion. Research framed a scientific minimum as:

1. Subjective Hooper quartet (sleep quality, fatigue, soreness, stress)
2. Sleep quantity + regularity
3. Overnight HR + HRV vs personal baseline (later)

Physio capture on GT5-A07 (`POC-2026-08-16`) proved companion overnight summaries for HRV / sleep HR / RR / sleep SpO₂ are **not** available on dict/`SLEEP_DETAILS` / `sleep_data` key maps. Interval HR exists but had **0% overlap** with last night’s TruSleep window — so minting overnight RHR from `0x0B ∩ sleep` would be dishonest. Exclusive Huawei Health bind is incompatible with Fathom pairing.

Without a deliberate product cut, agents either over-claim Health-class physiology or under-ship a usable recovery loop. Recovery v1 closes that gap: ship what we own, empty what we don’t, keep future physio as a separate track.

## Actors

- A1. Owner-athlete: Syncs overnight sleep, answers morning Hooper-4, reviews Sleep under Recovery
- A2. Product agent: Reviews this doc, resolves review questions, opens plan / feature work
- A3. Implementation agent: Builds against locked requirements on the sleep/feel product branch (not this physio-probe worktree)

## Key Flows

- F1. Overnight sleep lands
  - **Trigger:** Gate A session ready; owner Sync (or equivalent product sync)
  - **Steps:** TruSleep `sleep_state` timing SoT → overnight session on Recovery · Sleep list/detail
  - **Outcome:** Date, local window, duration visible; no fake Quality / HRV / SpO₂ chips
  - **Covered by:** R1–R4, R10

- F2. Morning Hooper-4
  - **Trigger:** Unanswered overnight session for that `mergeKey`
  - **Steps:** Four ordinal prompts (sleep quality → fatigue → soreness → stress) → persist once → hide
  - **Outcome:** Structured wellness record for baselines / later P4
  - **Covered by:** R5–R9 (detail SoT: Hooper-4 brainstorm)

- F3. Honest empty for watch-only physio
  - **Trigger:** Owner looks for HRV / overnight SpO₂ / RR / sleep avg HR in companion
  - **Steps:** No product tiles that imply companion ownership; optional locked “advanced metrics” chrome only if already in IA — never invent values
  - **Outcome:** Trust preserved; Health/watch tiles remain watch-side only
  - **Covered by:** R10–R13

## Requirements

**Sleep timing (already largely shipped — product must keep as SoT)**
- R1. Overnight sleep **timing** (begin/end/duration, local window) comes from TruSleep file SoT (`sleep_state`), not message-path ownership after the Aug 11 flip
- R2. Recovery · Sleep list/detail show date, window, and duration for overnight sessions without a Quality score
- R3. Sleep regularity / quantity for future morning copy may use owned timing only (multi-night history when already available)
- R4. Stages remain honest: show when message-path (or later owned TruSleep stage decode) exists; never invent REM/deep from flags; thin/empty hypnogram is allowed

**Hooper-4 morning wellness**
- R5. Replace single emoji feel-on-wake with four items: sleep quality, fatigue, muscle soreness (DOMS), stress
- R6. One consistent ordinal scale for all four (prefer **1–7** Hooper-style); all four required before treat-as-answered
- R7. Persist once per overnight `mergeKey`; naps stay out of survey
- R8. Complete in ≤ ~10–15s; local prefs only; no wellness text in Sentry/hex logs
- R9. Never claim or derive DOMS/soreness from the watch

**Honesty locks from physio POC (hard)**
- R10. Do **not** productize companion overnight HRV, sleep RR, sleep SpO₂ summaries, or overnight avg sleep HR from dict/`SLEEP_DETAILS`/`sleep_data` keys or from `0x0B ∩ sleep_state` until a future capture promotes those rows
- R11. Do **not** mint overnight RHR / sleep HR charts by intersecting interval FitnessData HR with TruSleep windows based on current evidence (0% last-night overlap on `POC-2026-08-16`)
- R12. Do **not** treat path-2 post-HR “spo2 hint” bytes as sleep SpO₂
- R13. UI copy must not imply Fathom reads Health overnight tiles; watch-only metrics stay unlabeled as companion data

**Product framing**
- R14. No opaque numeric “Recovery 73”-style score in this cut
- R15. No hard / easy / rest intensity coaching in this cut
- R16. Optional morning **explanation** card is allowed only if it uses owned inputs (sleep hours/window + Hooper-4) and never invents ANS/HRV/SpO₂ contributors — product review chooses include vs defer (see Outstanding Questions)
- R17. Bottom IA remains Home | Recovery | Workouts with Recovery **Vitals | Sleep**; this cut does not add Food or a new Recovery child tab

**Privacy**
- R18. Keep physio-probe privacy rules for any diagnostic code left in tree: route/len/keys/tag histograms only — never PPG/ACC bodies, full HR/SpO₂ series, or `sleep_data` bodies in logs/fixtures

## Acceptance Examples

- AE1. **R1–R2.** After overnight Sync, Sleep shows a session with local window and duration; no Quality number
- AE2. **R5–R7.** Unanswered overnight session shows Hooper-4; after all four saved, survey does not reappear for that `mergeKey`
- AE3. **R10–R13.** Sleep detail / list never display companion overnight HRV, RR, sleep SpO₂, or overnight avg HR values derived from ABSENT pipes
- AE4. **R14–R15.** No recovery score badge and no workout intensity suggestion on morning surfaces
- AE5. **R9.** Copy never says the watch measured muscle soreness

## Success Criteria

- Owner can run a daily recovery loop: Sync sleep → see timing → answer Hooper-4 in under ~15s
- ≥1 week of complete Hooper-4 + overnight timing records accumulates without claiming false physio
- Product and support copy can state clearly what Fathom owns vs what remains watch/Health-only
- Downstream baseline/P4 work can consume four named wellness fields + sleep timing without parsing emoji or inventing HRV

## Scope Boundaries

**In**
- Recovery v1 product scope lock post physio POC
- Hooper-4 feel upgrade (implementation may already be planned via parallel handoff)
- Honest empties / copy for ABSENT overnight physio
- Keeping TruSleep timing as sleep SoT

**Out**
- Companion overnight HRV / RR / sleep SpO₂ / overnight avg HR product surfaces
- Re-arming product continuous-HR sleep charts from `0x0B ∩ sleep` as overnight SoT
- Huawei Health exclusive bind / Health SDK as Fathom data path
- 10-minute Health-clone full Sync daemon
- P4 Good/Moderate/Caution composite **with** ANS contributors
- P5 training-load / intensity join
- Parsing PPG/`sleep_data` into invented avgHrv
- Physio probe UI as a shipping feature (debug-only may remain)

## Key Decisions

| Decision | Lock | Rationale |
|----------|------|-----------|
| Recovery v1 data foundation | Timing + Hooper-4 only | Matches owned GT5 companion evidence + science minimum layers 1–2 |
| Overnight physio in companion | Absent / deferred | `ABSENT-overnight-summary` after dict + sleep_data observe + path-2; watch UI ≠ companion SoT |
| Overnight HR from interval ∩ sleep | Do not ship | 0% sleep-window overlap on capture night |
| Recovery score | No opaque score | Explainability > fake precision |
| Intensity coaching | Out | Needs load model + owner trust; Hooper alone ≠ hard/easy |
| Physio POC worktree | Research complete; not the Recovery UI ship branch | Probe branch stays evidence/docs; product feature lands on sleep/feel line |
| Parallel Hooper-4 brainstorm | Remains detailed survey SoT | This doc parents product packaging; do not fork conflicting survey rules |

## Alternatives considered

1. **Wait for HRV before any Recovery ship** — Rejected: subjective + sleep quantity is already an evidence-backed daily loop; waiting indefinitely stalls the product.
2. **Proxy overnight HR from daytime `0x0B`** — Rejected: dishonest given 0% last-night overlap; risks teaching wrong baselines.
3. **Require Huawei Health bind for Recovery** — Rejected: conflicts with Fathom exclusive companion pairing.
4. **Ship P4 Good/Moderate/Caution now from Hooper + sleep only** — Deferred to product review (R16 / Outstanding Questions): useful if copy stays explanatory; risky if it looks like a medical/ANS score.

## Dependencies / Assumptions

- TruSleep file timing SoT remains shipped behavior on the Recovery Sleep product branch
- Hooper-4 detailed requirements: `docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md`
- Physio evidence SoT: `docs/catalogs/gt5-a07-full-metrics.md`, `docs/experiments/gt5-a07-full-metrics-probe-matrix.md`, `docs/handoffs/2026-08-13-gt5-physio-dict-file-capture-handoff.md` (status complete)
- Implementation should **not** land on `feat/gt5-physio-dict-file-capture` as the product ship branch; use the sleep/feel Recovery line (or a new branch off main that includes TruSleep SoT)
- Future incremental FitnessData keepalive for **daytime** HR is a separate experiment and must not silently redefine overnight SoT

## Outstanding Questions

### Resolve Before Planning

- [Affects R16][Product] Include a morning **explanation** card (owned sleep hours + Hooper summary, no score), or ship survey + sleep list/detail only and defer any morning “state” framing?
- [Affects packaging][Product] Treat this as one feature PR (“Recovery v1”) that includes Hooper-4, or two sequenced features (Hooper-4 first, then Recovery honesty/copy pass)?

### Deferred to Planning

- [Affects R5–R8][Technical] Atomic vs resume-partial Hooper save (see Hooper-4 AE2)
- [Affects R4][Needs research] Whether empty hypnogram copy needs a one-line trust note this cut
- [Affects future][Needs research] Whether incremental `0x0B` keepalive can ever fill sleep-window HR — out of v1 acceptance

## Evidence appendix (for product review)

| Signal | Watch UI (Health not opened) | Companion after POC |
|--------|------------------------------|---------------------|
| Sleep timing | Present | **Present** — TruSleep `sleep_state` SoT |
| Overnight HRV | Present on Sleep tile | **ABSENT-companion** |
| Overnight avg HR | Present on Sleep tile | **ABSENT** as overnight summary; interval HR not in sleep window |
| Sleep RR | Present on Sleep tile | **ABSENT-companion** |
| Sleep SpO₂ | Present on Sleep tile | **ABSENT-companion** |
| Sleep score | Present on watch | Not companion SoT; Quality UI stays locked |
| Interval / daily HR | — | Diagnostic `interval-proxy` only; product Sync still skips merging as sleep SoT |

Capture id: `POC-2026-08-16-physio-probe` (GT5-A07).

## Next Steps

1. Product agent reviews this doc + linked Hooper-4 + physio handoff
2. Resolve the two **Resolve Before Planning** questions
3. → `/ce-plan` (or equivalent) for Recovery v1 on the sleep/feel product branch
4. Do not reopen companion overnight physio as in-scope without new device evidence

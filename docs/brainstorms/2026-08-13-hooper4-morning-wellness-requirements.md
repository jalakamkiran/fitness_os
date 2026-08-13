---
date: 2026-08-13
topic: hooper4-morning-wellness
status: ready-for-plan
origin: recovery-analytics brainstorm (closed early; physio POC parallel)
---

# Hooper-4 morning wellness (feel upgrade)

## Summary

Replace the single emoji feel-on-wake survey with a **four-item athlete wellness check** (Hooper-style): sleep quality, fatigue, muscle soreness, stress. Persist once per overnight sleep session for baseline learning. No intensity coaching. No DOMS from the watch.

## Problem Frame

Owner currently decides hard/easy days mostly by ad-hoc feel (sore / tired / mood) and rarely looks at data. A single global emoji is too coarse for recovery learning. Evidence (Saw et al.; Hooper & Mackinnon wellness index) supports a short multi-item self-report as the highest-sensitivity daily recovery input — and **muscle soreness cannot come from GT5**.

## Actors

- A1. Owner-athlete: answers morning prompts after overnight sleep sync
- A2. Recovery · Sleep UI: shows survey once per unanswered overnight session

## Key Flows

- F1. Morning multi-prompt
  - **Trigger:** Overnight sleep session present and no wellness answer for that `mergeKey`
  - **Steps:** Answer sleep quality → fatigue → soreness → stress (same scale each) → persist once → hide survey
  - **Outcome:** Structured wellness record available for baselines / future P4
  - **Covered by:** R1–R6

## Requirements

- R1. Replace single “How do you feel waking up?” emoji row with **four prompts**: sleep quality, fatigue, muscle soreness (DOMS), stress
- R2. Use one consistent ordinal scale for all four (prefer **1–7** Hooper-style; map UI labels honestly). Do not invent medical cutoffs
- R3. Persist **once per overnight session** `mergeKey` (same once-per-key rule as today); naps remain out of survey unless product later changes overnight-only rule
- R4. Completing the set requires all four answers before treat-as-answered (no partial “done” that blocks re-prompt forever)
- R5. Keep survey ≤ ~10–15 seconds; no long RESTQ/POMS batteries
- R6. Migrate or supersede legacy single-string feel keys without orphaning TruSleep SoT feel migration paths
- R7. No recovery **intensity suggestion** (hard/easy/rest) in this cut
- R8. Do not claim or derive DOMS / soreness from Huawei watch metrics
- R9. Privacy: local prefs only; no wellness text in Sentry/hex logs

## Acceptance Examples

- AE1. **R1–R4.** Given an unanswered overnight session, survey shows four items; after all four saved, survey does not reappear for that session
- AE2. **R4.** Given user answers only two items and leaves, reopening still prompts for remaining items (or full set if atomic-save chosen — pick one in plan and test it)
- AE3. **R3.** Nap-only day does not show survey (overnight-only preserved)
- AE4. **R6.** Sessions with legacy single feel string still load without crash; new shape is canonical going forward
- AE5. **R7–R8.** UI copy never says watch measured soreness or recommends workout intensity

## Success Criteria

- Owner can complete Hooper-4 most mornings in under ~15s
- ≥1 week of complete four-item records accumulates without data-model churn blocking physio POC
- Downstream recovery engine can read four named fields per night without parsing emoji labels

## Scope Boundaries

- **In:** Feel upgrade UI + persistence + tests + migration from single-string feel
- **Out:** GT5 HR/HRV/RR/SpO₂ capture POC (parallel track)
- **Out:** Baseline engine maturity UI, P4 Good/Moderate/Caution composite, training-load join, intensity coaching
- **Out:** Collapsing back to one tap after 30 days (optional later)

## Key Decisions

- Dimensions locked: **sleep quality, fatigue, soreness, stress** (no motivation in v1)
- Soreness is **subjective-only** (watch cannot provide DOMS)
- P4 intensity coaching deferred until training-stress / muscular-load work exists
- Physio capture POC runs **in parallel**, not blocking this cut

## Dependencies / Assumptions

- Implementation branch with sleep/feel: `feat/recovery-sleep-detail` (feel does not live on `feat/vitals-auto-tracking-enable`)
- Existing overnight-only + once-per-`mergeKey` behavior remains the trigger model
- TruSleep file SoT feel rekey/migration must keep working for the new payload shape

## Next Steps

→ `/ce-plan` or implement from `docs/handoffs/2026-08-13-hooper4-feel-upgrade-handoff.md`

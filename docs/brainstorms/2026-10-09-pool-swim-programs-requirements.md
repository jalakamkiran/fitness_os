---
date: 2026-10-09
topic: pool-swim-programs
status: planning
origin: /ce-brainstorm session 2026-10-09 (Programs after pool swim detail + Local AI Coach deferral)
plan: docs/plans/2026-10-09-002-feat-pool-swim-programs-plan.md
related:
  - docs/brainstorms/2026-10-08-pool-swim-detail-redesign-requirements.md
  - docs/architecture/swim-session-insight-contract.md
  - docs/brainstorms/2026-09-14-local-ai-coach-requirements.md
  - docs/brainstorms/research/2026-10-09-programs-pm-discovery-brief.md
  - docs/brainstorms/research/2026-10-09-fathom-data-for-programs.md
  - docs/brainstorms/research/2026-10-09-programs-gamification-progress.md
  - docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md
  - docs/brainstorms/research/2026-10-09-usms-masters-workout-sources.md
  - docs/brainstorms/research/2026-10-09-swim-data-sources-four-questions.md
  - docs/brainstorms/research/2026-10-09-opensource-swim-formats-and-community-practice.md
  - docs/plans/2026-10-09-002-feat-pool-swim-programs-plan.md
  - docs/design/programs-prototype/index.html
---

# Pool swim Programs — milestone-led training plans

## Summary

Ship a **pool-only Programs** capability in Fathom that turns athlete intake (goal distance, target time, horizon, sessions/week) into a followable local plan: a **milestone proof-swim spine**, curated warm-up / main-set / cool-down sessions between proofs, soft recovery warnings when other sports load is high, and a full progress loop (daily chores, forgiving streaks/XP/levels, efficiency / habit / volume scorecards). Plan craft is **dataset/template + rules**, not Local AI Coach.

---

## Problem Frame

Fathom already holds rich pool-swim history and session insight, but the athlete still improves by unstructured self-pushing. That path does not reliably produce larger continuous distances or target times. Generic template apps ignore owned history; conversational coaches are a separate bet and are explicitly out of this cut. Without a structured, milestone-proof program that adapts dates when proofs slip — and that respects multi-sport life with soft warnings — the instrument stack never becomes athletic improvement.

---

## Actors

- A1. **Owner-athlete**: Sole dogfood user; sets a pool goal, follows prescribed sessions, completes or skips chores, attempts proof milestones, reviews progress scorecards.
- A2. **Paired watch (GT5)**: Source of completed pool swims and other workouts via sync; Programs consumes completed sessions as adherence and proof evidence.
- A3. **Programs planner (system)**: Deterministic local engine that baselines the athlete, places milestones, fills training days from a curated pool-session vocabulary, and adjusts milestone dates when proofs fail or are delayed.
- A4. **Progress loop (system)**: Tracks chores, streaks/XP/levels, and efficiency/habit/volume scorecards; streaks stay forgiving; milestone clock stays honest.

---

## Key Flows

- F1. **Create program**
  - **Trigger:** A1 chooses to create a new pool program.
  - **Actors:** A1, A3
  - **Steps:** UI discloses pool-only; A1 enters goal distance, target time, horizon, sessions/week; A3 runs baseline cascade (history → guided test if thin → self-report last); A3 proposes milestone ladder + first block of sessions; A1 confirms and activates.
  - **Outcome:** One active program with visible milestones, adaptive target dates, and today’s chore.
  - **Covered by:** R1–R8, R20

- F2. **Daily chore / training day**
  - **Trigger:** A1 opens Programs on a day with a prescribed session (or reviews today’s chore from Home/Programs).
  - **Actors:** A1, A2, A4
  - **Steps:** See warm-up / main / cool-down structure; optionally soft-warn if other-load/recovery looks heavy; complete via synced swim match or manual done/skip/adjust; progress loop updates chores and forgiving streak/XP.
  - **Outcome:** Adherence is recorded without nuking the program on a single miss.
  - **Covered by:** R9–R14, R18–R19

- F3. **Proof milestone**
  - **Trigger:** Plan reaches a proof-swim day (e.g. attempt 1.1 km continuous / time-bounded distance).
  - **Actors:** A1, A2, A3, A4
  - **Steps:** A1 attempts the proof; result is evaluated pass/fail from synced swim or honest manual confirm; on pass, celebrate and unlock next block; on fail or delay, milestone dates slip and the next training block is reshaped; efficiency/habit/volume scorecards update but do not gate the first dogfood proofs unless a proof fails.
  - **Outcome:** Progress is felt at milestone grain; ultimate goal-day is a derived forecast, not the success clock.
  - **Covered by:** R15–R17, R21–R23

- F4. **Baseline repair**
  - **Trigger:** History is insufficient to trust a baseline at create time, or mid-program confidence collapses.
  - **Actors:** A1, A3
  - **Steps:** Prescribe guided test set; if still insufficient or athlete cannot test, collect self-report; re-anchor ladder.
  - **Outcome:** Plan remains honest about evidence quality.
  - **Covered by:** R4–R6

---

## Requirements

**Intake and venue**
- R1. Program creation MUST require goal **distance**, **target time** for that distance, **horizon**, and **sessions/week**.
- R2. Creation MUST disclose that Programs v1 is **pool only**.
- R3. A1 MAY have at most one **active** program at a time in v1 (replacing or completing the prior active program is allowed; exact replace UX left to planning).

**Baseline**
- R4. Baseline MUST prefer **Fathom pool-swim history** when it is sufficient to estimate current continuous distance and sustainable pace/time.
- R5. When history is insufficient, Programs MUST prescribe a **guided baseline test set** before locking the ladder.
- R6. When history and guided test are both insufficient or unavailable, Programs MUST accept **self-report** as last resort and label confidence as low.
- R7. “Insufficient history” criteria MUST be explicit and athlete-visible at a high level (e.g. too few recent pool sessions / no continuous distance signal) — exact thresholds deferred to planning/research.

**Plan craft (non-agent)**
- R8. Plan generation MUST use a **curated pool session vocabulary + periodization rules** (MySwimPro / Garmin Coach–style), not Local AI Coach or a cloud LLM.
- R9. Every prescribed training session MUST include **warm-up, main set orchestration, and cool-down** (not distance-only chores).
- R10. Session volume/intensity MUST be sized from baseline, goal, horizon, and sessions/week so the plan is plausible for A1’s stated weekly budget.
- R11. Research-backed template rules MAY be distilled into Fathom-owned content; v1 MUST NOT depend on licensing a third-party workout feed.

**Milestones and adaptation**
- R12. The primary success object is the **milestone proof swim** (progressive distance/time proofs), not a fixed ultimate goal-day ceremony.
- R13. The planner MUST place proof milestones between training blocks (dogfood example: ~1000 m capacity → ~1200 m proof inside ~2–3 weeks when intake matches).
- R14. Forecast completion of the ultimate goal MAY be shown, but MUST update when milestone dates move.
- R15. When a proof is **failed or delayed**, milestone dates MUST slip and the following block MAY be reshaped; a single routine chore miss MUST NOT by itself move milestone dates.
- R16. Efficiency, habit, and volume MUST be tracked as scorecards and MAY inform coaching copy / chore emphasis; they MUST NOT gate early dogfood proofs unless a proof fails.

**Multi-sport and recovery**
- R17. When other workouts (e.g. badminton, strength) or recovery signals look heavy, Programs MUST **soft-warn** and keep the prescribed swim unless A1 skips or adjusts.
- R18. Hard auto-downgrade of swim days from other-load is **out of v1** (deferred multi-sport scheduling).

**Progress loop (full)**
- R19. v1 MUST include daily/session **chores** with done / skipped / adjusted states that feed adherence.
- R20. v1 MUST include **streaks, XP, and levels** that are **forgiving** (cosmetic progress; skips do not harshly punish).
- R21. v1 MUST surface **efficiency, habit, and volume** scorecards alongside milestone progress.
- R22. Split rules: streaks/XP stay forgiving; **milestone timeline stays honest** to proof outcomes.

**Evidence and honesty**
- R23. Completed pool swims from sync SHOULD satisfy chores/proofs when they match the prescription intent; inventing paces or distances is forbidden.
- R24. Programs MUST reuse existing swim session insight / metrics as inputs where available (seam noted in swim-session-insight contract) without requiring Coach.

**Non-goals wiring**
- R25. Local AI Coach MUST NOT be required to create, advance, or narrate Programs in v1.
- R26. Open-water program generation is out of v1.

---

## Acceptance Examples

- AE1. **Happy create (rich history)** — A1 with recent pool swims showing ~1000 m continuous capacity enters 1200 m, a target time, 3-week horizon, 3×/week. Programs baselines from history (no forced test), shows pool-only disclosure, proposes milestones including a ~1200 m proof, and activates with warm-up/main/cool-down sessions.  
  **Covers:** R1–R4, R8–R10, R12–R13, R2

- AE2. **Thin history → guided test** — A1 has sparse/no usable pool history. Create flow requires a guided baseline swim before locking the ladder; after test sync, milestones generate.  
  **Covers:** R5, R7, F4

- AE3. **Self-report fallback** — A1 cannot complete the guided test. Self-report captures current best distance/time; plan generates with low-confidence labeling.  
  **Covers:** R6

- AE4. **Soft warn, keep chore** — A1 has a hard strength session same day. Programs warns about recovery/load but still shows today’s swim prescription; A1 may skip. Skip does not break the milestone clock by itself; streak remains forgiving.  
  **Covers:** R17–R20, R15, R22

- AE5. **Proof fail slips dates** — A1 fails the 1200 m proof. Milestone dates move later; next block reshapes; XP/streak do not erase prior progress.  
  **Covers:** R15–R16, R22, F3

- AE6. **No Coach dependency** — With Local AI Coach disabled/absent, A1 can still create and follow a full program.  
  **Covers:** R8, R25

---

## Success Criteria

- S1. Dogfood: from a truthful ~1000 m baseline, A1 can run a short-horizon program aimed at a ~1200 m proof inside ~2–3 weeks with clear milestone pass/fail.
- S2. Every training day shows a complete pool session structure (warm-up / main / cool-down), not a bare distance target.
- S3. A1 can state current milestone, next proof, and whether they are ahead/behind the adaptive forecast without opening Coach.
- S4. Missed chores feel recoverable (forgiving streaks); failed proofs feel consequential (dates move).
- S5. Plan craft is explainable from template/rules + intake + baseline — no agent required.

---

## Scope Boundaries

- Pool-only programs (UI discloses); open water deferred
- No Local AI Coach integration for create/advance/narrate in v1
- No hard auto-reschedule from other sports/recovery (soft-warn only)
- No licensed third-party workout API dependency in v1
- No cloud LLM plan generation
- “Healthier life” in v1 = swim-session hygiene (warm-up/cool-down, sustainable load) + recovery soft-warns — **not** a nutrition/lifestyle coaching product
- Multi-program library, social leaderboards, and coach marketplace deferred

---

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Product spine | Milestone-backcast ladder | Progress is felt at proof grain; goal-day is derived |
| Session quality | Curated template vocabulary | Trustworthy sets like MySwimPro/Garmin without agent |
| Scorecards | Full loop, light gating | XP/streaks/scorecards ship; don’t gate early proofs |
| Coach | Explicitly excluded v1 | Plan craft is dataset/rules |
| Other sports | Soft-warn | Deeper multi-sport scheduling later |
| Miss rules | Split | Forgiving streaks; honest milestone dates |
| Baseline | History → test → self-report | Maximize owned data; stay honest when thin |
| Dataset strategy | Distill into Fathom-owned rules | Avoid license dependency; research informs content |

---

## Dependencies / Assumptions

- Pool swim history, interval metrics (pace/SWOLF/strokes), and session insight seam exist or are shipping on main.
- Other-workout types and recovery signals are available enough to soft-warn; exact signal math is planning/research.
- A1 is the sole dogfood athlete; content quality judged on their pool reality first.
- External research (periodization, CSS/threshold practice, public datasets, community training patterns) informs the template rules pack — may conclude **build our own distilled dataset** rather than ingest Garmin/MySwimPro proprietary feeds.

---

## Outstanding Questions

Resolved in brainstorm dialogue (see Key Decisions). Remaining items are **Deferred to Planning / research packs** (not Resolve-Before-Planning blockers):

- Exact “sufficient history” thresholds
- Proof matching rules (how closely a synced swim must match a prescription); inventory notes no chore↔workout link exists yet — plan must add `(workoutNumber, startTime)` binding + manual confirm for continuity proofs
- Continuous-distance baseline: rest/length timestamps may be absent — guided tests should prefer non-stop swims so session totals are clean
- Soft-warn: badminton type code unknown; load/TE confirmed mainly on strength/run — use owner-relative thresholds; Hooper-4 not on this branch
- XP/level curve: research proposes weekly streaks + Rest Passes, positive-only XP, level cost `100 × min(level, 8)` — adopt vs tune in planning; resolve pause→milestone-date behavior and lifetime vs per-program level
- Session vocabulary: research proposes ~20 set patterns + warm-up/cool-down templates; CSS (400/200) as pace anchor; rung +15–25% every 2–3 weeks — calibrate in dogfood
- Intake honesty: warn when pace goal needs a longer horizon than distance-capacity rungs (e.g. 1000→1200 m in 2–3 weeks vs 22:00 goal-time needing months)
- Dataset strategy confirmed: distill Fathom-owned rules; no USA Swimming/Garmin/MySwimPro license path for v1

---

## Research follow-ups (orchestrated)

Separate research docs (same brainstorm wave):

1. Training algorithms + datasets + community practice → `docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md` ✅ (build Fathom-owned rules pack; license nothing)
2. Fathom data inventory for baseline/adherence/proofs → `docs/brainstorms/research/2026-10-09-fathom-data-for-programs.md` ✅
3. Gamification + milestone progress patterns → `docs/brainstorms/research/2026-10-09-programs-gamification-progress.md` ✅
4. PM discovery / product-lens brief → `docs/brainstorms/research/2026-10-09-programs-pm-discovery-brief.md` ✅

---

## Visual aids

```text
Intake (distance, time, horizon, x/week)
        │
        ▼
Baseline: history ──► guided test ──► self-report
        │
        ▼
Milestone ladder (proof swims)  ←── dates slip on proof fail/delay
        │
        ▼
Training blocks: warm-up / main / cool-down  (template vocabulary)
        │
        ▼
Daily chores + soft other-load warn
        │
        ▼
Progress: forgiving streaks/XP/levels + efficiency/habit/volume scorecards
```

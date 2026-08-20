---
date: 2026-08-20
topic: next-day-session-commit-pol-probe
status: ready-to-run
kind: pol-probe
origin: docs/brainstorms/2026-08-20-recovery-v1-timing-hooper-requirements.md
parallel: docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md
---

# PoL Probe: Next-day session commit (paper, no planner)

## Why this probe exists

Recovery v1 (`docs/brainstorms/2026-08-20-recovery-v1-timing-hooper-requirements.md`) is a **data-foundation POC**, not a training-OS POC. It locked:

- Overnight **sleep timing** (TruSleep `sleep_state`) as companion SoT
- **Hooper-4** morning wellness (sleep quality, fatigue, soreness, stress)
- **No** companion overnight HRV / RR / sleep SpO₂ / overnight avg HR
- **No** opaque recovery score
- **No** hard / easy / rest intensity coaching
- P4 morning-state composite and **P5 training-load join** stay out

The owner vision now is a full personal athletic app that **plans tomorrow’s strength / swim / run from sleep and other data**. That is a new product bet. Fathom’s brand lock is still “calm companion for session truth, **not** a loud coach dashboard.” Hooper-4 already records that the owner “decides hard/easy days mostly by ad-hoc feel and **rarely looks at data**.”

If that last sentence is still true, a planner in Fathom is prototype theater. This probe tests the leap **before** any planning UI, engine, or “full app” cut.

**Do not** expand Recovery v1 into coaching because of this vision. Ship Recovery v1 as the honest loop. Run this probe in parallel on paper.

---

## Hypothesis

If the owner completes last-night sleep timing + Hooper-4 each morning and applies a **written next-day rule** (owned inputs only, no software), they will (a) finish the morning commit ritual on most days **and** (b) let the rule change a pre-written session at least twice in a week in a way they still endorse that evening.

One-sentence form: *Sleep hours + Hooper-4 are enough to make me change tomorrow’s strength / swim / run / rest — not just diary how I felt.*

## Risk Being Eliminated

**Behavior + value, not feasibility.** Companion overnight ANS is already known-absent. The unknown is whether a next-day planner is a real job:

1. Will the owner look at data in the morning and **commit** a session, or keep deciding by ad-hoc feel?
2. Will sleep + Hooper ever **disagree** with the weekly skeleton enough to swap sport, cut load, or rest?
3. When it disagrees, is the change later judged as right — or as noise that a load/HRV model would have avoided?

Failure here means: do **not** build a Fathom planner / “full athletic OS.” Keep Recovery v1 as display + survey. Planning stays in the owner’s head or calendar.

## Prototype Type

- [ ] Feasibility Check — already done (physio POC: overnight HRV/RR/SpO₂ absent)
- [x] **Task-Focused Test** — can the owner complete the morning job (read → score → commit tomorrow) without a product?
- [ ] Narrative Prototype
- [ ] Synthetic Data Simulation — follow-on only if this probe passes and rule quality is still in doubt
- [ ] Vibe-Coded PoL Probe — **not first.** A morning card in Fathom is already an MVP-shaped object.

Cheapest harsh truth: paper protocol, 7 training days, zero Fathom feature work.

## Target Users / Audience

Owner-athlete only (n=1). Sports in scope: **strength, swimming, running**. No other users. No stakeholder demo.

## Inputs frozen (what “other data” may mean)

Only signals Fathom can honestly own **today or in Recovery v1**:

| Allowed this probe | Not allowed (would fake WHOOP) |
|--------------------|--------------------------------|
| Sleep window + duration (watch Sleep tile or Fathom Recovery · Sleep) | Overnight HRV / RMSSD |
| Hooper-4 1–7: sleep quality, fatigue, soreness, stress (paper is fine) | Sleep SpO₂, sleep RR, overnight avg HR |
| Yesterday’s completed session type (strength / swim / run / rest) | Training-load / TSS / CTL / ATL |
| A **pre-written 7-day skeleton** (the plan the rule is allowed to amend) | Opaque “Recovery 73” |

If the owner wants to use a watch HRV number they saw on the watch tile, **record it as watch-only** in notes and **do not** let it drive the rule. That is the honesty lock from Recovery v1 R10–R13.

---

## Protocol (7 consecutive mornings with a planned session)

### Before day 1 (15–20 min, once)

Write a **weekly skeleton** for the next 7 days. Each day: sport (`strength` / `swim` / `run` / `rest`) + intended hardness (`hard` / `steady` / `easy` / `technique`). Example only — owner fills real intent:

| Day | Skeleton sport | Hardness |
|-----|----------------|----------|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |
| 6 | | |
| 7 | | |

Print or pin the **rule card**. Do not “improve” the rules mid-week. Mid-week edits invalidate the probe.

### Rule card (owned inputs only)

Use personal typical sleep duration as `T` (last 7 nights if known, else last 3, else owner estimate).

1. **Short sleep:** duration `< T − 90 min` **or** Hooper sleep quality `≥ 6` → next day **cannot** be `hard`. Cap at `easy` in a different sport than yesterday, or `rest`.
2. **Soreness:** muscle soreness `≥ 6` → **no strength**. Choose `swim` / `easy run` / `rest`.
3. **Fatigue stack:** fatigue `≥ 6` **and** (short sleep **or** stress `≥ 6`) → **rest** (not “easy run to sweat it out”).
4. **Else:** keep the skeleton sport + hardness.

If two rules fire, take the more conservative (rest > easy-swap > cap-hardness).

### Each morning (≤ 2 min, before leaving / before first training)

1. Record sleep **begin / end / duration** (Fathom if already showing timing; else GT5 Sleep tile).
2. Score Hooper-4 (1–7, all four required). Higher = worse, Hooper-style.
3. Write the **skeleton session** for today (already on the week card).
4. Apply the rule card **in writing**. Result = **committed session**.
5. Note whether committed ≠ skeleton (`change` / `no-change`) and which rule fired.
6. Do **not** open a planner prototype. Do **not** ask an LLM to coach that morning.

### Each evening (after the session or after skipping)

1. What did you **actually** do? (`match-commit` / `broke-commit` / `did-nothing`)
2. One line: would you still endorse the morning commit? (`yes` / `no` + why)
3. Optional: “I already knew this from feel” (`yes` / `no`) — vanity check. If always yes, the data added no decision.

### Daily log (copy one row per day)

| Date | Sleep h | SQ | Fat | Sor | Str | Skeleton | Committed | Rule fired | Actual | Endorse? | Already knew? |
|------|---------|----|-----|-----|-----|----------|-----------|------------|--------|----------|---------------|
| | | | | | | | | | | | |

Do not commit raw wellness rows to git if they feel too personal. Keep the log local; this doc only stores the protocol and later **aggregates**.

---

## Success Criteria (Harsh Truth)

Need **7 mornings** with a skeleton session (rest days count). Abort and fail if fewer than 5 complete logs.

- **Pass (both must hold):**
  - **Ritual:** morning commit completed in ≤ 2 min on **≥ 6 / 7** days
  - **Decision:** committed ≠ skeleton on **≥ 2 / 7** days **and** evening endorse = `yes` on **≥ 50%** of those change-days
  - **Follow-through:** actual = committed on **≥ 5 / 7** days (a planner you ignore is still a diary)

- **Fail (any one):**
  - Ritual < 5 / 7 (still “rarely looks at data”)
  - 0–1 changes all week (sleep + Hooper never beat the calendar — planner is chrome)
  - Changes happen but evening `no` on **> 50%** of change-days (rule is noise without load/HRV; do not encode it in Fathom)
  - Actual ≠ committed on **≥ 3 / 7** (commit is theater)
  - Owner used watch HRV / Health tiles to override the rule **≥ 2** times (the product would be lying if Fathom shipped that path)

- **Learn (record even on pass/fail):**
  - Which rule fired most (short sleep vs soreness vs fatigue-stack)
  - Which sport was most often protected vs sacrificed (strength vs swim vs run)
  - How often “already knew from feel” = yes — if 6/7, the app adds logging cost without a new decision
  - Whether the job is **next-day amend** (this probe) vs **weekly periodization** (a different product; do not pretend this probe tested that)

## Tools / Stack

- Notes app or a local spreadsheet (not in the Fathom repo)
- GT5 Sleep tile and/or Fathom Recovery · Sleep for **timing only**
- Paper Hooper-4 (UI not required to start)
- This protocol doc
- **No** new Flutter screens, reasoner prompts, recovery score, or workout-plan schema

## Timeline

- **Build:** 0 days (skeleton + print rule card, 20 min)
- **Test:** 7 consecutive mornings (stretch to 10 only if ≥2 days were travel / illness with no skeleton)
- **Analyze:** 1 sitting — fill pass/fail, write learnings, decide the fork below
- **Disposal:** day 8–9 (delete the working log after aggregates land in learnings)

## Disposal Plan

After analysis:

1. Write `docs/learnings/2026-08-2x-next-day-session-commit-probe.md` with **counts only** (compliance, change-days, endorse rate, which rules fired). No daily Hooper numbers in git unless the owner wants them.
2. Delete the local spreadsheet / notes protocol.
3. Do **not** leave a “temporary planner” screen, JSON schema, or reasoner prompt in the app “since we already thought about it.”
4. Recovery v1 honesty locks stay in force regardless of pass/fail.

## Fork after the probe (pre-commit, so results cannot be spun)

| Result | What you are allowed to do next | What you are not allowed to do |
|--------|----------------------------------|--------------------------------|
| **Fail — no ritual** | Ship Recovery v1 survey + sleep list only. Treat planning as out of Fathom. | Do not add morning coaching chrome to “nudge” a habit the paper test already lost |
| **Fail — no changes** | Keep Recovery as diary. Optional later: P4 **explanation** card (R16) with no session prescription | Do not build a next-day workout planner |
| **Fail — bad endorsements** | Recheck science: you likely need load and/or true overnight HRV, which GT5 companion does **not** own | Do not encode this rule card in product copy |
| **Pass** | *Then* consider a **second** probe: one morning card (vibe-coded or Recovery explanation surface) that **amends today/tomorrow** using the same rules — still not a full athletic OS | Do not jump to periodization, food, or multi-week programming; that is a new hypothesis |

A “full fledged app for athletic fitness” is **not** the next story after Recovery v1. It is at best the story after **this** probe passes **and** a later P5/load probe exists. Strength / run as first-class Fathom sports remain their own tracks (IA already says swim-first, Run/Strength later).

## Owner

Owner-athlete (Kiran). Accountable for running 7 mornings, scoring pass/fail against this page, disposing the log, and refusing to start a planner branch on a fail.

## Status

- [x] Hypothesis defined
- [x] Probe built (paper protocol — this doc)
- [ ] Users recruited (n=1, self)
- [ ] Testing complete
- [ ] Learnings documented
- [ ] Probe disposed

---

## Quality checklist

- [x] **Lightweight:** 20 min setup, no engineering
- [x] **Disposable:** working log deleted after learnings; no code
- [x] **Narrow Scope:** one job — morning data → next session commit
- [x] **Brutally Honest:** fail if you skip mornings, never change the plan, or regret the changes
- [x] **Tiny & Focused:** smaller than Recovery v1, which is already the product cut
- [x] **Falsifiable:** numeric pass/fail above
- [x] **Clear Owner:** owner-athlete

## Anti-patterns this probe is designed to prevent

- **Prototype theater:** a polished “tomorrow’s workout” Home module that never changed a session
- **MVP disguised as probe:** vibe-coding a planner because Fathom already has Workouts + Recovery tabs
- **Skipping the failure threshold:** “I’ll know if it feels useful”
- **Reopening physio:** using watch HRV as if Fathom owned it (`POC-2026-08-16`)
- **Conflating Recovery v1 with P5:** shipping intensity coaching inside the sleep/Hooper PR

## Related

- Recovery v1 requirements: `docs/brainstorms/2026-08-20-recovery-v1-timing-hooper-requirements.md`
- Recovery v1 handoff: `docs/handoffs/2026-08-20-recovery-v1-timing-hooper-handoff.md`
- Hooper-4 SoT: `docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md`
- Physio evidence: `docs/handoffs/2026-08-13-gt5-physio-dict-file-capture-handoff.md`
- Brand / IA: `docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md` (session truth, not coach dashboard)

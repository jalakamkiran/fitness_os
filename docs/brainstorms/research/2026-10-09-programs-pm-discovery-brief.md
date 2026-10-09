---
date: 2026-10-09
topic: pool-swim-programs-pm-discovery
status: draft
origin: PM discovery + product-lens pass (research follow-up #4 of the Programs brainstorm wave)
related:
  - docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md
  - docs/brainstorms/2026-10-08-pool-swim-detail-redesign-requirements.md
  - docs/architecture/swim-session-insight-contract.md
  - docs/brainstorms/2026-09-14-local-ai-coach-discovery.md
scope: discovery brief only — not a PRD. Requirements are locked upstream; this brief frames, stress-tests, and sharpens them.
method: discovery-process (frame → evidence gaps → probes → decide), jobs-to-be-done (functional/social/emotional + pains/gains), opportunity-solution-tree (outcome → opportunities → solutions → experiments), competitive-research-snapshot (Fact / Inference / Assumption labels, cited URLs)
---

# Fathom Pool Swim Programs — PM Discovery Brief

> **What this is.** A discovery + product-lens brief written *after* the Programs requirements were locked (`status: ready-for-plan`). It does **not** reopen scope. Local AI Coach integration and open water remain out (R25, R26). Its jobs: (1) name the job Programs is hired for, (2) say what we'd have to see to call the dogfood a success or a kill, (3) position against the alternatives the athlete could hire instead, and (4) be honest about how little evidence a single dogfooder gives us.
>
> **Discovery mode.** n=1 owner-athlete (A1). Same stance as the Local AI Coach discovery: we substitute **temporal evidence** (many sessions over weeks, milestone outcomes) and **pre-registered predictions** for cross-person saturation. Anything that reads like market validation is a hypothesis, not a finding.
>
> **Tags:** 🔶 = assumption we're acting on. 🔵 = open question. **[F]** Fact (cited), **[I]** Inference, **[A]** Assumption.

---

## 0. Executive summary

- **The job:** *"Turn my swim history into steady, provable progress toward a longer continuous swim / faster time — so I stop self-pushing blind and can say 'I did it' at a defined moment."* The unit of progress is the **proof swim**, not the calendar or a streak.
- **The bet:** a deterministic, local, Coach-free Programs engine — baseline from owned history → milestone proof ladder → warm-up/main/cool-down sessions — will move A1 from ~1000 m continuous toward a ~1200 m proof inside ~2–3 weeks more reliably than unstructured self-pushing.
- **Where Fathom is different (and where it is not):** competitors already do *adaptive plans* well (MySwimPro, FORM HeadCoach, Garmin Triathlon Coach's swim sessions) and *template libraries* (TrainingPeaks). Fathom's defensible wedge is **(a) plan anchored in the athlete's own local history, (b) a milestone-proof spine with an honest clock, (c) no agent/no cloud, (d) it works with the owner's Huawei GT5 data stream**, which none of the named competitors targets. The wedge is real for A1, narrow as a market claim, and should be stated that way.
- **Biggest risks:** (1) plan craft is "good enough but generic" and A1 reverts to self-pushing; (2) the gamification loop (XP/levels/scorecards) is scope that doesn't serve the proof job; (3) proof-matching and baseline thresholds are guessed, so a proof result could be disputed by the athlete himself; (4) n=1 means we can build the right thing for the wrong reason.
- **Recommendation:** ship the full loop as locked (it's already decided), but **instrument the dogfood so the proof ladder is the success measure and everything else is judged by whether it helped reach proofs.** Pre-register predictions and kill criteria *before* the first block starts (§2, §5).

---

## 1. Problem and Jobs-to-be-Done (A1, owner-athlete)

### 1.1 Problem statement (hypothesis form)

> We believe **a multi-sport owner-athlete with a Huawei GT5 and a deep local pool-swim history** struggles to **increase continuous swim distance and hit target times** because **improvement currently depends on unstructured self-pushing; nothing converts owned history into a sequenced, honest plan**, leading to **plateaued capacity, inconsistent pool sessions, and instrument data that never becomes athletic improvement**.

Grounding **[F, repo]**: requirements Problem Frame ("improves by unstructured self-pushing… does not reliably produce larger continuous distances or target times"); Pool swim detail redesign already delivers verdict + next-action tip per session but **explicitly defers Programs** (A3 "future Programs consumer"); the Local AI Coach discovery records the owner "decides hard/easy days mostly by ad-hoc feel and rarely looks at data" **[F, repo]**.

**Honest caveat 🔶:** that last observation cuts both ways. If A1 rarely consults data, a program that must be opened daily can fail the same way the coach ritual might. Programs has an advantage the coach doesn't — it *tells him what to swim* rather than asking him to read data — but "opens the app on swim days" is still unproven.

### 1.2 Situation (when the job arises)

"When I'm about to swim and have no structure — or when I've just finished a swim that didn't move me past my current ceiling — I want a clear next session and a defined moment where I'll know I've leveled up."

### 1.3 Jobs

| Type | Job | Rooted in |
|---|---|---|
| **Functional** | Extend my continuous pool distance (e.g. ~1000 m → ~1200 m) within a short horizon | Requirements S1, F1 |
| **Functional** | Know exactly what to swim today (warm-up / main set / cool-down) without designing it myself | R9, S2 |
| **Functional** | Verify whether I actually hit a milestone, with evidence from my own synced swims | R12, R23 |
| **Functional** | Keep training sane across swim + badminton + strength without a schedule war | R17–R18 |
| **Emotional (seek)** | Feel *directed* instead of aimless in the water; feel progress at a grain I can feel (a proof passed) | Brainstorm Key Decisions ("progress felt at proof grain") |
| **Emotional (seek)** | Trust the plan because I can see why it is what it is (baseline → ladder → session) | S5, R7 |
| **Emotional (avoid)** | Avoid guilt-spiral from a missed day; avoid fake progress from inflated streaks | R15, R20, R22 |
| **Emotional (avoid)** | Avoid the sense that "the app is making up numbers" | R23 ("inventing paces or distances is forbidden") |
| **Social** | Be able to say credibly "I swam 1.2 km continuous" / "I'm on the 1.2 → 1.5 block" — private-to-self first | 🔶 weak — A1 is sole user; leaderboards deferred |

**Social job honesty 🔶:** there is no social audience in v1. The social job here is mostly *self-identity* ("I'm a swimmer who trains with structure"). Do not overweight it; do not let it justify leaderboards/sharing (explicitly deferred).

### 1.4 Pains (current alternatives: self-push, ChatGPT chat, generic plans)

- **Challenges:** no sequencing — each session is whatever feels right; distance ceilings stall.
- **Costliness:** designing sets by hand (or copy-pasting data into ChatGPT and re-deriving context each time).
- **Common mistakes:** attempting a "proof" distance without preparation; going hard in a week of heavy badminton/strength; skipping warm-up/cool-down.
- **Unresolved problems:** apps that don't know my history; apps that don't support my watch (see §3); adaptive apps that opaquely rewrite my plan.

### 1.5 Gains (what "better than today" looks like)

- **Expectations:** a plan that reflects my real baseline on day one (not a questionnaire guess).
- **Savings:** never designing a set again; one place for "what do I do today."
- **Adoption factors:** frictionless — sessions appear without setup; matched automatically from synced swims.
- **Life improvement:** healthier swim hygiene (warm-up/cool-down, sustainable load) — *not* lifestyle coaching.

### 1.6 Job-to-be-done statement

> **When** I have a pool goal beyond what I can swim today and a few sessions a week to spend on it, **I want** a plan built from my own swim history that sequences sessions toward defined proof swims, **so I can** reliably extend my continuous distance and *know* when I've actually done it.

### 1.7 What A1 is "firing" if Programs works

Hiring Programs displaces: (1) unstructured self-pushing, (2) ad-hoc ChatGPT set-writing, (3) a generic subscription app that wouldn't ingest GT5 data cleanly. It does **not** displace the Local AI Coach (not hired for this).

---

## 2. Opportunity hypothesis and success metrics (dogfood)

### 2.1 Opportunity hypothesis

> If A1 follows a **milestone-led, history-baselined, template-driven** pool program for a short horizon (~2–3 weeks), then **A1 will pass the first proof swim (~1.1–1.2 km continuous) more reliably and with more confidence than the pre-Programs baseline**, because (a) the plan is sized from owned history (R4, R10), (b) sessions are complete and purposeful (R9), (c) the proof is a defined moment (R12–R13), and (d) skips don't punish him into abandonment (R15, R20).

**Differentiated sub-hypotheses** (each can be falsified separately — see §6):

| ID | Hypothesis | Primary risk it addresses |
|---|---|---|
| H1 | History-based baseline (no test needed) is accurate enough that A1 agrees with it ("yes, that's about my 1000 m") | Baseline credibility (R4–R7) |
| H2 | Template + rules sessions feel purposeful, not generic | Plan craft (R8–R10) |
| H3 | Proof-grain progress is more motivating than streak/XP alone | Spine choice (R12 vs R20) |
| H4 | Soft-warn + "keep the swim" doesn't annoy and doesn't get ignored | Multi-sport honesty (R17–R18) |
| H5 | A1 opens Programs on swim days without being nagged | Ritual adoption 🔶 |
| H6 | Forgiving streaks + honest milestone clock feels "fair" after a miss/failed proof | Split rules (R22, S4) |

### 2.2 Success metrics (dogfood, pre-registered)

**North-star (outcome):** *Proof pass with confidence.* A1 completes at least the first proof swim and can state, unprompted, the current milestone, next proof, and ahead/behind status (S1, S3).

| Tier | Metric | Target (initial; adjust at plan time) | Source of truth |
|---|---|---|---|
| **Outcome** | First proof swim attempted within ±3 days of scheduled date | ≥ 1 attempt inside horizon | Program record + synced swim |
| **Outcome** | First proof pass (≈1.1–1.2 km continuous) inside ~2–3 wk horizon | Pass (or fail with documented, plausible reason) | Synced swim match / honest manual confirm (R23) |
| **Outcome** | Net continuous-distance gain vs baseline at end of horizon | ≥ +100 m *or* a clear explanation if not | Session history |
| **Adoption** | Prescribed sessions completed (done/matched) ÷ prescribed, per week | ≥ 70% of sessions/week target | Chores (R19) |
| **Adoption** | Swim days on which A1 opened Programs before or after the swim | ≥ 70% 🔶 | Lightweight local analytics (opt-in dogfood counter) |
| **Quality (trust)** | "Baseline felt right" self-rating at activation (1–5) | ≥ 4 | One-tap capture at confirm |
| **Quality (trust)** | "Today's session felt purposeful" self-rating (1–5), sampled | median ≥ 4 | One-tap after chore |
| **Quality (trust)** | Disputed proof matches (A1 says "that swim should/shouldn't have counted") | 0–1 total | Manual log; flags rule defects |
| **Behavior** | Plan abandonment (no chore interaction ≥ 7 days while program active) | 0 | Chores |
| **Guardrail** | Invented paces/distances shown to A1 | 0 (hard) | Review / invent-guard (R23) |
| **Guardrail** | Soft-warn shown but A1 reports it was wrong/noisy ≥ 2 times | < 2 | Manual log |
| **Anti-metric** | Streak length, XP, level, scorecard views | **Reported, never a success criterion** (R16, R22) | — |

### 2.3 Pre-registration (to blunt self-confirmation)

Before the first block, write down (in the plan or run log): predicted proof outcome, predicted number of sessions A1 will complete, which session type he expects to dislike, and what he'd have done without Programs this week. Re-read at end of horizon. This mirrors the Local AI Coach discovery's one-tap "what would I have done otherwise" gap — **the same instrumentation gap applies here**: without a "what I would have swum" capture, we can't separate *Programs changed my behavior* from *Programs narrated what I'd have done anyway*.

---

## 3. Competitive snapshot

**Scope.** Decision supported: *positioning Programs and choosing what to build vs copy.* Not a market-size or pricing play (single-user product). Evidence is from public vendor pages retrieved 2026-10-09; no hands-on use of competitors by the author.

### 3.1 Competitor snapshots

#### MySwimPro
- **Positioning:** "Personalized swim training plans… 100% unique to you, flexible, and adaptive" — coach algorithm adjusts next workouts as you log. **[F]** ([support article](https://support.myswimpro.com/en/articles/9741919-new-improved-personalized-swim-training-plans-more-personalized-than-ever), [coach page](https://www.myswimpro.com/coach))
- **Relevant capability:** Event-based schedules with taper; workout swaps; mid-plan edits without losing progress; sync with Apple Watch, Garmin, Wear OS; tiers around $99/yr–$199/yr (higher tier adds dryland, test sets, technique drills). **[F]** ([Coach Plus](https://www.myswimpro.com/coach-plus))
- **Likely strength:** Mature plan UX and set vocabulary; claimed scale ("2.5M swimmers"). **[F for claim]** ([Coach Plus](https://www.myswimpro.com/coach-plus))
- **Likely weakness (for A1):** Plan sized from questionnaire + app-logged swims, not an owner's local deep history; no listed Huawei sync **[I — absence on vendor page, not verified in-app]**; "adapts quietly" is the opposite of an honest milestone clock **[I]**.
- **Key source:** https://www.myswimpro.com/coach-plus

#### Garmin "Swim Coach" (swim half of Garmin Triathlon Coach)
- **Positioning:** Adaptive plans in Garmin Connect; swim sessions adapt using comfortable swim distance, goal, sleep/recovery/recent training. **[F]** ([Garmin Rumors](https://garminrumors.com/garmin-adds-triathlon-coach-to-adaptive-training-lineup-here-are-the-details/), [AquaPlan review](https://www.aquaplan.fit/blog/garmin-coach-swim))
- **Relevant capability:** Freestyle-focused varied-intensity sessions; scheduled with run/bike; guided on compatible Garmin watches; Garmin also supports scheduled pool workouts via Connect calendar. **[F]** ([Swim 2 manual](https://www8.garmin.com/manuals/webhelp/garminswim2/EN-US/GUID-84D39EEF-3552-49DF-9709-1256E3F03886.html))
- **Likely strength:** Free; multisport scheduling with recovery signals (the thing Fathom defers via R18). **[F]**
- **Likely weakness (for A1):** Requires Garmin hardware/ecosystem **[F]**; swim is a component of a *triathlon* program, freestyle-centric **[F]**; it's a plan-adapter, not a proof-milestone spine **[I]**.
- **Key source:** https://www.aquaplan.fit/blog/garmin-coach-swim

#### FORM (HeadCoach 2.0 / Premium)
- **Positioning:** Adaptive plans + post-swim insight + next-swim direction; built around FORM goggles and app. **[F]** ([press release Nov 2025](https://www.formswim.com/blogs/media/form-introduces-headcoach%E2%84%A2-2-0-expert-coaching-tailored-to-your-goals), [Plans help](https://support.formswim.com/hc/en-us/articles/42290261828499-What-are-HeadCoach-Plans))
- **Relevant capability:** Race plans back-scheduled from a date into Base/Build/Taper; plan adjusts for shortened/extended swims, user can accept/reject changes; imports TrainingPeaks/TriDot workouts; ~$9.99–$15/mo. **[F]** ([Premium](https://www.formswim.com/pages/premium))
- **Likely strength:** Closest analogue to Fathom's "insight → next action → plan" loop; best-in-class swim-specific coaching content. **[I]**
- **Likely weakness (for A1):** Tied to FORM goggles/ecosystem **[F]**; backcasts from a *race date* rather than milestone proofs **[F/I]**; cloud/subscription.
- **Key source:** https://support.formswim.com/hc/en-us/articles/42290261828499-What-are-HeadCoach-Plans

#### TrainingPeaks (plan marketplace + structured swim workouts)
- **Positioning:** Calendar + marketplace of coach-authored swim plans; structured workouts sync to Garmin/Suunto/Wahoo for pool/lap swim; open water unsupported for structured swims. **[F]** ([Help center](https://help.trainingpeaks.com/hc/en-us/articles/9121983425421-Structured-Swim-Workouts-FAQ), [plan example](https://www.trainingpeaks.com/training-plans/other/swimming/tp-337612/8-week-swim-fitness-builder-training-plan-2-swims-per-week-start-any-time))
- **Relevant capability:** Static, periodized, human-authored plans (e.g. 8-week builder → "up to a mile"); drills not supported in structured steps. **[F]**
- **Likely strength:** Breadth of human-written plans; strong multisport calendar. **[I]**
- **Likely weakness (for A1):** Plan is *not* sized from owned history or adapted to proofs; hardware sync list excludes Huawei **[I]**; static dates don't slip honestly.
- **Key source:** https://help.trainingpeaks.com/hc/en-us/articles/9121983425421-Structured-Swim-Workouts-FAQ

#### ChatGPT + self-push (the real incumbent, per Coach discovery)
- **Positioning:** Paste data/context, ask "what should I swim," improvise. **[F, repo]** ([Coach discovery interview prompt: "this is the actual competitor"](../2026-09-14-local-ai-coach-discovery.md))
- **Relevant capability:** Unlimited flexibility, free-form reasoning, set generation on demand.
- **Likely strength:** Zero setup friction; handles any goal phrasing. **[I]**
- **Likely weakness:** No persistence of baseline, no proof ladder, no honest clock, context re-pasted each time, can hallucinate paces/sets **[I]**; ephemeral — nothing records whether the milestone was reached.
- **Key source:** repo Coach discovery.

### 3.2 Quick comparison

| Dimension | **Fathom Programs** | MySwimPro | Garmin (Tri Coach swim) | FORM HeadCoach | TrainingPeaks | ChatGPT + self-push |
|---|---|---|---|---|---|---|
| Target customer | Owner-athlete, GT5, multi-sport, n=1 | Broad swimmers / triathletes | Garmin-wearing multisport | FORM-goggle swimmers | Coached/structured athletes | Anyone with a prompt |
| Core use case | Reach a proof swim; honest ladder | Personalized adaptive plan | Adaptive multisport block | Technique + adaptive plan | Follow purchased plan | Ad-hoc set design |
| Plan input | **Owned local history → guided test → self-report** | Profile + logged swims | Comfortable distance + Garmin data | Objective + FORM swim data | Plan author's assumptions | Whatever I paste |
| Progress object | **Proof milestone (honest dates)** | Plan completion / event date | Plan adaptation | Objective / race date | Calendar completion | None |
| Agent/LLM | **None (deterministic)** | "AI/algorithm" **[F claim]** | Algorithmic | HeadCoach (algorithmic/"expert" claim) | Human-authored | LLM |
| Cloud/subscription | **Local, no subscription** | Subscription | Free in Garmin ecosystem | Subscription | Plan fees + optional premium | Subscription |
| Huawei GT5 | **Native (Fathom sync)** | Not listed 🔶 | No | No | Not in sync list 🔶 | Via manual paste |
| Multi-sport awareness | Soft-warn only (R17–R18) | Limited | **Strong** | Limited | **Strong (calendar)** | Manual |
| Gamification | Forgiving XP/streaks + scorecards | Some | Light | Some | Light | None |
| Main strength | History-anchored + honest clock + privacy | Polish + scale | Free + recovery-aware | Insight loop | Breadth of plans | Flexibility |
| Main weakness | Narrow vocabulary; n=1 proof; fewer sets | Doesn't know my history | Ecosystem lock + tri-centric | Hardware lock | Static | No memory/clock/guardrails |
| Evidence quality | Repo-grounded | Vendor pages | Vendor + review | Vendor pages | Vendor pages | Repo discovery |

### 3.3 Positioning for Fathom (positioning statement)

> **For** a multi-sport owner-athlete who swims with a Huawei GT5 and already has months of pool history,
> **Fathom Programs** is a **local, deterministic swim plan**
> **that** turns that history into a ladder of proof swims and complete sessions — and tells the truth when a proof slips —
> **unlike** MySwimPro, FORM, or Garmin's adaptive plans (which quietly re-plan from their own cloud data and ecosystems) or a ChatGPT chat (which forgets, drifts, and can invent numbers).

**Honest differentiation, ranked by durability:**
1. **Owned-history baseline + Huawei GT5 native** — structural; competitors won't prioritize (but this is a *niche*, not a moat) **[I]**.
2. **Milestone-proof spine with honest dates** — a product-philosophy choice competitors could copy easily **[I]**; durable only because it is coherent with the rest of Fathom (instrument honesty, invent-guards).
3. **No agent / no cloud** — values-based; relevant to A1 and privacy-minded users; *not* a feature competitors lack the ability to match.
4. **Forgiving-streak + honest-milestone split** — nice design point; weak as a differentiator.

**Where Fathom does not need to win:** set-library breadth, technique drills/video, ecosystem-wide multisport scheduling, race-date periodization polish. Copy *vocabulary patterns* from competitors (R8, R11) into Fathom-owned content; don't try to out-curate them.

### 3.4 So what (implications)

- **Strategy:** (1) Lean into proof-ladder + owned-history as the *one* thing the product visibly does better; (2) keep the session vocabulary small and excellent rather than broad (a thin, trusted set beats a large, generic library); (3) borrow FORM/MySwimPro's "accept or reject proposed plan change" pattern for ladder reshapes — it supports honesty.
- **Risks:** (1) competitors' plans are *good enough* that A1's marginal gain from Programs is mostly about convenience of GT5 data; (2) Garmin already does what R18 defers (recovery-aware multisport), which makes Fathom's soft-warn look primitive if compared side by side.
- **Opportunities:** (1) A "proof readiness" signal derived from owned history (e.g. "your last 3 swims suggest you're ≥80% there") is something questionnaire-based apps can't match; (2) honest forecast with slipping dates.
- **Assumptions to validate 🔶:** that MySwimPro/TrainingPeaks genuinely lack usable Huawei GT5 flow for A1 (verify hands-on); that A1 values the honest-clock behavior over adaptive-quiet behavior; that a small curated vocabulary feels purposeful for 2–3 weeks.

---

## 4. Opportunity Solution Tree

**Desired outcome (measurable):** *A1 converts pool history into a verified continuous-distance gain — first proof swim (~1.1–1.2 km) passed inside ~2–3 weeks — and continues into the next block.*

```
OUTCOME: Verified proof-swim progress from owned history, short horizon
│
├─ O1  I don't know what I can actually do (baseline is vague)           ← R4–R7, F1/F4
│   ├─ S1.1  History-derived baseline with visible "why" + confidence     [IN: R4, R7]
│   ├─ S1.2  Guided baseline test set when history is thin                [IN: R5]
│   └─ S1.3  Self-report fallback labeled low confidence                  [IN: R6]
│
├─ O2  I don't know what to swim today, so I improvise or skip            ← R8–R11
│   ├─ S2.1  Warm-up / main / cool-down sessions from curated vocabulary  [IN: R8, R9]
│   ├─ S2.2  Session sizing from baseline × goal × horizon × sessions/wk  [IN: R10]
│   └─ S2.3  Soft "why this session" line tied to the proof it supports   [IN: S5 explainability]
│
├─ O3  Progress is invisible until goal day, and goal-day feels remote    ← R12–R16, R21
│   ├─ S3.1  Milestone proof ladder with defined proof swims              [IN: R12, R13]
│   ├─ S3.2  Honest dates: slip on fail/delay; forecast updates           [IN: R14, R15]
│   ├─ S3.3  Proof evaluation from synced swim match or honest manual     [IN: R23]
│   └─ S3.4  Scorecards (efficiency/habit/volume) alongside milestones    [IN: R21]
│
├─ O4  Misses and heavy weeks derail me (guilt, or overreach)             ← R17–R20, R22
│   ├─ S4.1  Chore states done / skipped / adjusted without nuking plan   [IN: R19]
│   ├─ S4.2  Forgiving streaks / XP / levels                              [IN: R20]
│   └─ S4.3  Soft-warn from other-load/recovery; keep the swim            [IN: R17]
│
└─ O5  I won't trust a plan I can't explain or reproduce                  ← R11, R23–R25
    ├─ S5.1  Fathom-owned distilled rules pack (no licensed feed)         [IN: R11]
    ├─ S5.2  Consume swim-session insight object                          [IN: R24]
    └─ S5.3  Invent-guard: no fabricated paces/distances                  [IN: R23]

OUT OF SCOPE (not on tree by decision): Coach narration (R25), open water (R26),
hard auto-downgrade from other sports (R18), licensed workout feeds, social/leaderboards.
```

### 4.1 Opportunity assessment

| Opp | Evidence strength | Why it matters to the outcome | Weakest assumption |
|---|---|---|---|
| **O1 Baseline** | Medium (repo history exists; thresholds undefined) | Wrong baseline poisons every downstream session and the first proof | 🔶 "Sufficient history" can be defined without per-user tuning (R7 open) |
| **O2 Session guidance** | Medium-high (competitors validate set vocabulary; self-push pain is documented) | Gets A1 into the water with purpose | 🔶 Small vocabulary stays fresh across 6–9 sessions |
| **O3 Proof ladder** | Medium (product-philosophy chosen; no direct validation) | It *is* the outcome | 🔶 Proof matching rules can be fair and unambiguous |
| **O4 Forgiveness / load** | Medium (documented habits; plausible) | Keeps adherence alive | 🔶 Soft-warn is useful, not noise |
| **O5 Trust/explainability** | Medium-high (honesty culture throughout Fathom) | Prevents "ChatGPT drift" | 🔶 A1 reads the "why" |

**Product-lens note on O3 vs O4:** the locked scope spends heavily on O4 (full XP/levels/streaks/scorecards) while the outcome is O3. That is a conscious trade (Key Decisions: "Full loop, light gating"). The brief's stance: **accept it, but treat O4's cosmetic layer as the first thing to cut or simplify if the proof job slips** (§5, kill/descope triggers).

### 4.2 Candidate first experiments (cheapest first; see §6)

| Exp | Tests | Cost |
|---|---|---|
| E1 Retro baseline replay: run the baseline rule on A1's last 90 days; does the output match his own sense (~1000 m)? | S1.1, H1 | Hours (offline script/spreadsheet) |
| E2 Paper program: hand-render 1 week of sessions from the intended vocabulary for A1; he swims 2 of them | S2.1–S2.3, H2 | 1 evening + 2 swims |
| E3 Proof-match replay: run the proof-matching rule over past long swims; check false pass/fail | S3.3 | Hours |
| E4 Soft-warn replay: on past weeks with badminton/strength, would the warn have fired, and was it right? | S4.3, H4 | Hours |

**Selected POC (highest signal per cost):** E1 + E3 together (they validate the two numerically risky rules before any UI is built), then E2 as a paper pass.

---

## 5. Risks and kill criteria

### 5.1 Risk register

| # | Risk | Likelihood | Impact | Why | Mitigation |
|---|---|---|---|---|---|
| R-1 | **Plan feels generic / template-y** | Med | High | Small vocabulary + deterministic rules vs adaptive competitors | E2 paper pass; keep vocabulary small but curated; surface "why this session" |
| R-2 | **Baseline wrong → first proof fails for the wrong reason** | Med | High | Thresholds undefined (R7); single-user tuning | E1 replay; show baseline + confidence; allow A1 to correct with one-tap |
| R-3 | **Proof matching disputed** | Med | High | R23 SHOULD-match language is soft; real swims are messy (rests, mixed strokes) | E3 replay; define continuous-distance criteria explicitly; "honest manual confirm" as escape hatch |
| R-4 | **Gamification dilutes the spine** | Med | Med | R20–R21 are scope without direct proof impact | Anti-metrics (§2); descope trigger below |
| R-5 | **A1 doesn't open it (ritual risk)** | Med | High | Documented habit: rarely looks at data | Put today's chore on Home (F2 trigger already allows); measure swim-day opens |
| R-6 | **Soft-warn noise** | Med | Low-Med | Other-load signal math is deferred | E4 replay; cap frequency; make dismissible |
| R-7 | **Short-horizon (2–3 wk) confounding** | High | Med | 1000→1200 m may happen from simple repetition; can't attribute | Pre-register; capture "what I'd have swum"; extend to a second block before concluding |
| R-8 | **n=1 overfit** | High | Med | Rules tuned to A1's pool reality | Label confidence; keep rules parameterized; invite 1–2 peer swimmers as bonus signal only |
| R-9 | **Injury/overreach from ladder pushing** | Low-Med | High | Progressive distance proofs + multi-sport load | Soft-warn; cap weekly increase in rules pack; "adjust" chore state; don't prescribe beyond baseline step cap |
| R-10 | **Competitor parity makes this redundant even for A1** | Low-Med | Med | MySwimPro/FORM could cover 80% | Hands-on trial of one competitor for a week as a calibration (§6) |

### 5.2 Kill / pivot / descope criteria (set before dogfood starts)

**Kill (stop building toward this shape; re-open discovery):**
- **K1.** After a full first block (2–3 wks, ≥ 6 prescribed sessions), A1 completes **< 40%** of prescribed sessions *and* cannot name a reason other than "plan was wrong/useless." *(Plan fails the adoption job.)*
- **K2.** **Two consecutive baselines** rejected by A1 as materially wrong (> ±15% on his own estimate) even after history/test paths. *(Baseline engine isn't trustworthy.)*
- **K3.** A competitor trial (MySwimPro or FORM, ~1 wk) is rated by A1 as **clearly better** on *both* session quality and plan fit, *and* GT5 sync is workable for him. *(Wedge dissolves.)*

**Pivot (change approach, keep the product):**
- **P1.** If proofs repeatedly pass/fail for reasons the rules can't see (messy swims), pivot proof evaluation to **honest manual confirm primary, sync match advisory.**
- **P2.** If sessions feel generic but baseline is right, pivot craft investment from *more vocabulary* to *better "why this session" + small adaptive tweaks* (still deterministic).

**Descope (cut cosmetic layer, keep the spine):**
- **D1.** If by the end of block 1 A1 reports never looking at XP/levels/scorecards and they cost > ~25% of build effort, descope them to a minimal streak + chore tally; keep milestone timeline as-is.

**Guardrail trips (fix before continuing, not a kill):**
- Any invented pace/distance shown (hard fail); more than one disputed proof match; soft-warn noise ≥ 2 reported times.

---

## 6. Evidence gaps and how research packs de-risk

### 6.1 What we do *not* know (single-dogfooder reality)

| Gap | Why it matters | Currently true? |
|---|---|---|
| Does A1 actually follow a plan for 2–3 weeks? | The whole outcome | 🔵 Unknown; documented habit leans to ad-hoc |
| Is A1's ~1000 m ≈ truthful *continuous* capacity? | Baseline R4; proof design | 🔶 Stated in requirements as example, not validated from data |
| What counts as a valid "continuous" swim in GT5 data (rest handling, stroke changes, pool length)? | Proof rules R23 | 🔵 Open (data-inventory pack) |
| How noisy are other-load/recovery signals? | R17 | 🔵 Open |
| Does the template vocabulary feel purposeful across a block? | R8–R9 | 🔵 Untested |
| Does A1 prefer honest-clock over adaptive-quiet planning? | Core design choice (R15, R22) | 🔶 Design stance, not a measured preference |
| Would *anyone else* want this? | Product viability beyond A1 | 🔵 Zero evidence; **explicitly not a gate for v1** |
| Is the "healthier life" framing meaningful at all? | R-scope boundary | 🔵 Treat as swim hygiene only |

**What a single dogfooder can and cannot tell us.** It can validate *internal coherence and fit-to-A1* (does it work for this athlete, with this watch, this history). It cannot validate demand, willingness to pay, onboarding clarity for strangers, or generalizability of the rules pack. All market-level claims in §3 are positioning hypotheses only.

### 6.2 How the research packs de-risk (mapped to the brainstorm's follow-ups)

| Research pack | Gaps it closes | Decision it unlocks | Exit signal |
|---|---|---|---|
| **#1 Training algorithms + datasets + community practice** | Vocabulary size/shape; periodization/CSS practice; safe weekly progression; which sources are citable | R8–R11, R13 (rules pack content; weekly increase caps; proof step size) | A small, cited rules pack: set patterns + progression caps + proof ladder spacing for 1000→1200 m class goals |
| **#2 Fathom data inventory (baseline/adherence/proofs)** | "Sufficient history" thresholds; continuous-distance derivation; sync-match feasibility; other-load signals available | R4–R7, R17, R23–R24; replay experiments E1/E3/E4 | Concrete definitions + a replay on A1's real history showing baseline and proof rules behave sensibly |
| **#3 Gamification + milestone patterns** | XP/streak forgiveness mechanics; milestone UX that doesn't mislead | R19–R22; descope trigger D1 | A small, simple mechanic set whose numbers are tunable; no punitive loops |
| **#4 This brief** | Positioning, JTBD, metrics, kill criteria | Framing for plan; instrumentation list (§2.3) | Pre-registered success/kill criteria |

### 6.3 Additional cheap probes to add (not new scope — validation work)

1. **Retro baseline replay (E1)** and **proof-match replay (E3)** on A1's real swim history before building UI — the two highest-leverage numerical risks.
2. **Paper program (E2):** hand-write one week using the planned vocabulary, swim two sessions, score "purposeful" (1–5). Proves or kills R-1 early.
3. **Competitor calibration week (optional, K3):** use one competitor's plan (e.g. MySwimPro trial) for ~1 week with the GT5 workflow noted. Purpose is calibration, not switching.
4. **"What I'd have swum" capture:** one-tap at chore view or at program activation; resolves the narrate-vs-change ambiguity (§2.3).
5. **Peer bonus signal (optional):** 1–2 swimmer friends read the session cards cold; ask "what would you change?" — treated as bonus color, never as a gate.

---

## 7. Recommended MVP narrative (consistent with locked requirements)

**One-sentence narrative:**
> *Tell Fathom where you want to get to in the pool; it reads your own swim history, lays out a ladder of proof swims, hands you a complete session each swim day, keeps you honest when a proof slips, and cheers you on without punishing a missed day.*

**The loop, end to end (the full loop is the MVP — R19–R22 are in):**

1. **Create (F1):** pool-only disclosure → distance, target time, horizon, sessions/week.
2. **Baseline (F4):** history → guided test → self-report (low confidence); athlete sees *why* (R7).
3. **Ladder:** a ~1200 m proof (example) with intermediate steps; ladder date forecast shown but not worshipped (R12–R14).
4. **Train (F2):** each swim day shows warm-up / main / cool-down; soft-warn if load looks heavy; complete via synced match or manual done/skip/adjust (R9, R17, R19, R23).
5. **Prove (F3):** attempt the proof; pass → celebrate + unlock next block; fail/delay → dates slip, next block reshapes (R15).
6. **Progress loop (A4):** forgiving streaks/XP/levels; efficiency/habit/volume scorecards beside milestones; none gate early proofs (R16, R20–R22).

**Short-horizon dogfood proof (what "done" means for v1 learning):**
- Horizon ≈ 2–3 weeks, 3×/week, from ~1000 m truthful capacity to ~1200 m proof (S1, AE1).
- A1 can state current milestone, next proof, ahead/behind forecast without opening Coach (S3).
- Every training day shows full session structure (S2); a missed chore feels recoverable, a failed proof feels consequential (S4).
- Explainable from rules + intake + baseline, with Coach disabled (S5, AE6).

**What the narrative deliberately doesn't claim:** no "AI coach," no "adaptive to your recovery," no multi-sport scheduling, no open water, no social. It is a **plain, honest swim-program engine** whose edge is *your* data and an *honest clock*.

**Sequence recommendation (planning-level, not scope change):**
1. Replay experiments E1/E3 (+E4 if cheap) from research pack #2 → lock thresholds.
2. Rules pack from research pack #1 → small vocabulary + progression caps.
3. Build the spine first (create → baseline → ladder → chore → proof → slip/pass), then the cosmetic loop (XP/levels), then scorecards — so that **if time or attention runs out, what's shipped still proves the job** (guards against R-4 / D1).
4. Pre-register predictions; run block 1; review against §2 and §5 criteria; only then decide on block 2 or scope changes.

---

## Appendix — Source notes

- **Repo [F]:** `docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md` (locked R1–R26, AE1–AE6, S1–S5); `docs/brainstorms/2026-10-08-pool-swim-detail-redesign-requirements.md` (Programs deferred; insight seam); `docs/brainstorms/2026-09-14-local-ai-coach-discovery.md` (n=1 discovery mode, ChatGPT as real competitor, "rarely looks at data").
- **Web [F], retrieved 2026-10-09:** MySwimPro Coach/Coach Plus and support article; Garmin Triathlon Coach coverage and Swim 2 manual; AquaPlan review of Garmin Coach SWIM; FORM HeadCoach 2.0 press release, HeadCoach Plans and Premium support pages; TrainingPeaks structured swim FAQ and sample swim plans. Pricing/feature claims are vendor-stated and may change; verify before any external use.
- **Not verified:** hands-on behavior of any competitor with Huawei GT5 data; any competitor's internal algorithm; market share/user counts beyond vendor claims.
- **Skills applied (substance, not a new framework):** discovery-process (frame → evidence → probes → decide), jobs-to-be-done (functional/social/emotional, pains/gains), opportunity-solution-tree (outcome → opportunities → solutions → experiments, POC selection), competitive-research-snapshot (Fact/Inference/Assumption labels, comparison schema, so-what), write-prd (structure cues only).

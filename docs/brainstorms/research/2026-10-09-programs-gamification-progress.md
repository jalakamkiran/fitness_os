---
date: 2026-10-09
topic: pool-swim-programs-gamification-progress
status: research-complete
type: research
informs: R19–R22 (progress loop), R15–R16 (milestone honesty / scorecards), F2, F3
origin: docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md ("Research follow-up #3")
---

# Programs: gamification and milestone-progress research

## TL;DR

1. **Split the game layer from the clock, visibly.** The strongest pattern across Duolingo, Strava, Apple Rings, MySwimPro and PushFit is that *streaks forgive and the underlying goal does not lie*. Fathom should render two different object types: **a forgiving "habit layer"** (chores, weekly streak, XP, level) and **an honest "capability layer"** (milestone ladder with dates that only proofs can move). Give them different visual treatments and say so once in a "Rules of the clock" sheet.
2. **Weekly streak, not daily.** Swim programs are 2–4 sessions/week with built-in rest. Strava, Nike Run Club and MySwimPro all use weekly streaks. A daily streak would punish the plan itself.
3. **Forgiveness should be automatic, not a purchase or a button.** Duolingo's freeze data shows slack raises retention; PushFit and Apple (90-day ring pause) show the no-button variant. Recommended: a **half-the-sessions floor per week** plus **auto-applied Rest Passes** (2 at program start, +1 per full week, cap 3). No currency, no wagers, no leagues.
4. **XP is a receipt for showing up and attempting, never for meters swum, and never negative.** The proof *attempt* pays XP whether it passes or not. A fail costs dates (honest) but costs zero XP, streak or level (forgiving).
5. **Short programs need an early win and level-ups that land on proofs.** A 2–3 week program cannot lean on streaks (max 3 weeks). Use block-progress bars, a reasoned head start (+50 XP for locking the baseline), a first proof by ~day 8–10 if the planner allows, and a curve tuned so level-ups coincide with proofs.
6. **Failure is data, not a verdict.** State the fact ("1,120 m of 1,200 m, your longest ever"), show what carried the athlete, give a concrete retry date plus an autonomy choice, and never touch XP/streak/level. Setback research points to self-efficacy and self-compassion as the levers that stop one lapse becoming abandonment.
7. **Scorecards inform emphasis, never access.** Three small cards (Habit, Volume, Efficiency), no composite score (Home explicitly bans composites), each with one deterministic "focus line" that feeds the next chore header. Nothing gates a proof. Efficiency must be matched-pace to avoid the SWOLF glide trap.

---

## 1. What the reference products actually do (and what to steal or avoid)

Evidence tiers: **[Official]** product docs or first-party blog, **[Study]** peer-reviewed or preprint, **[Vendor/Blog]** secondary commentary, **[Issue]** user reports. Most of the A/B numbers are Duolingo's own and apply to language learners, not swimmers. They are directional evidence, not guarantees.

| Product | Mechanic | What it teaches Fathom | Steal / avoid |
|---|---|---|---|
| **Duolingo** | Daily streak; **streak freeze** equipped in advance fills a missed day, earnable or bought with gems, up to two equipped ([GTM Sauce summary of Duolingo talk](https://gtmsauce.com/tactics/duolingo-let-users-skip-a-day-without-losing-their-streak-up-to-two-days), [Duolingo engineering blog](https://blog.duolingo.com/protecting-streaks-from-site-issues/)). **Weekend Amulet** A/B: +4% one-week return, 5% fewer streak losses ([Duolingo blog](https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals/)). Group PM: streaks cannot rescue a weak product; first 7 days are the fragile window ([Lenny's Newsletter](https://www.lennysnewsletter.com/p/behind-the-product-duolingo-streaks)). | Slack makes the streak *more* durable, and people still value it. Early-week retention matters most, so the first week needs wins. | **Steal:** pre-applied forgiveness, retroactive repair for system problems (watch sync lag = our outage). **Avoid:** purchasable freezes, Streak Wager, loss-framed "streak saver" pushes (these work on retention but are the dark-pattern core). |
| **Duolingo leagues** | Weekly XP leaderboard with demotion. | Qualitative study of Duolingo users reports demotion hits motivated users and pushes XP farming ([arXiv 2203.16175](https://ar5iv.labs.arxiv.org/html/2203.16175)). | **Avoid:** leagues, demotion, anything relative to other people. Sole-athlete app anyway; social leaderboards are already out of scope. |
| **Strava** | Weekly **Streaks**: one activity ≥60 s per Mon–Sun week; any activity type counts; late upload **restores** a missed streak; banners at weeks 2–5 and bigger milestones; banners cannot be disabled ([Strava Help](https://support.strava.com/en-us/articles/15401580-streaks-on-strava)). | Weekly grain + restore-on-late-sync is exactly right for a watch that syncs late. Low bar keeps the streak achievable. | **Steal:** Mon–Sun weeks, retro-matching late syncs. **Avoid:** an un-hideable banner. Add a "hide game layer" setting. |
| **Nike Run Club** | Weekly consistency, plans, weekly/monthly challenges, milestones, personal progress over competition ([Nike](https://www.nike.com/a/running-goals), [Trophy case study, vendor](https://trophy.so/blog/nike-run-club-gamification-case-study)). | Vendor analysis argues weekly streaks suit physically hard activities because breaks come from injury/recovery/travel, not low motivation. Single-source and vendor-written, so treat as reasoning, not proof. | **Steal:** plan + milestones + personal progress, not rivalry. |
| **MySwimPro** | **Weekly Streak** tied to the athlete's own "Number of Swim Days" target; resets if the week falls short; hundreds of distance/workout badges; monthly challenges with leaderboards ([support](https://support.myswimpro.com/en/articles/17252645-your-weekly-streak), [badges](https://blog.myswimpro.com/2019/07/01/achievement-unlocked-new-swimming-badges/), [challenge](https://blog.myswimpro.com/2020/06/29/july-2020-swim-strength-challenges/)). | Closest direct competitor. Their weekly streak is **hard-reset with no forgiveness**, which is a gap Fathom can differentiate on. The streak target is personal (sessions/week), which we inherit from intake. | **Steal:** target = athlete's sessions/week. **Improve:** floor + passes instead of cliff. Badge sprawl is optional. |
| **Apple Activity rings** | Goals editable by weekday; Monday recap with suggested goals; **pause rings up to 90 days without breaking award streaks**; awards for PRs and milestones ([Apple Support](https://support.apple.com/guide/watch/adjust-your-activity-ring-goals-apd29b30023c/watchos), [Track daily activity](https://support.apple.com/guide/watch/track-daily-activity-apd3bf6d85a6/26/watchos/26)). | Declared pause is a first-class concept. Weekly review is where goals adapt, not mid-week. | **Steal:** weekly recap moment, declared pause. |
| **PushFit / Kinoku** (small apps, design pattern only) | Training **earns** rest days into a bank; a miss silently spends one; streak breaks only when the bank is empty; zero buttons; dot row labeled "rest days left" ([PushFit guide](https://pushfit.app/guide/goals)). Planned rest days do not count as misses and the score skips them rather than scoring zero ([Kinoku](https://kinoku.app/features/rest-day)). | The cleanest forgiveness mechanic I found: earned, automatic, visible, honest about remaining balance. | **Steal:** Rest Pass bank, labeled count, plain warning on the last one. |
| **Habitica** | Missed Dailies damage HP overnight; redder tasks hurt more; party bosses punish the group ([GitHub #5773](https://github.com/HabitRPG/habitica/issues/5773), [#3161](https://github.com/HabitRPG/habitica/issues/3161), [#4630](https://github.com/HabitRPG/habitica/issues/4630)). | Users report compounding penalties, multi-day absences hurting more than one day, and shame/avoidance ([user write-up](https://ordovia.app/blog/why-i-left-habitica/)). | **Avoid:** any loss state tied to a miss. This is the anti-pattern. |
| **SuperBetter** | Epic Win (a goal you are *not* 100% sure of), Quests, Power-Ups, "forgiving" goals ("okay to fail numerous times"), XP across physical/mental/emotional/social; peer-reviewed trials on depression and concussion recovery ([SuperBetter FAQ](https://v1.superbetter.com/faq), [McGonigal ch. 12](https://publicism.info/self_help/superbetter/12.html), [Built In](https://builtin.com/articles/superbetter-mobile-game-ux-supports-wellness-11559)). | The nearest design philosophy to "proof swims": a challenging goal you can fail and retry without penalty, with XP for effort. | **Steal:** "Epic Win" framing for proofs, attempt XP, retry without loss. **Skip:** avatars, allies, secret identities (off-tone for "calm instrument"). |

**Dark-pattern guardrails** (consistent across reviews): competitive gamification, visible-achievement pressure and social overload are associated with stress and "gamification exhaustion" ([Information Processing & Management, 2021](https://www.sciencedirect.com/science/article/abs/pii/S0306457321001382)); fitness-app experiments are framed through Self-Determination Theory (autonomy, competence, relatedness) with the over-justification risk that rewards overshadow the activity itself ([dark side of gamification experiment](https://exa.ai/library/publication/tdxdrfdxsy2)); ethics review flags loss of perceived autonomy, sense of defeat and anger/anxiety, and recommends autonomy/personalization and avoiding defeat in "serious" apps ([MDPI ethics review](https://www.mdpi.com/1660-4601/18/21/11052)). Reward framing matters: *informational* rewards ("this means you did X") support motivation, *controlling* ones ("do this to earn that") undermine it ([NerdSip synthesis of Deci & Ryan](https://nerdsip.com/blog/gamification-gone-wrong-when-streaks-become-the-point), vendor blog but accurately summarizing SDT).

### Fathom "never" list (v1)

- No XP, level, or streak **loss**. Nothing ever decrements.
- No daily streak. No hearts, energy, or timers.
- No loss-framed notifications ("your streak will end!"). Max one gentle local nudge/day, off by default for streak topics.
- No purchasable protection, wagers, leagues, leaderboards, variable-ratio loot.
- No XP for distance (prevents "swim more to level" overload against soft recovery warnings).
- No red, sad faces, or "you missed" tallies in the habit layer.
- Settings toggle to **hide XP/levels/streaks** entirely (milestones and scorecards remain). Users in the Duolingo-motivation thesis asked to toggle off distracting mechanics ([Oulu thesis](https://oulurepo.oulu.fi/handle/10024/54117)); Strava's non-disableable banners are the cautionary example.

---

## 2. Milestone vs streak: keeping both meaningful when split

**The tension.** Product rules say streaks/XP are forgiving cosmetics while milestone dates are honest. The risks are (a) *false reassurance* ("8-week streak, I must be on track") and (b) *false alarm* ("I broke my streak so my proof date moved"). Both come from a mental model where one number stands for "how I'm doing."

**Design response: two named objects with different jobs.**

| | Habit layer | Capability layer |
|---|---|---|
| Question it answers | "Am I showing up?" | "Can I swim it yet?" |
| Objects | Chores, weekly streak, Rest Passes, XP, level | Milestone ladder, proof attempts, forecast, longest-continuous record |
| Rules | Forgiving, never decrements, automatic protection | Honest; moves **only** on proof fail/delay/early pass (and declared program pause) |
| Visual treatment | Warm accent (amber), soft rounded, brief animations | Flat instrument styling (mint/neutral per pool-night DS), dates in plain type, no animation beyond the proof moment |
| Copy voice | Encouraging, never reproachful | Plain, factual, units and dates |

**Keeping streaks motivating without clock power**

1. **Streak counts the behavior; milestone counts the capability.** After every proof, show "what carried you" (sessions done in that block) so the habit layer visibly feeds the capability layer through *reflection*, not mechanics. Evidence supports that visible progress on meaningful work drives motivation: [Amabile & Kramer, Progress Principle](https://www.hbs.edu/faculty/Pages/item.aspx?num=40244) (28% of low-importance events had major impact on inner work life, so small wins matter).
2. **Make progress feel closer.** Goal-gradient: effort rises with perceived proximity to a reward ([Kivetz et al.](https://journals.sagepub.com/doi/10.1509/jmkr.43.1.39)). Endowed progress: a head start framed with a reason increases persistence ([Nunes & Drèze](https://academic.oup.com/jcr/article/32/4/504/1796232)); *earned* vs *endowed* attribution matters, and low-progress self-attributions can lower commitment ([Zhang & Huang](https://ideas.repec.org/a/oup/jconrs/v37y2010i4p641-654.html)). Implementation: the endowment is **reasoned and real** ("Baseline locked: +50 XP"), and the key proximity bar is **evidence-based** (longest continuous swim vs next proof distance), not fake.
3. **Weekly grain with a floor.** A 3×/week athlete who swims twice keeps the streak. Strava/MySwimPro prove weekly works; floor + passes fixes MySwimPro's cliff.
4. **Streak is not the headline on a 2–3 week program.** Max possible streak is 3, so lead with **block progress** ("5 of 8 sessions to proof") and show the streak as a small secondary chip. For longer programs the streak gradually earns more prominence (banners at weeks 2, 4, 8, 12).
5. **Never cross-wire the penalties.** Chore miss → no date movement (product rule). Proof fail → no streak/XP/level movement. Declared pause → dates shift by pause length, labeled **Paused**, not **Slipped**. (Open question: confirm in planning.)
6. **State the rules once.** A one-screen "Rules of the clock" at activation and in settings: "Streaks and XP forgive. Dates only move when a proof is delayed, not passed, or you pause." This is cheap and removes the reassurance/alarm failure modes.
7. **Honest clock UI.** Show *planned* date, *current forecast*, and delta ("+4 days: proof 1 not passed on Oct 12"). Keep a short "why dates moved" ledger so slips are explained, not mysterious.

---

## 3. XP and level curves for short and medium programs

**Method (from game-design practice):** design pacing in *time-to-level*, then derive XP, and watch XP/hour by source so one activity does not dominate ([GameDesign.gg](https://gamedesign.gg/articles/character-progression-systems/), [XP Curve Designer guide](https://gamesdesign.co.uk/guides/tool-xp-curve-designer-guide.html)). Fast early levels, then slower ([Deliberate Game Design](https://deliberategamedesign.com/the-shape-of-curves/), [Grasp](https://paths.grasp.study/modules/edf7d6da-d14c-48bc-9f76-ba97e6a2d654/lessons/b92d0265-1035-4015-b800-421826f8ca4e)). Exponential curves are for multi-year status games; for a cosmetic layer in a 3–6 month program, a **capped-cost** curve avoids grind.

**Targets (hours-first, in calendar days at 3 sessions/week):**

| Program length | Target feel |
|---|---|
| 2–3 weeks (dogfood) | L2 on first completed chore; L3 by end of week 1; **a level-up lands on each proof pass**; finish around L6 (L7 within reach) |
| 3 months | ~1 level per 1–2 weeks early, ~1 per 2 weeks by L8+; finish ≈ L12 |
| 6 months | Never more than ~2–3 weeks between level-ups at steady cadence; finish ≈ L21 |

**Recommended curve.** Cost to go from level L to L+1 = `100 × min(L, 8)` XP. Cumulative:

| Level | Cumulative XP | Cost to next | Typical landing (3×/wk) |
|---|---|---|---|
| 1 | 0 | 100 | start |
| 2 | 100 | 200 | first session (day ~2) |
| 3 | 300 | 300 | end of week 1 |
| 4 | 600 | 400 | week 2 |
| 5 | 1,000 | 500 | first proof pass |
| 6 | 1,500 | 600 | around final dogfood proof pass |
| 7 | 2,100 | 700 | just after dogfood proof, or ~week 4 in longer programs |
| 8 | 2,800 | 800 | ~week 5–6 |
| 9 | 3,600 | 800 | ~week 8 |
| 10 | 4,400 | 800 | ~week 10 |
| 12 | 6,000 | 800 | ~week 12 |
| 16 | 9,200 | 800 | ~month 4–5 |
| 20 | 12,400 | 800 | ~month 5–6 |
| 21 | 13,200 | 800 | ~month 6 |

Cap at 800 keeps late levels from stretching beyond ~2 weeks. Treat all numbers as **launch hypotheses**: log time-to-level locally and retune (the sources all say tune from measured income, not the formula).

**Level labels (optional copy).** Subtle depth tiers, consistent with "calm instrument, subtle mythic": e.g. L1–3 *Shallows*, L4–7 *Lane*, L8–12 *Channel*, L13+ *Deep*. Avoid RPG class art, avatars, or numbers-as-trophies.

---

## 4. Celebrating proofs, handling fails

### Pass: proportionate celebration

Celebration hierarchy so the biggest moment is reserved for the thing that matters:

| Event | Weight | Treatment |
|---|---|---|
| Chore matched/done | Quiet | Checkmark, XP count-up ≤1 s, block bar advances |
| Level up | Small | Toast; tier name change gets slightly more |
| Weekly floor/full week | Small | Recap card line |
| Streak week 2/4/8/12 | Small | Hideable banner |
| **Proof passed** | **Big** | One full-screen result moment (skippable, ~3 s), not looping |

**Proof pass moment contents:** hero stat (distance and time), delta vs baseline ("+200 m since you started"), what carried you (sessions in block), XP and any level-up, next rung preview ("Next: 1,400 m proof, forecast Nov 2"). A saved/export-able milestone card is optional; the data is local and should stay local unless exported. This is the "Epic Win" beat: a goal the athlete was not certain they could reach, so it feels like discovery, not a checkbox ([McGonigal](https://publicism.info/self_help/superbetter/12.html)).

**Early pass:** if the athlete passes ahead of schedule, forecast pulls in only when they confirm the next proof date (honest in both directions without surprising them).

### Fail: facts, attempt credit, next step

Research relevant to design (with honest caveats):

- A setback increases the chance of subsequent failure; **reduced self-efficacy and reduced perceived usefulness of continuing** are proposed mechanisms, and interventions that protect self-efficacy are suggested ([Radboud setback paper](https://repository.ubn.ru.nl/bitstream/handle/2066/288111/288111.pdf?sequence=1)). The "what-the-hell effect" itself has inconsistent replication, so I use it as a design caution, not a law ([PMC9291624](https://pmc.ncbi.nlm.nih.gov/articles/PMC9291624/)).
- Self-compassion after lapses is associated with less negative affect, higher perceived control, and goal re-engagement ([PMC10543633](https://pmc.ncbi.nlm.nih.gov/articles/PMC10543633/); exercise setbacks specifically: [Journal of Sport & Exercise Psychology](https://journals.humankinetics.com/view/journals/jsep/40/1/article-p31.xml)). Evidence for *app copy* causing this effect is limited. This is design inference.
- SuperBetter's Epic Win guidance: challenging but not obviously impossible; "be open to trying again" ([McGonigal](https://publicism.info/self_help/superbetter/12.html)).

**Recommended fail screen (data-first, no euphemism, no blame):**

1. **Headline = the fact:** "1,120 m of 1,200 m continuous." If it exceeds the previous longest continuous swim, say so: "Longest continuous swim to date (+120 m)." (A record is a legitimate win even on a fail.)
2. **Status line (honest):** "Proof not passed. Next attempt forecast Oct 23 (+4 days)." Ledger term is **Not passed** (honest); headline tone is neutral/specific.
3. **Credit:** "+100 XP for the attempt." Level, streak, and prior proofs unchanged and shown ("Proof 1 passed Oct 10").
4. **Why (from existing swim insight):** one observation from the data, e.g. split fade after 800 m. Descriptive, not diagnostic, no "you should have."
5. **Choice (autonomy):** primary "Retry Oct 23 (after 2 more sessions)"; secondary "Adjust proof to 1,150 m first"; tertiary "Talk later." No forced path.
6. **Cooldown:** default minimum gap between attempts (suggest ≥48–72 h; planner owns exact value) to avoid the "fail → immediately re-try at fatigue → fail again" loop.
7. **Escalation after repeated fail:** after 2 consecutive misses at the same rung, offer an intermediate rung or baseline re-test (a visible step in the ladder, dates still honest). Keeps the goal "challenging but not out of reach."
8. **No push notification** about the fail. Next day's chore header may carry the focus line; no reference to the miss.

### Delay vs fail

R15 treats delayed like failed for the clock. Make **delay an athlete verb** ("Delay proof") with the same factual date shift and no XP effect. If the athlete is short on sessions before a proof, show a neutral readiness hint ("1 of 3 sessions this block. Attempt anyway or delay?"), never a lock.

---

## 5. Scorecards: inform emphasis, don't gate

Constraints from existing docs: R16 (scorecards **must not gate** early dogfood proofs unless a proof fails), and the Home design rule that composite scores stay off Home ([Home Today instrument](../2026-09-12-home-today-instrument-requirements.md) via brand/IA supersession). So: **three separate cards on the Programs screen, no combined number, no grades.**

| Card | Question | Primary display | Supporting |
|---|---|---|---|
| **Habit** | Am I showing up? | "N of M sessions" this block | Weeks at/above floor; Rest Passes left |
| **Volume** | Am I building capacity? | **Longest continuous vs next proof distance** (bar) | Weekly distance vs plan; 4-week rolling; ramp indicator |
| **Efficiency** | Am I swimming smarter or fresher? | Matched-pace distance per stroke (DPS) trend | Pace fade on long swims; SWOLF only as secondary |

### High-level formulas (v1)

**Habit.** `habit = (done_synced + done_manual + 0.6 × adjusted) / (prescribed − excused_skips)` over the current block (display as a fraction, not a %). `excused` = skip reason in {other load / recovery, ill, travel, pool closed}. Bands for words only: *Steady* ≥ 0.85, *Building* 0.6–0.85, *Light* < 0.6. (Kinoku's principle: planned rest is not a zero.)

**Volume.**
- `weekly_m` = pool metres in program week; `plan_ratio = weekly_m / planned_m`.
- `continuous_capacity` = longest uninterrupted swim in trailing 28 d (stop-gap threshold is a parameter; define with the data-inventory doc). Display `capacity_gap = proof_distance − capacity`.
- `ramp = weekly_m / mean(previous 3 weeks)`. Flag softly above ~1.3 ("bigger week than usual: keep proof-eve easy"). The "~10% per week" rule appears in swim coaching content ([Alison Smith CSS program](https://www.alisonsmith.co.uk/post/consistent-css-swim-training-leads-to-measurable-improvements) and [swim-training guides](https://research.poin-t-go.com/en/sports/general/swimming-lactate-threshold-training)) but is a heuristic. A dogfood 1,000 → 1,200 m target is itself +20% in capacity, so don't flag the plan against its own design. Defer thresholds to the training-algorithms research doc.

**Efficiency.** Efficiency in swimming is easy to fake with raw SWOLF. SWOLF = seconds + strokes per length, comparable only to your own history in the same pool/stroke/effort; adding glide improves the score while swimming slower; push-off distance corrupts it ([SwimFast](https://learnswimfast.com/times/what-is-swolf), [SwimFast calculator](https://learnswimfast.com/tools/swolf-calculator), [Polar](https://support.polar.com/uk-en/swimming-metrics), [Steel City Endurance](https://steelcityendurance.com/swimming/what-can-swolf-tell-us-interpreting-swim-data-from-your-gps-watch/)). Therefore:
- **Matched-pace DPS:** from qualifying intervals (dominant stroke, ≥50 m, preferably ≥100 m, pace within ±5% of the athlete's steady-pace band, same pool length), take median distance per stroke per session; trend = change vs program baseline.
- **Pace fade (durability):** last-third pace ÷ first-third pace on the longest continuous swim or main set ≥400 m. This is the most proof-relevant efficiency signal.
- **SWOLF:** secondary, pool-length-normalized, only at matched pace, with a glide caveat in the info sheet.
- **Minimum data:** ≥3 qualifying sessions or ≥6 intervals; else show "Collecting" (honest, not a zero).

### How scorecards "inform emphasis" without gating

- Each card yields a status relative to the athlete's own plan/baseline. A deterministic rule picks **one focus line** for the next chore header ("Focus: even splits", "Focus: swim Thursday", "Focus: build the long swim").
- Scorecards **never** block, delay, or reshape a proof before a failure (R16).
- After a fail, scorecards feed **reshaping suggestions** (e.g. high pace fade → more steady aerobic volume; capacity short of proof → add a long swim), offered as a retry plan the athlete can override. My reading of R16: "unless a proof fails" permits reshaping, not locking.
- Trend arrows only after first-reading minimums; use "own prior block" as the comparison, never population norms.

---

## 6. Concrete v1 recommendation

### 6.1 Chore states

| State | Meaning | XP | Counts for floor | Habit card | Milestone clock |
|---|---|---|---|---|---|
| **Scheduled** | Future prescribed chore | n/a | n/a | n/a | n/a |
| **Due** | Today's chore | n/a | n/a | n/a | n/a |
| **Done (synced)** | Watch swim matched to prescription intent | 100 (+20 structure bonus if warm-up and cool-down matched) | Yes | 1.0 | No effect |
| **Done (manual)** | Honest athlete confirm, no matching swim | 70 | Yes | 1.0 | No effect |
| **Adjusted** | Shorter/modified but real swim (≥~50% of intent or athlete-confirmed) | 60 | Yes | 0.6 | No effect |
| **Moved** | Athlete reschedules within the same program week | none until done | n/a | n/a | No effect |
| **Skipped (excused)** | Athlete skips with reason: recovery/other load, ill, travel, pool closed | 0 (+25 once/week if reason = "listening to recovery"; tunable) | Not counted against | Removed from denominator | No effect |
| **Skipped (other)** | Athlete skips, no excuse | 0 | No | 0 in numerator | No effect |
| **Lapsed** | Day passed without action; auto-resolves after a 72 h late-sync window | 0 | No | 0 | No effect |
| **Superseded** | Block reshaped after a proof fail/delay | n/a | Removed | Removed | n/a (cause is the proof) |

**Evidence rules.** The state transition from a synced swim uses *sync-timestamped* swim data, not tapped wall-clock time. Late syncs retro-match within 72 h (Strava restore pattern; Duolingo's Big Red Button repair concept). Matching is undoable ("Not this one"). Manual done is allowed but pays 70 to keep evidence slightly privileged without calling the athlete a liar.

### 6.2 Streak rules

- **Unit:** weekly (Mon–Sun, local TZ, setting to change week start).
- **Week target:** `sessions_per_week` from intake. **Floor** = `ceil(target / 2)` (3 → 2, 2 → 1, 4 → 2, 5 → 3, 1 → 1). A week at or above the floor extends the streak. A week meeting 100% of prescribed chores is a **Full week** (gold dot, extra XP, +1 Rest Pass).
- **Rest Passes:** start with **2** per program (endowed, shown as labeled dots "Rest passes: 2"); **+1 per Full week**, cap **3**. A week below the floor **auto-consumes** a pass (no button, retroactive up to close of week) and the streak survives. When none remain, the streak breaks visibly and plainly, and the last pass says so on the day.
- **Declared pause / excused week:** if the athlete marks illness, travel, or a heavy other-sport block (or uses excused skips so the week cannot reach the floor), the week is **excused**, consumes no pass, and does not count toward the streak number. Longer than 2 consecutive weeks prompts "Pause program?" which shifts milestone dates by the pause and labels them *Paused* (confirm in planning).
- **On break:** current streak resets to 0, but **Best streak** and **Weeks trained (x of y)** remain and never reset. Copy never mentions loss ("Fresh week. Best: 5").
- **Planned light week:** athlete or planner can set a deload week with floor = 1.
- **No daily streak.** No streak notifications by default. Optional single local nudge when the floor is unmet and ≥2 days remain; neutral copy ("2 sessions planned, 1 done"), user toggle.
- **Carry-over:** streak and passes persist across programs (a program ending is not a break; gap between programs is auto-paused).

### 6.3 XP sources and caps

| Source | XP | Rule |
|---|---|---|
| Program activated (baseline locked) | +50 | Once per program; copy gives the reason ("Baseline locked") |
| Guided baseline test completed | +100 | Replaces nothing; once |
| Chore done (synced) | +100 | Max 1 chore-XP/day |
| Warm-up and cool-down both matched | +20 | With synced swim; manual users self-check ✓ |
| Chore done (manual) | +70 | |
| Chore adjusted | +60 | |
| Excused skip, "listening to recovery" | +25 | Max 1/week; drop if patronizing |
| Floor week | +25 | Week bonus |
| Full week | +50 | Replaces floor bonus (not additive) |
| **Proof attempted** | **+100** | Pass or fail |
| **Proof passed** | **+200** | Additional to attempt |
| New longest continuous swim (PB) | +100 | Only when exceeding prior record by ≥ one rung step (parameter), once per record |
| Comeback (first completed chore after ≥7 days idle) | +50 | Once per 21 days; no message about the gap |
| Extra unprescribed pool swims | 0 | Counts toward Volume only |
| Distance swum | 0 | Never |

Sanity-check: no non-proof source exceeds ~1.2× the base chore, so nothing is farmable (the ">50% above peers is a bug" rule from [GameDesign.gg](https://gamedesign.gg/articles/character-progression-systems/)). Proofs are the only big payers by design.

**Projected totals (rough):**
- **Dogfood, ~2.5 weeks:** 8 chores + 2 proofs ≈ 50 + 8×110 + 3 full weeks×50 + 2×400 (attempt + pass + PB) ≈ **1,900 XP → L6, with L7 (2,100) one extra chore or bonus away**. Intended landings: L2 on first chore (~day 2), L3 ~end of week 1, L4 ~week 2, **L5 on proof 1 pass, L6 on proof 2 pass**, so each proof coincides with a level-up.
- **12-week:** 36 chores + 5 proofs ≈ **6,500 XP → L12**.
- **26-week:** 78 chores + 10 proofs ≈ **13,800 XP → L21**.

### 6.4 Scorecards and the gating statement

See §5. In v1: three cards (Habit, Volume, Efficiency), no composite, no grades, "Collecting" states, one focus line, **nothing gates a proof**.

### 6.5 UX moments

| # | Moment | Content | Tone |
|---|---|---|---|
| 1 | **Program activation** | Ladder with *planned* dates; "Baseline locked +50 XP"; **Rules of the clock** sheet (dismissible) | Calm, plain |
| 2 | **Today chore card** | Warm-up / main / cool-down; focus line; soft-warn banner (amber, informational); Start / Adjust / Skip (reason chips) | Informational |
| 3 | **Post-sync match** | "Matched to Thursday's session," XP count-up, block bar advances, Undo | Quiet |
| 4 | **Weekly recap (Mon)** | Sessions, volume, streak/pass status, suggested adjustments (Apple weekly-review pattern) | Neutral |
| 5 | **Pre-proof screen** | Rest guidance, pacing plan from baseline, **Delay proof** as tertiary (states "dates move to…") | Plain, factual |
| 6 | **Proof pass** | Big moment: §4 | Warm, brief |
| 7 | **Proof not passed** | §4 fail screen | Factual, supportive |
| 8 | **Level up / tier change** | Toast | Small |
| 9 | **Streak banners (wk 2/4/8/12)** | Hideable | Small |
| 10 | **Return after gap** | "Welcome back" + next chore; no tally of missed | No shame |
| 11 | **Program complete** | Ledger: proofs passed, longest continuous start→now, chores done, level gained | Reflective |

### 6.6 Local-first implementation notes

- **Derive, don't mutate.** Store an append-only **XP ledger** (reason codes + source event ids) and chore events. Compute streak, passes, level and scorecards from events so the rules can be retuned and **recomputed** after dogfood. Keep the **milestone ledger** (attempts, results, date changes with reason) as a separate, auditable table.
- **Evidence timestamps over device clock** for matching and week boundaries. No server-authoritative problem for a single-athlete local app, but derived-from-evidence prevents accidental double counting and makes recompute deterministic. Apptitude's teardown describes the standard idempotency requirement for freeze/pass consumption ([Apptitude](https://apptitude.io/blog/how-duolingos-streak-mechanic-actually-works/)): passes must consume once per week-close evaluation.
- **Local telemetry** (time-to-level, XP by source, passes consumed, hide-game-layer toggled) for retuning; never sent anywhere.

---

## 7. Recommended v1 rules (summary table)

| Area | Rule | Why (source family) |
|---|---|---|
| Primary success | Proof pass/fail only moves milestone dates | Product rule; goal-gradient and honesty |
| Streak unit | Weekly (Mon–Sun), per-athlete sessions/week target | Strava, MySwimPro, NRC |
| Week floor | `ceil(target/2)` sessions keeps streak | Slack improves retention (Duolingo) |
| Rest Passes | Start 2, +1 per Full week, cap 3, auto-applied, labeled | PushFit; Duolingo freeze |
| Excused weeks | Illness/travel/heavy other load: no pass consumed | Apple pause; Kinoku |
| Streak break | Resets current; keep Best and Weeks trained; no loss copy | Habitica anti-pattern |
| XP | Positive only, never decays; no XP for distance | Dark-pattern guardrails; recovery soft-warn |
| Proof XP | Attempt +100, pass +200, PB +100 | SuperBetter attempt credit |
| Level curve | cost = `100 × min(L,8)`; dogfood ≈ L6, 12-wk ≈ L12, 6-mo ≈ L21 | Hours-first curve design |
| Early win | +50 baseline-locked head start; first proof by ~day 8–10 if plannable | Endowed progress; Duolingo week-1 fragility |
| Chore states | Done(synced/manual), Adjusted, Moved, Skipped(excused/other), Lapsed, Superseded; 72 h late-sync match | Strava restore |
| Pass celebration | One full-screen moment, delta vs baseline, what carried you, next rung | Progress principle; Epic Win |
| Fail handling | Factual headline, attempt XP, no streak/level change, retry date + choice, 48–72 h cooldown, step-down after 2 fails | Setback and self-compassion research |
| Scorecards | Habit, Volume, Efficiency; no composite; one focus line; never gate | R16; Home rule |
| Efficiency metric | Matched-pace DPS + pace fade; SWOLF secondary | SWOLF limitations |
| Notifications | None streak-loss; ≤1 optional neutral nudge | Dark-pattern guardrails |
| Autonomy | Setting to hide game layer; all copy skippable | SDT; Strava banner caveat |
| Social | None in v1 | Competition → stress; scope |

---

## 8. Verification scenarios (map to AE-style checks)

1. **Two swims in a 3×/week week:** streak extends (floor met); no pass used; no date movement.
2. **One swim in a 3×/week week, passes = 2:** pass auto-consumed; streak intact; recap shows "Rest pass used (2 → 1)".
3. **Soft-warn day, athlete skips (recovery):** excused; habit denominator shrinks; streak/dates unaffected.
4. **Proof fail at 1,120 m:** dates shift, +100 XP, streak/level unchanged, headline shows record if > prior; retry offer; no notification.
5. **Proof pass early:** forecast offered earlier only on athlete confirm; XP +300 (+100 if PB).
6. **Late sync (48 h):** chore flips Lapsed → Done (synced) with XP and floor recomputed.
7. **Game layer hidden:** milestones and scorecards render; no XP/streak UI anywhere.
8. **Dogfood run:** from ~1,000 m baseline, ≥8 chores + 2 proof passes yields ~L6, with a level-up on each proof pass (L5, then L6).

---

## 9. Open questions / follow-ups

- **Program pause semantics** (shift dates vs hold forecast) is a planning decision; research favors "declared, labeled Paused, honest shift."
- **Proof evidence matching** (how tightly a synced swim must match) is owned by the data-inventory research; this doc assumes only "synced match → evidence XP; manual → reduced XP."
- **Continuous-swim definition** (stop-gap threshold) affects the Volume card and PB XP.
- **Planner constraint:** programs ≥2 weeks should place a first proof by ~day 8–10 (e.g. 1,100 m before 1,200 m). This improves early-win design but adds all-out efforts; check against the training-algorithms doc.
- **XP/level is lifetime or per program?** Recommended lifetime (progress persists, no reset anxiety) with per-program XP summary on the completion ledger.
- **Copy and naming** (Rest Pass, tier names, "Not passed" vs "Not yet") need a pass from the brand voice owner.
- **Efficiency thresholds** (pace band ±5%, ≥3 sessions) are initial guesses to validate on the owner's real intervals.

## Source notes and confidence

- **High confidence (first-party docs):** Strava streak rules, MySwimPro weekly streak, Apple ring pause/weekly goals, Duolingo blog A/B results, SuperBetter FAQ/book chapter.
- **Medium (peer-reviewed/preprint but different domain):** goal-gradient, endowed progress (consumer rewards, not fitness), setback/self-compassion (diet/exercise lapses, mostly correlational), gamification stress surveys (self-report, mixed populations).
- **Lower (vendor/blog/design-tool articles):** Trophy NRC analysis, NerdSip synthesis, PushFit/Kinoku product copy, XP-curve tutorials, SWOLF blog guidance. Used for design patterns and pacing heuristics, not claims of efficacy.
- Duolingo numbers (+4%/−5%, +14% D7) are Duolingo-reported A/B tests on their own user base.
- Not found / not verified: published A/B evidence for streak mechanics in swimming apps; the 10%-per-week swim volume rule beyond coaching content.

---
date: 2026-10-09
topic: pool-swim-programs-training-algorithms-datasets
status: research-complete
type: research
feeds:
  - docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md (R8–R11, R13; "Research follow-up #1")
  - docs/architecture/swim-session-insight-contract.md (consumer seam)
author: best-practices-researcher subagent
---

# Pool-swim training program engine — algorithms, datasets, community practice

> Research input for the **Fathom Programs v1 rules pack** (pool only, local-first, deterministic, curated templates + rules, milestone proof swims as the spine). Not a plan, not a PRD.

---

## 0. Executive summary (one page)

**Bottom line.** A credible deterministic pool-swim engine can be built entirely from (a) public physiology/coaching formulas, (b) generic set vocabulary that every swim coach uses, and (c) Fathom's own swim history — with **no licensed feed**. There is **no clean public dataset** of swim *training programs* or *athlete trajectories* (no "OpenPowerlifting for swim"). The available "datasets" are competition times (restricted), sensor/IMU research data (wrong problem), or proprietary app content (not licensable as a feed). **Recommendation: build a Fathom-owned, provenance-tagged, distilled rules pack, calibrated on the owner-athlete's own logs.**

**USMS follow-up (2026-10-09):** Public articles such as [Best Workouts for Masters Swimmers](https://www.usms.org/fitness-and-training/articles-and-videos/articles/best-workouts-for-masters-swimmers) publish full sample workouts and a useful taxonomy (pace / USRPT / test / breathing / recovery). The large **Workout Library** and **35 six-week plans** (six of them “swim N nonstop”: 200→3,000 yd) are **member-only** — not a scrapable dataset. Distill patterns; do not ingest the library. Deep pass amendments: ladder shape by goal length, session-total clamp ~1,300–2,000 m, send-off vs rest, no breath-hold sets, optional split-pause proof. See `docs/brainstorms/research/2026-10-09-usms-masters-workout-sources.md`.

**Four-questions source map (2026-10-09):** Beyond USMS — verified GPT list + Swim Smooth / Maglischo / MSA–MSNSW / FINIS / TrainingPeaks blurbs / Open Swim Workout / swiML / Brunner IMU / Cosoli HR Zenodo / SwimXYZ, etc. Organized as Q1–Q4 with **ingest vs distill vs ignore** (World Aquatics / Swim.com / synthetic Kaggle technique → ignore). See `docs/brainstorms/research/2026-10-09-swim-data-sources-four-questions.md`.

**Formats + community deep dive (2026-10-09):** OpenSwim Kotlin model + 12 MIT workouts, OSW/SwimText, swimming-resources 410-index, Zhuang PMC6891622 / SwimBIT method notes, and r/Swimming·triathlon·Slowtwitch → **12 FP-\*** meter Rules Pack seeds (expand toward USMS 26+6). See `docs/brainstorms/research/2026-10-09-opensource-swim-formats-and-community-practice.md`.

**What the science and practice say, in engine terms**

1. **Two different goals hide inside "goal distance + target time."** *Capacity* (can I swim D continuously?) is limited by breathing/technique/aerobic base and moves in weeks. *Pace* (can I swim D in T?) is limited by threshold speed and moves in months (Swim Smooth guidance: CSS gains ≈ 0.3–0.5 s/100 m per week, plateau after 8–12 weeks, "5% in 10 weeks" as a challenge target). The engine must treat these as two tracks, which is exactly what a milestone ladder does.
2. **Anchor pace on one number: CSS (critical swim speed)** from a 400 m + 200 m time trial: `CSS pace per 100 m = (T400 − T200) / 2`. It is a *planning anchor*, not physiology truth (it overestimates maximal-lactate-steady-state speed; the 200/400 shortcut overestimates vs longer trials). Retest every ~4–8 weeks. T-30/T-pace and 1000–1500 m time trials are valid fallbacks.
3. **Intensity for distance goals is mostly easy-to-steady, with ≤1 threshold session/week and one long-rep endurance session** (Swim Smooth 3-session week; Maglischo/Sweetenham zone logic; swimmer systematic review: long-distance swimmers mostly pyramidal; no TID model proven superior).
4. **Continuous-distance milestones are built by lengthening reps and shrinking rest**, not by doing one long swim to failure (r/triathlon, SwimGym, TrainingPeaks beginner plans, Ruth Kazez 0→1650). Typical adult data points: **500 m→mile in ~4–8 weeks at 2–3 sessions/week; many take 2–3 months.** A 1000→1200 m (+20%) step in 2–3 weeks is aggressive-but-plausible for 3 sessions/week and consistent with +5–10%/week volume guidance.
5. **Every session = warm-up (≈15–20%, ≥300 m) → optional technique/pre-set → main set → cool-down (100–300 m easy).** Evidence is coach-consensus (grade C), not RCT; fine for v1.
6. **GT5 wrist HR is not a safe intensity driver in water** (wrist optical HR in swimming has limits of agreement of roughly −53 to +34 bpm vs chest strap in one study). Drive intensity from **pace relative to CSS + RPE**, keep HR as a soft/secondary signal.

**What is NOT available:** a public workout/plan corpus with license; public pool *training* logs at scale; any Garmin Coach / MySwimPro / FORM plan export; USA Swimming / World Aquatics / NCAA bulk data with commercial reuse rights; Strava data for any model use (June 2026 policy bans AI uses outright, and its data is per-user anyway).

**Top 5 recommendations** (details in §6, §7)

| # | Recommendation |
|---|---|
| 1 | **Build, don't license:** ship a Fathom-owned *Rules Pack v1* (formulas + ~20 set patterns + parameter ranges), every rule tagged with source + evidence grade; calibrate with dogfood logs. |
| 2 | **Anchor on CSS (400/200) with a baseline cascade** history → guided test → self-report; label confidence; *never* use wrist HR for zones. Prefer **pace-offset zones expressed as ranges** (CSS+x…y s/100). |
| 3 | **Milestone ladder = capacity rungs (+15–25% continuous distance per 2–3 weeks, rounded to 50 m; optional `ladder_shape` linear vs capped-rehearsal by goal length) → pace proofs → full-distance trial.** Dogfood: 1000→1200 m fits the default +20% rung. Goal-day = derived forecast range, recomputed on every proof. |
| 4 | **Scale by sessions/week through fixed session *roles*** (2 = Endurance + Quality; 3 = Endurance + CSS + Technique/Aerobic; 4–5 = add easy/aerobic only), session ≈ 45–60 min, weekly volume +5–10%/wk with a ~80% deload every 3rd–4th week; **frequency before session length**. |
| 5 | **Honest failure semantics:** near-pass (≥90% of D) slips ~1 week, clear fail steps back to last proven distance with a half-size next rung; surface feasibility warnings at intake when the *pace* gap implies > horizon (pace moves ~0.3–0.5 s/100/week, not days). |

---

## 1. Scope, method, and honesty notes

- **Method:** web search + page reads across sports-science literature, coaching sites, vendor docs/ToS, and community threads (2026-10-09). Where a number came from a coaching blog or app vendor rather than peer review, it is labelled **[B]** or **[C]**.
- **Evidence grades** used throughout:
  - **[A]** peer-reviewed / primary physiology source
  - **[B]** established coach/author text or national-body material (Maglischo, Sweetenham & Atkinson, USMS, Swim Smooth)
  - **[C]** blog, vendor doc, forum consensus, field heuristic
  - **[D]** Fathom-calibrated (to be created from dogfood data)
- **Reddit caveat:** direct `reddit.com` fetches were **blocked** ("blocked by network security") from the research tooling. Community findings below come from **search-index snippets** of real r/Swimming and r/triathlon threads; verify specific quotes by opening the thread in a logged-in browser before citing them in product copy. The user-suggested **r/Swimmit** is not a separate active community: Swimmit was the original name of the subreddit that became **r/Swimming** (2010 mod announcement in the r/Swimming archive).
- **Not legal advice.** The licensing notes summarize publicly visible terms; get counsel before shipping anything derived from third-party content.
- No source below was treated as authority for *medical* claims; Programs copy should carry the same "educational, consult physician" posture app vendors use (e.g. MySwimPro ToS).

---

## 2. Training science → engine rules

### 2.1 Frame the goal correctly: capacity vs pace

| Goal type | Typical intake phrase | Limiting factor | Time scale of change | Engine track |
|---|---|---|---|---|
| **Capacity** | "swim 1200 m without stopping" | breathing rhythm, relaxed technique, aerobic base, pacing discipline | **weeks** (r/Swimming: ~4–8 wk from 500 m→mile; 2–3 months common) | continuous-distance rungs |
| **Pace/time** | "1200 m in 22:00" | threshold speed (CSS), efficiency (stroke length), race-pace rehearsal | **months** (CSS gains ~0.3–0.5 s/100 m/wk early; plateaus after ~8–12 wk) | CSS development + goal-pace rehearsals |

The product already says goal-day is a *derived forecast*. Making the two tracks explicit lets the engine tell the athlete honestly which one is the bottleneck at intake.

Sources: Swim Smooth "Understanding Swim Training Zones" (week structure, CSS improvement guideline) — https://blog.swimsmooth.com/p/understanding-training-zones **[C/B]**; Swim Smooth 10-week CSS programme (aim: −5% CSS) — https://blog.swimsmooth.com/p/challenge-yourself-with-our-2024 **[C/B]**.

### 2.2 Critical swim speed (CSS), T-30, and test options

**Origin.** Wakayoshi et al. showed distance–time is linear across maximal swims; the slope is critical velocity (flume r² > 0.998; correlated with onset of blood lactate accumulation r = 0.949 and mean 400 m speed r = 0.864). **[A]**
- Wakayoshi 1992 (Europe PMC abstract): https://europepmc.org/article/MED/1521952
- Wakayoshi et al. full text mirror: https://d.docksci.com/download/determination-and-validity-of-critical-velocity-as-an-index-of-swimming-performa_5ec52686097c47ac058b458c.html

**Field protocol (coach-popularized, Ginn simplification).**
- 400 m maximal even-paced → full recovery (≈8–15 min easy swim/rest) → 200 m maximal.
- `CSS (m/s) = (400 − 200) / (T400 − T200)`; `CSS pace per 100 m = (T400 − T200) / 2` (seconds).
- Worked example: 400 in 6:40 (400 s), 200 in 3:10 (190 s) → 200/210 = 0.952 m/s → 105 s/100 m (1:45).
- Retest interval guidance disagrees by source: **4–6 weeks** (Swim Smooth), **6–8** (SwimTune, Envol), **8–12** (Outdoor Swimmer). → v1 default **~6 weeks**, or at the first proof boundary after ≥5 weeks.
- Sources: https://swimtune.com/guides/css-critical-swim-speed ; https://www.swimio.app/guides/critical-swim-speed-test ; https://learnswimfast.com/tools/css-calculator ; Swim Smooth https://blog.swimsmooth.com/p/get-your-pace-right ; Outdoor Swimmer https://outdoorswimmer.com/coach/how-tos/testing-times-2/ **[C/B]**
- Keep **same distance pair, same course (pool length), same timing method** across retests; don't compare 400/200 with 400/50 results (Swimio, SwimFast).
- Garmin ships a built-in pool CSS test on pool-swim-capable Forerunners (`Pool Swim > Options > Critical Swim Speed > Do Critical Swim Speed Test`) and auto-detects CSS in Connect from varied efforts; one third-party guide says auto-CSS "may differ from true CSS by 3–10 s/100 m" **[C]**. Manual: https://www8.garmin.com/manuals/webhelp/GUID-2492EDA1-1182-400B-8F43-D8B3211E4F3C/EN-US/GUID-F9FFE0BF-ED46-40D4-A562-92F1CB4C3650.html ; https://www.trainingzones.io/en/guides/critical-swim-speed

**Validity limits (important for honest copy). [A]**
- CSS **overestimates** the maximal lactate steady state: CSS ≈ 92.7% of MAS vs MLSS ≈ 88.3% in 8 well-trained swimmers; correlated (r = 0.87) but "too great to use interchangeably." — Dekerle et al. 2005, https://pubmed.ncbi.nlm.nih.gov/16195984/
- The **two-point 200/400** version is reliable test-retest (CoV ≲ 3.4% in the four-stroke study) but, with only two points, gives no error estimate, and short trials bias CS **upward** (faster) versus designs including ≥800 m trials. "Use 200/400 for routine monitoring; ≥3 trials for precision." — https://exa.ai/library/publication/55zjnt00rx0 ; Karsten et al. 2022 (Greenwich repository) https://gala.gre.ac.uk/id/eprint/50514/3/50514%20KARSTEN_An_Updated_Methodology_To_Estimate_Critical_Velocity_In_Front_Crawl_%28AAM%29_2022.pdf ; https://exa.ai/library/publication/dnbs2f15jph
- Practical failure modes (coach docs): sandbagging the 200 (→ CSS too fast), starting the 400 too hard, insufficient recovery between trials, off-day testing — Outpace PDF https://outpaceswimming.co.nz/wp-content/uploads/2021/09/Understanding-Critical-Swim-Speed.pdf **[C]**.

**T-30 and relatives (alternatives).**
- **T-30:** 30-min continuous max swim; average per-100 m is "threshold pace" (HY-TEK T-30 module attributes the computations to Madsen). https://hytek.active.com/User_Guides_HTML/SwTM7/HTML/t_30.htm **[C/B]**
- SDSU Swimming Science Bulletin: the T-30 pace was **too fast for EN-1** (aerobic base) training in the study cited — pace for EN-1 could be held 45 min; suggests T-40 / 4,000 m swim for EN-1 pace and sets such as 4×400 with <10 s rest. https://coachsci.sdsu.edu/swim/bullets/icar8990/icar17.htm **[B]**
- **10×100 timed repeat** (Outdoor Swimmer session 2): total time minus rest ÷ reps = threshold pace per 100; add 2–3 s for aerobic pace. https://outdoorswimmer.com/coach/how-tos/testing-times-2/ **[C]**
- **1000 m aerobic time trial** (TrainingPeaks 12-wk plan, week 1) sets aerobic threshold pace; 1500 m TT ≈ 100–102% of CSS. https://www.trainingpeaks.com/training-plans/triathlon/ironman/tp-117016/open-water-swim-3-8km-race-plan-12-weeks **[C]**
- **No-test estimate:** CSS ≈ average pace of a recent continuous 1500 m (pool) — triathlonpace.com (add ~1–2 s/100 m if the reference was a wetsuit swim). https://triathlonpace.com/articles/estimate-your-critical-swim-speed-using-garmin-or-race-results **[C]**

**Engine implications**
- Use **CSS as a bounded planning anchor**, with a `confidence` field (`test`, `history`, `self_report`) and a staleness clock.
- Provide **fallback test ladder** for athletes who can't swim 400 m continuously: (a) 10×100 timed (T-pace) or (b) capacity-first mode where "steady pace" = pace of the athlete's longest recent continuous swim (no CSS yet).

### 2.3 Zones: CSS-relative pace offsets (use ranges, not points)

Vendor/coach zone tables agree broadly. A merged table for the v1 pack (all **[C]** unless noted):

| Fathom effort | Pace vs CSS (per 100 m) | RPE (1–10) | Typical use | Cross-reference |
|---|---|---|---|---|
| **Easy / Recovery** | CSS +10 to +15 s (cap: should be able to talk at each wall) | 2–3 | WU/CD, technique, recovery swims | SwimTune: +12–15 s; Swim Smooth "Easy" +8–10 s; AquaPlan: 10–20 s slower than normal easy |
| **Steady / Aerobic** | CSS +6 to +10 s | 4–5 | Bulk volume; capacity proofs | SwimTune +6–10; Swim Smooth steady +6 |
| **Endurance-2 ("long-rep tempo")** | CSS +3 to +5 s | 5–6 | 400 m reps, 10×400-style | Swim Smooth "6×400 at CSS+3–4", 4×400 at CSS+4 |
| **Threshold** | CSS ±2 s | 6–7 | 100–200 m CSS reps, 10–15 s rest | Swim Smooth 10×100 @ CSS, 10–15 s rest; SwimTune 10–20×100 |
| **Fast / VO₂-ish** | CSS −2 to −4 s | 8–9 | short reps, generous rest; **optional** v1 | SwimTune |
| **Sprint** | max | 9–10 | **out of v1** except 25 m build/fast finishers | — |

Sources: https://swimtune.com/guides/css-critical-swim-speed ; https://blog.swimsmooth.com/p/understanding-training-zones ; https://blog.swimsmooth.com/p/red-mist-vs-css-training-why-both ; https://www.aquaplan.fit/blog/recovery-swim-workout ; zones-as-spans rationale (Envol Swimrun, "zones as spans, don't beat yourself up"): https://envolcoaching.net/2023/10/13/css-swimming/

**Pace by sustained-effort distance.** Swim Smooth's pacing post lists sustained efforts getting slower vs CSS as distance grows: (training-style) 200 m @ CSS, 400 m @ CSS+2, 600 m @ CSS+4, 800 m @ CSS+6, 1000 m @ CSS+8; and for events 1500 m ≈ CSS, 5 km ≈ CSS+2–4. I could not verify the exact context of the first list (training prescription vs race pace) — treat as a **range hint** that a *continuous 1000–1200 m proof at "steady" pace (CSS+6–10)* is on-pattern. https://blog.swimsmooth.com/p/get-your-pace-right **[C]**

**Race-pace relative to CSS (for forecasting).** One calculator guide: 400 m ≈ 95–97% of CSS pace (faster), 1500 m ≈ 100–102%, 1900 m ≈ 103–106%, 3800 m ≈ 107–112% (i.e., slower). https://www.trainingzones.io/en/guides/critical-swim-speed **[C]** → in v1, prefer the Riegel-style predictor (below) for the 800–2000 m band because it can be personalised from two points.

### 2.4 Set construction (Maglischo / Sweetenham & Atkinson / modern coach practice)

**Maglischo (endurance training types, as reproduced in a coaching-journal summary of *Swimming Fastest*)** **[B]**
- **Threshold repeats:** at lactate-threshold speed, sets of **20–40 min**, short rest (10–30 s on ≤400 m reps; 30–60 s on longer reps); lots of weekly exposure for elite swimmers (3–5 sets/week). Practical determination: T-30 or "a long set of repeats at the fastest sustainable average." Summary: http://kinisiologia.phed.uoa.gr/fileadmin/kinisiologia.phed.uoa.gr/uploads/01vol2no1.pdf
- **Overload endurance:** slightly *above* threshold (≈1–2 s/100 m faster), **15–25 min**, used sparingly (1–2 per week max for elite; "analogous to maxing out with weights").
- **Basic endurance:** ~4–5 s/100 m slower than threshold, ≥1000 m total, 5–30 s rest.
- **Fast-twitch fibre recruitment** needs some short, near-max efforts (e.g. 50–75 m with 3–4 min rest) — an elite-performance consideration, **not needed** for a continuous-capacity v1. https://rowperfect.co.uk/wp-content/uploads/2012/01/Training-fast-twitch-fibers.pdf ; book TOC (incl. "Warming Up and Swimming Down") https://books.google.com/books/about/Swimming_Fastest.html?id=cSSW4RhZOiwC

**Sweetenham & Atkinson / British Swimming zone sets** (HR "beats below max" — *do not transplant the HR rule; translate to pace via CSS*) **[B]**
- A1 low-intensity aerobic: e.g. 10×300 m @ 50 bbm
- A2 aerobic maintenance/development: e.g. 8×200 m @ 40 bbm on 3:00
- A3: 8×200 m @ 40 bbm on 2:50; AT: 24×100 @ 30 bbm on 1:25; VO₂/critical speed: 24×100 @ 20 bbm on 1:45
- Zone summary doc: https://www.southeastswimming.org/wp-content/uploads/2020/05/Physiological-Training-Models-P1.pdf ; A1/A2 used for "warm-up and warm-down, base conditioning and technical training": https://zwemfed.be/sites/default/files/2023_symposium_fv_bel.pdf ; book overview (Ch. 2 benchmark test sets, Ch. 13 training zone sets): https://www.rundna.com.au/p/championship-swim-training-by-bill-sweetenham-john-atkinson
- **Take-away:** even elite-oriented texts put *base-aerobic sets at ~200–300 m reps, ~10 reps, with generous but fixed intervals*, and treat A1/A2 as the default WU/CD intensity.

**Modern distance-triathlete / adult-swimmer set grammar (Swim Smooth, TrainingPeaks coaches, AquaPlan)** **[B/C]**
- **CSS 100s:** 10–15×100 @ CSS, 10–15 s rest, hold *even splits*; "if you can finish all reps with 10 s rest comfortably, reduce rest to 5 s or increase pace by 2 s." https://thetriathlete.co.uk/sessions/css-main-set-12x100m-pool-session/
- **Ladder at CSS** (Swim Smooth's named "Goldilocks" set — *branded name; don't reuse*): 3–4×100 @ CSS then a 200, repeat with 300, then 400 (cumulative time at CSS, not distance, scales with swimmer speed). https://scientifictriathlon.com/tts132/
- **Long-rep endurance:** 4–10×400 @ CSS+3–6 s with ~20–30 s rest; Swim Smooth's "Red Mist" branding (don't reuse). https://blog.swimsmooth.com/p/red-mist-vs-css-training-why-both
- **Broken goal distance at goal pace:** e.g. 15×100 @ CSS with 15 s rest; "3×500 at goal pace, 30 s rest" as race rehearsal for a 1500 goal. https://www.aquaplan.fit/blog/train-for-a-fast-1500m-freestyle
- **Aerobic rep-lengthening / rest-shrinking:** 5×200 @ steady 10–15 s rest → 4×500 → 10×400; then reduce rest to 5–10 s before continuous 1000 (r/triathlon top reply; SwimGym blog). https://www.reddit.com/r/triathlon/comments/1je1oz2/do_you_swim_the_full_distance_in_training_without/ ; https://swimgym.com/fast-lane/how-to-improve-your-endurance
- **Descending long sets** (e.g. 5×500 / 6×400 / 2×600+3×300+4×150) to prevent going out too hard (Tritheos). https://tritheos.com/setup-your-triathlon-swim-training-for-massive-swimming-improvements/
- **Technique/drill sets:** 4–10×50 as 25 drill + 25 swim, ≤15 s rest, placed *after* WU, before the main set (Rock Star Triathlete; Coach Ray lists KOS, 6/1/6, 6/3/6, broken arrow, Popov). https://rockstartriathlete.com/how-to-structure-your-own-swim-workout/ ; https://www.coachray.nz/2016/09/10/saturday-swim-session-build-400s-2/

### 2.5 Periodization and intensity distribution

- **Swimmer systematic review (9 studies, evidence 1b/2b):** sprinters polarized/threshold, middle-distance threshold/pyramidal, **long-distance mostly pyramidal**; wave-like meso-cycles are the dominant periodization; **no model shown superior**. https://journals.humankinetics.com/view/journals/ijspp/16/7/article-p913.xml **[A]**
- **2024 meta-analysis (endurance sports broadly, little swim data):** polarized beat other distributions on VO₂peak (esp. <12 wk interventions, highly trained) but no advantage in time trials/threshold. https://pmc.ncbi.nlm.nih.gov/articles/PMC11329428/ **[A]**; swim-specific small trial: polarized helped 100 m, pyramidal helped 800 m. https://www.mlsjournals.com/Sport-Research/article/download/2597/1343 **[A, small]**
- **Practical v1 rule:** *Pyramidal-leaning for distance goals*: ~75–85% of distance in Easy/Steady, ~10–20% Endurance-2/Threshold, ≤5% faster work; **at most one threshold-flavoured main set per week** and **≤1 Endurance-2 long-rep session per week** for ≤3 sessions/week athletes. (Rule is **[C]** — consistent with Swim Smooth's 3-session pattern and the 80/20 articles but not RCT-proven for adult recreational swimmers.)
- **Block structure:** 3-week build + 1 lighter week, or "weeks 4 and 8 recovery" in a 4-week block (TrainingPeaks 8-wk 1500 m programme). https://www.trainingpeaks.com/training-plans/triathlon/olympic/tp-284491/1500m-open-water-swim-programme-8wk **[C]**. Beginner plans (TrainingPeaks 1500m Focus 8/12/16 wk) explicitly have **no easy weeks** because volume is low. https://www.trainingpeaks.com/training-plans/other/swimming/tp-656782/1500m-focus-beginner-8-weeks **[C]**
- **Backward planning** from an event: FORM HeadCoach splits into base/build/taper and **contracts** the plan if the race is too close; recommends ≥2 swims/week for race plans. https://support.formswim.com/hc/en-us/articles/42290261828499-What-are-HeadCoach-Plans **[C]** (Fathom's analog: backward from *goal-day forecast*, contract to "capacity-only" when horizon is short.)

### 2.6 Volume and frequency progression

| Source | Rule | Grade |
|---|---|---|
| USMS ("Simple Ways to Add Volume Productively") | After holding yardage 4–6 weeks, raise **10–15% (20% if diligent/no injuries)** every 4–6 weeks; add across the week, not as a "distance day"; tweak set shapes (10×100 → 10×125). https://www.usms.org/fitness-and-training/articles-and-videos/articles/simple-ways-to-add-volume-productively-to-your-swimming-workouts | [B] |
| Third Coast Training | **+5–10%/week**; 45–60 min sessions; add frequency before lengthening; 3 sessions/week is the minimum for genuine improvement (Olympic-distance 3–4). https://thirdcoasttraining.com/how-to-build-swimming-endurance-guide-for-triathletes/ | [C] |
| Oliletriathlete | ≤10%/week; **recovery week at 80%** of peak after 4 weeks of progression; 2–3 sessions with ≥1 rest day; base phase 85–90% comfortable pace. https://oliletriathlete.com/swim-endurance-training-distance-burnout/ | [C] |
| Triathlete.com swim block | Aggressive 4-week block: +20–25% w1 (add a session), +20–25% w2 (lengthen sessions), dip w3, +20–25% w4. https://www.triathlete.com/training/how-to-successfully-execute-a-swim-focused-block/ | [C] |
| SwimTune | 2–3 sessions general fitness; 3–5 event prep; >~5/week recovery becomes limiting; test-week: cut volume 30–50%, keep one short sharp set. https://swimtune.com/guides/swim-training-load-recovery | [C] |
| Padlie beginner guide | Weeks 1–4: 1,000–1,500 m/session; weeks 5–8: 1,500–2,500 m; avoid volume before comfort; one technical cue per set. https://padlie.com/en/blog/beginner-adult-swimming-sessions-12-weeks | [C — "field heuristic, not validated"] |

**Reconcile for Fathom v1.** For *total weekly volume*: **+5–10%/week, ~80% deload every 3rd–4th week**. For *max continuous distance*: **+15–25% per rung** (fewer, larger steps because continuous distance is a skill-gated threshold; each rung gets a multi-session build). These two rules are compatible: e.g., a 20% continuous step over 2.5 weeks ≈ 7–8%/week.

### 2.7 Warm-up and cool-down — how they are typically structured

Evidence is mostly coach convention **[C]** (Maglischo's book has a "Warming Up and Swimming Down" chapter — I could not read its content; use as follow-up if a paper copy is available).

| Block | Typical content | Typical size | Sources |
|---|---|---|---|
| **Warm-up** | Easy swim mixed with non-free/kick/pull; short build; at least 100 m kick *or* different stroke; "never start the main set cold." | 400–800 m (≈15–20% of session); 200–300 m minimum for short sessions; 10–15 min | swimer.app 5-block model https://swimer.app/en/swimming-workout-structure ; Coach Ray https://www.coachray.nz/2017/05/27/saturday-swim-session-400s/ ; Breaking Muscle https://breakingmuscle.com/a-beginner-s-guide-to-structuring-your-swim-workout/ |
| **Technique / pre-set** | 4–10×50 (25 drill + 25 swim) or 3×(100 pull + 50 swim), ≤15 s rest | 200–400 m (10–15%) | Rock Star Triathlete; Coach Ray |
| **Main set** | Primary stimulus | 800–1800 m typical (≈40–50% of a 2–3 km session); "15–25 min focused intervals" (MySwimPro) | swimer.app; MySwimPro https://blog.myswimpro.com/2025/08/12/how-to-structure-the-perfect-swim-workout-and-stop-swimming-mindlessly/ |
| **Supplementary (post-main)** | Kick/pull/other stroke, light | 200–600 m | swimer.app |
| **Cool-down** | Very easy, technique-focused, any stroke allowed; stretch if desired | 100–300 m; 5–8 min (5–10% of session) | swimer.app; Rock Star: "no longer than 300 m" |

Test/proof-day variants: Swim Smooth/Outdoor Swimmer test sessions are **2,100–2,900 m total** around a 400+200 test (WU, drills, test, long recovery, CD). For a proof swim, put the proof *first after a shortened WU* so it is judged fresh.

### 2.8 Heart rate and load: what to avoid for GT5

- Wrist optical HR during swimming degrades with water film and arm motion. Studies: Polar M600 vs H10 limits of agreement −53.0 to +33.9 bpm; temple OH1 −26.9 to +24.7 bpm (PLOS One, https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0231522); a 2025 front-crawl study found wrist HR vs chest strap R² 0.01–0.06 stepwise (MDPI, https://www.mdpi.com/2076-3417/15/11/5848); a 2026 Scientific Data paper explicitly notes no prior dataset of this kind — https://www.nature.com/articles/s41597-026-08084-4 **[A]**.
- **Session-RPE × duration** is a validated, low-friction load proxy in swimming (r = 0.55–0.94 vs HR-based; Wallace/Slattery/Coutts 2009), but sRPE is influenced by rep distance and volume at equal relative intensity (IJSPP 2015: 5×400 at critical speed felt harder than 20×100 for equal volume). https://opus.lib.uts.edu.au/handle/10453/9495 ; https://journals.humankinetics.com/view/journals/ijspp/10/7/article-p848.xml **[A]**
- **Engine implication:** intensity = **pace vs CSS**; load = **duration × sRPE** (ask 1 tap post-session) plus distance; HR only as hint (already "locked" HR in the insight contract).

---

## 3. Public / licensable / reference datasets

### 3.1 Inventory (what exists, what it is, can Fathom use it?)

| Source | What it contains | Access / terms (as observed) | Useful for a *training-program rules pack*? |
|---|---|---|---|
| **USA Swimming SWIMS** | Official meet times (membership-linked). Public lookup on usaswimming.org; "Open Water times are not included" (Times Policy Manual). | Third-party **vendor API requires application/review**, tiered (Tier 3 = times/member verification), MDSA + Vendor API License; "unauthorized redistribution is strictly prohibited." https://www.usaswimming.org/times ; https://websitedevsa.blob.core.windows.net/sitefinity/docs/default-source/technology/api-access-program-application.pdf?sfvrsn=c75c1932_1 ; https://devswimsthirdpartydocs.usaswimming.org/ | **No.** Race times of competitive members; no training logs; not licensable for this use. Could in principle inform time-standard curves, but not needed. |
| **NCAA** | D-I official times flow through SWIMS under a USA Swimming–NCAA times partnership; season-best lists at usaswimming.org/DI. https://ncaaorg.s3.amazonaws.com/championships/sports/swimdive/d1/2025-26D1XSW_MEMOPreSeasonInfo.pdf | Public lists; no bulk/commercial grant found. | **No.** Elite/collegiate race performances. |
| **SwimCloud (CollegeSwimming.com)** | Meet results/top times (submitted by meets; **does not sync with SWIMS**). | Site ToS binds users; no explicit scraping grant found. A third-party scraper exists (SwimScraper) — existence ≠ permission. https://www.swimcloud.com/terms/ ; https://support.swimcloud.com/hc/en-us/articles/7159725331347-Submitting-Meet-Results ; https://github.com/maflancer/SwimScraper | **No** (legal risk + wrong data). |
| **World Aquatics** | Rankings/reports at api.worldaquatics.com (public PDFs); data.worldaquatics.com GMS. | GMS terms: users shall not copy, distribute, create derivative works from info obtained; site legal page asserts all content/data is World Aquatics-owned. Commercial feeds exist via paid vendors (e.g. DataSportsGroup swimming API). https://www.worldaquatics.com/legal ; https://data.worldaquatics.com/TermsAndConditions/TermsAndConditions.htm ; https://dsg-api.com/doc/swimming/get_results/485/ | **No.** Elite race results; restricted; irrelevant to adult capacity milestones. |
| **Strava API** | User-authorized activity data incl. swims. | API Policy **§5.3 (effective June 1, 2026)** forbids using Strava Data (or anything derived/aggregated/anonymized from it) in connection with developing, training, evaluating, grounding or operating **any AI Application**, incl. context-window ingestion; official route is Strava's own MCP for subscribers' personal use. https://cdn-1.strava.com/legal/api_policy ; https://communityhub.strava.com/developers-api-7/is-my-app-compliant-13485 | **No.** Fathom is Huawei-sourced; Strava data is per-user, policy-fenced, and not a program corpus. A deterministic rules engine is not an "AI Application," but do not feed Strava data to any model or to future Coach without legal review. |
| **Garmin Connect Developer Program** (Health/Activity/**Training API**) | Push workouts/plans to a user's Garmin calendar; read activity/health data via OAuth 2.0. | Business-use only, application + approval (2 business days to status, 1–4 wk integration); no program fee, but **some metrics may require license fee/minimum device order**. Connect IQ is a separate SDK program. https://developer.garmin.com/gc-developer-program/training-api/ ; https://developer.garmin.com/gc-developer-program/program-faq/ | **Not a content source.** It's a *delivery* rail for *your* plans to *Garmin* watches. Fathom targets GT5 → not applicable for v1. Garmin Coach plan content (coach-authored, adaptive) is proprietary; Garmin lists run/cycle/strength/triathlon coaches — a swim-only coach was not found in sources reviewed. https://www.garmin.com/en-US/blog/fitness/five-ways-to-use-garmin-coach-on-your-watch/ ; https://garminrumors.com/garmin-adds-triathlon-coach-to-adaptive-training-lineup-here-are-the-details/ |
| **MySwimPro** | Hundreds of guided workouts, plans, "DynamicSwim" scaling, Personalized Intervals, test sets. | Proprietary app; ToS consumer-use, "as is," medical disclaimers; **no public API/dataset found**. Support docs describe the *Set schema* (reps, distance, stroke, interval, effort level, equipment). https://myswimpro.com/terms-of-use/ ; https://support.myswimpro.com/en/articles/6350436-getting-started-with-myswimpro | **Learn vocabulary and schema ideas only.** Don't ingest or copy workouts. |
| **FORM** (goggles + app) | 1,500+ workouts, HeadCoach plans (4–12 wk) | Premium subscription; proprietary; can import TrainingPeaks/TriDot workouts and "Script" text → guided workout. https://www.formswim.com/pages/premium | **No dataset.** Product analog only. |
| **TrainingPeaks plan marketplace** | Paid, human-authored plans (e.g. "1500m Focus – Beginner 8/12/16 wk", Nick de Meyer open-water plans) | Copyrighted per-author products. Plan *descriptions* are public. | **Learn structure** (cadence, weekly time, test-week placement); don't reproduce sessions. |
| **USMS Workout Library** | Coach-written workouts (7 specialties) + **35** six-week plans (six nonstop-capacity plans); Swim.com watch delivery | **Member-only**; no open license or API; Swim.com is delivery, not a data feed (and not GT5). https://www.usms.org/workout-library | **Distill only.** Optional $75 membership for aggregate shape of unread nonstop PDFs — not a product dataset. |
| **Community workout DBs** (e.g., Swimwestside coach archive) | ~500+ coach-written Masters workouts, searchable | "Free resource" statement in a USMS community thread; **no explicit license**. https://community.usms.org/swimming/f/workouts/19665/new-free-workouts-database-online | **Don't ingest.** Could ask the author for permission if desired. |
| **Zenodo — Barry et al. 2022** (Swim Ireland training-load/injury surveillance dataset) | sRPE, session duration, volume, injury surveillance in competitive swimmers (related 104-week study: weekly volume ≈ 33.5 km!) | Open on Zenodo (record exists; exact license/variables **not verified** here). https://pure.ul.ie/en/publications/the-design-and-evaluation-of-an-integrated-training-load-and-inju/ ; https://www.mdpi.com/2076-3417/14/22/10411 | **Weak fit.** Elite pathway swimmers training ~33 km/wk; useful only as an upper bound sanity check on load models, not for adult rec milestones. |
| **youngSwimmers (R package)** | Cardiac autonomic modulation dataset, young swimmers across competition periods | Open R package. https://rdrr.io/cran/youngSwimmers/f/README.md | **No** (physiology of adolescents). |
| **IMU / wearable swim datasets** (ISWC 2019 lap counting: 40 swimmers, 30 Hz IMU; Kaggle swimming-styles IMU; Kaggle multimodal technique; Scientific Data 2026 wearable HR-in-water) | Labeled sensor streams | Open on GitHub/Kaggle/Nature (licenses vary; **verify each**). https://github.com/brunnergino/swimming-recognition-lap-counting ; https://www.kaggle.com/datasets/ruslanbredun/swimming-styles-imu-data ; https://www.nature.com/articles/s41597-026-08084-4 ; HR CSV on Zenodo https://zenodo.org/records/18992173 (CC BY 4.0) | **No** for plan craft. **Yes** for Q4 sensor R&D / HR honesty. Full map: `2026-10-09-swim-data-sources-four-questions.md`. |
| **Hugging Face `t22000t/swimming-resources`** | 410-entry **directory** of swim resources (19 "training plans" links), JSON/Parquet | Open dataset (check dataset-card license). https://huggingface.co/datasets/t22000t/swimming-resources | **Bookmark list, not content.** Handy for citation hunting. |
| **Open Swim Workout / swiML / OpenSwim** | Prescription **formats** (+ small MIT workout samples in OpenSwim) | https://www.openswimworkout.com/ ; https://swiml.org/ ; https://github.com/Danielbunckenburg/openswim | **Schema candidates** for Agon sessions — not measured-athlete datasets. |
| **Peer-reviewed literature** (Wakayoshi, Dekerle, TID review, sRPE papers) | Formulas, ranges, validity | Citable; **facts and formulas are reusable; text is not.** | **Yes — the primary legitimate input.** |

### 3.2 Direct answers to the specific questions

- **"OpenPowerlifting-style analog for swimming?"** **None exists** that is open, structured, and programmatically reusable. Competitive swim results are fragmented across federation systems with restrictive terms; there is **no public athlete-level training-log corpus** and **no public (baseline → plan → outcome) trajectory dataset**. Anything you hear described as one is either per-user app data or a scrape.
- **"Garmin Connect IQ or research exports?"** Connect IQ is a *watch-app SDK* program (no data corpus). Garmin's Connect Developer Program is *data access with the user's consent + business approval*, not an open dataset. Research exports are small, lab-collected, and study-specific.
- **"Is MySwimPro / Garmin Coach data usable?"** **Proprietary-only.** You may study published structure and generic coaching vocabulary; you may **not** assume rights to workout libraries, personalization models, or plan outputs. No public API or bulk export was found for MySwimPro; Garmin's rails push *your* content *to* Garmin devices.
- **"Strava?"** Policy as of June 1, 2026 blocks AI/ML-adjacent uses even for transient per-user inference and even for anonymized derivatives; not suitable as a corpus.

### 3.3 License vs distill vs build-own

| Option | What it means | Cost / time | Legal risk | Fit to Fathom constraints | Verdict |
|---|---|---|---|---|---|
| **License a feed** (MySwimPro/Garmin/USMS/vendor) | Pay for workouts/plans or API | Unknown, likely commercial negotiation; dependency; offline/local-first conflict | Low once signed, but **no known licensable swim-plan feed was found** | Violates R11 ("MUST NOT depend on licensing a third-party feed") | **Reject for v1** |
| **Distill from public knowledge** | Extract formulas/ranges/generic patterns from literature + coach texts; write original sets | Days–weeks of authoring + review | Low if you cite-not-copy, avoid trademarked set names, avoid scraping | Matches R8/R11; deterministic; explainable (S5) | **Do** |
| **Build-own from Fathom data** | Calibrate thresholds (rung size, fail rules, pace gain) from the owner-athlete's own sessions; later opt-in multi-user | Ongoing; needs outcome labeling | None (own data) | Matches local-first; improves with use | **Do (layer on top of distill)** |

**Recommendation:** **Distill + build-own, license nothing in v1.** Concretely:
1. **Provenance registry** — every parameter in the pack (`source_id`, `url`, `evidence_grade`, `transform` notes, `owner_review_date`).
2. **Original authoring** — write set descriptions in Fathom's own words and notation; avoid branded names (Swim Smooth's "Goldilocks," "Red Mist"; MySwimPro "SwimGauge," "DynamicSwim"; FORM "HeadCoach").
3. **Calibration loop** — log `proof_result`, `rung_step`, `pace_at_proof`, `sessions_between_proofs`, sRPE → adjust defaults in Fathom-owned config (grade **[D]**).
4. **Optional human review** — a one-time paid review by a certified swim coach is cheaper and safer than licensing a feed; collect a short sign-off note per pattern family.
5. **Keep a "future licensing" door open** only for (a) USMS partnership if Fathom later wants official masters workouts, (b) Garmin Training API if Fathom adds Garmin export.

---

## 4. Community practice (Reddit and forums)

**Access note:** Reddit direct fetch blocked; findings are from indexed snippets of the linked threads (verify quotes in-browser). "r/Swimmit" = historical name of r/Swimming (2010 announcement). r/Swimming ≈ 598K members at time of search.

### 4.1 How people build longer continuous pool distance

- **Typical timelines (adults):**
  - "4–6 weeks depending on form and how fast you want to swim it" (for a 'decent swimmer' to a nonstop mile). https://www.reddit.com/r/Swimming/comments/1j2icwn/for_a_decent_swimmer_how_long_would_it_take_to/
  - One reply: "about 2–3 months" for a mile after years away; another: a year from 250 yd to 2000 yd, "technique and mindset, not pure fitness." same thread.
  - Couch-to-1k in 14 weeks questioned as **"not realistic, but not impossible… not linear growth."** https://www.reddit.com/r/Swimming/comments/1v1cujf/couch_to_1k_doable_in_14_weeks/
  - Practitioner blog: **one length → 500 m takes ~8–12 weeks at 2–3 sessions/week** for most adults. https://chrisyau.me/en/blog/building-swimming-endurance
- **Progression recipes that recur:**
  - **Rep-length ladder**: 100s → 200s → 400s → 800s → 1650 with set breaks, "once you get to 800 without stopping you have probably already found a pace; you can often skip to 1650." https://www.reddit.com/r/Swimming/comments/1r05pfb/adult_swimmer_how_did_you_build_up_to_a_mile/
  - **Rest-shrink ladder**: 5×200 @ 10–15 s → 4×500 → reduce rest to 5–10 s → then continuous 1000 (r/triathlon, SwimGym). Links in §2.4.
  - **Ruth Kazez "Zero to 1650 in six weeks"** (3 days/week, rest measured in *breaths*): weekly totals ~700 → 900 → 1200 → 1500 → 1600 → 1650/1500 continuous; longest continuous piece: 400→600→1000→1200→(full). Note the "yardage/rest" design. https://ruthkazez.com/swimming/ZeroTo1mile.html ; FitDrills variant https://www.fitdrills.com/swim-1500-m-for-beginners/
  - **TrainingPeaks "1500m Focus – Beginner" (8/12/16 wk, 3 swims/week, ~1 h longest session, ends at 1,500–2,200 m/session)** — written for "can swim ~1000 m with breaks" athletes (very close to Fathom's dogfood baseline). https://www.trainingpeaks.com/training-plans/other/swimming/tp-656776/1500m-focus-beginner-12-weeks — and the 16-wk version https://www.trainingpeaks.com/training-plans/other/swimming/tp-656725/1500m-focus-beginner-16-weeks
- **Milestone thinking in the wild:** "You should be able to swim your race distance non-stop in a single interval *before the event*" (top r/triathlon reply) alongside "it isn't strictly required; know you can recover." People self-set **sub-distance proofs** (500, 800, 1000, then goal) and "register late as possible." https://www.reddit.com/r/triathlon/comments/1je1oz2/do_you_swim_the_full_distance_in_training_without/ ; https://www.reddit.com/r/Swimming/comments/1v1cujf/couch_to_1k_doable_in_14_weeks/

### 4.2 Common mistakes (recurring across threads and coach blogs)

1. **Swimming everything too hard.** "Triathletes are notorious for swimming hard all the time" (Tritheos); recovery swims should be 10–20 s/100 m slower than normal easy (AquaPlan). → Engine: enforce Easy/Steady share and cap threshold exposure.
2. **Breath-holding / panic breathing.** Repeated top advice in r/Swimming and r/triathlon: "exhale continuously underwater, breathe every 2nd stroke, nose bubbles, use a pull buoy to find rhythm"; "breathing is the limiting factor" for adult beginners. https://www.reddit.com/r/triathlon/comments/1vtf3j4/really_struggling_with_swimming_looking_for_any/ ; https://padlie.com/en/blog/beginner-adult-swimming-sessions-12-weeks → Engine: prescribe *breathing-rhythm* cue patterns; stage `pull` sets early.
3. **Swimming to exhaustion then resting 5 min.** Replace with shorter intervals that preserve stroke quality; "rest or drop to a shorter interval when stroke count jumps ≥4 per length, breathing becomes gasping, hips sink." (single-author coach blog **[C]**) https://chrisyau.me/en/blog/building-swimming-endurance → Engine: watch for stroke-count and pace fade as stop/shorten signals (Fathom has SWOLF/strokes per length).
4. **Over-kicking / too many technique fixes at once.** "80% upper body, 20% legs" (coach comment); "one technical cue per set" (Padlie). 
5. **Ignoring feedback.** "You can't cardio your way to swimming faster like the bike and run… swim more, with critique and feedback"; "technique is 80% of the battle." https://www.reddit.com/r/triathlon/comments/1djf62x/swimming_pace_has_plateaued_at_what_point_do_i/ → Engine can't give video feedback; surface *stroke count/SWOLF trends* and suggest "get coached eyes" only as a copy hint.
6. **Mis-run CSS tests** (sandbagged 200; no recovery; tired day). Outpace and Envol docs above.
7. **Plateau handling.** Advice: add frequency (2–3 → 4–5/wk gave 2:00 → 1:40/100 in 4–5 wk for one commenter), reduce rest on aerobic sets, add short fast 25/50s, expect fatigue "beatdown" for several weeks before supercompensation. https://forum.slowtwitch.com/t/swim-plateau-1/687781 (anecdotal **[C]**)
8. **Wall push-offs inflate perceived endurance** (short-course vs long-course differences); keep pool length consistent in proofs. (Comment in r/triathlon thread; plus SC→LC conversion shock ~2–3% per a calculator blog **[C]**.)

### 4.3 Plans people actually follow (observed)
Ruth Kazez 0→1650; Swim Smooth (CSS-based, 3-session week; "Guru" plans); TrainingPeaks beginner/1500 m plans (human-authored); MySwimPro / FORM guided plans; USMS 6-week plans; self-built "rep-length + rest-shrink" ladders. **No single canonical plan**; consensus pattern is *3 swims/week, easy-heavy, one long-rep session, one CSS session, progressive rep length, test every ~6–8 weeks.*

---

## 5. Product analogs: emulate vs avoid for a local milestone-led product

| Product | Plan craft (observed) | Emulate | Avoid for Fathom |
|---|---|---|---|
| **MySwimPro** | Plans from profile, goals, seed times, skill level, available days, event date (+taper); **DynamicSwim** scales distance while preserving structure; **Personalized Intervals** from best times; test sets ≈ every 12 workouts; "swap workout" without breaking plan; set schema = reps, distance, stroke, interval, effort level, variation, equipment; set groups = Warm up / Drill / Pre-Set / Main / Post / Cool down. https://support.myswimpro.com/en/articles/9741919-new-improved-personalized-swim-training-plans-more-personalized-than-ever ; https://support.myswimpro.com/en/articles/6350436-getting-started-with-myswimpro ; https://support.myswimpro.com/en/articles/6809628-test-sets | **Set/Set Group schema**; effort-level taxonomy (7 levels ≈ our 5); periodic test cadence; swap/skip friendliness; distance scaling "keep shape, scale volume." | Opaque "AI-powered" adjustments; cloud/subscription gating of personalization; 100 m race-pace tests as the only metric (not distance-capacity-led). |
| **Garmin Coach (+ Triathlon Coach)** | Adaptive plans from ability, goal, recovery, sleep, performance; Triathlon Coach has adaptive freestyle swims; user sets *comfortable swim distance*, plan adjusts; two-a-days & bricks. https://www.garmin.com/en-US/blog/fitness/five-ways-to-use-garmin-coach-on-your-watch/ ; https://garminrumors.com/garmin-adds-triathlon-coach-to-adaptive-training-lineup-here-are-the-details/ | **User-declared comfortable distance** as intake; daily adaptation framed as "adjusting the next workout," low drama. | Recovery/sleep-driven *hard auto-downgrade* (out of v1 per R18); race-date-centric framing; no swim-only product; Garmin-ecosystem lock-in. |
| **FORM HeadCoach Plans** | 4–12 wk plans, 1–7 swims/week, objective-driven; race plans backward from date with base/build/taper; **plan contracts if too little time**; adapts on pace/volume/technique; **user accepts or rejects proposed changes**; per-swim feedback + next-swim focus (HeadCoach 2.0). https://www.formswim.com/blogs/all/personalized-training-with-headcoach-plans ; https://support.formswim.com/hc/en-us/articles/42290261828499-What-are-HeadCoach-Plans ; https://www.formswim.com/blogs/media/form-introduces-headcoach%E2%84%A2-2-0-expert-coaching-tailored-to-your-goals | **Accept/reject adjustments**; "contract the plan" when the horizon is short; **one focus per next swim**; transparency about why a change happened. | Dependence on AR-goggle sensors; subscription ($9.99/mo class pricing); technique scoring that Fathom (GT5 wrist) can't measure. |
| **TrainingPeaks swim plans** | Static, coach-authored, **test sessions in week 1** to set T-pace; 4-week blocks (recovery w4/w8), endurance/technique/open-water weekly rhythm, 3 swims + optional strength; zone anchor = threshold pace; synced structured workouts. https://www.trainingpeaks.com/training-plans/other/swimming/tp-179731/1500-metre-front-crawl-open-water-swim-12-week-plan | **Week-1 baseline test**; weekly **role** rhythm (endurance / technique / quality); explicit weekly time and longest-session metadata. | Fixed calendar not responsive to proof outcomes; paid per-plan; open-water emphasis. |
| **Swim Smooth CSS ecosystem (Guru)** *(adjacent)* | CSS-based zones; 3-session week (aerobic / technique-recovery / CSS threshold); 10-week CSS development; retest 4–6 wk. | **One anchor number + three weekly roles**; "improve by X s/week" expectation management. | Brand-named sets; swimmer-type typology (needs stroke video). |

**Net design stance:** Fathom = *MySwimPro's set grammar* + *TrainingPeaks' weekly role rhythm and baseline test* + *FORM's accept/reject + plan contraction* + *Garmin's user-declared comfortable distance*, with *proof swims as the unit of progress* (none of the four center milestone proofs; FORM/MySwimPro center race/event dates).

---

## 6. Fathom Programs v1 — concrete rules-pack recommendation

> Defaults below are **proposals** to be validated against the owner-athlete. Each is tagged with evidence grade; **[D]** = needs Fathom calibration.

### 6.1 Metrics to compute (inputs from history + sessions)

| Metric | Definition | Notes / source |
|---|---|---|
| **`pool_len_m`** | 25/33⅓/50 m per session | Normalize SWOLF to 25 m; never mix course types in tests/proofs without labelling. (Intervals.icu SWOLF discussions: https://forum.intervals.icu/t/swimming-statistics-swolf-strokes-length-stroke-distance/11387) |
| **`MCD` (max continuous distance)** | Longest swim segment with no rest gap > `rest_gap_s` (default **15 s**; tune [D]) in the last 42 days, free stroke dominant | Core capacity metric; drives rungs. |
| **`best_efforts`** | Best average pace over contiguous segments ≥200 m and ≥400 m (and ≥800 m if present) in last 56 days | Garmin-style auto-CSS idea: varied efforts across distances. |
| **`CSS_test`** | `(T400−T200)/2` per 100 m from a guided/recorded test | Gold standard in-app; confidence = high if test valid. |
| **`CSS_hist`** | From `best_efforts` pair (long, short) with distances differing ≥2× (e.g., 400/200 or 800/400): `CSS = (Dl−Ds)/(Tl−Ts)` | Label **provisional**; require agreement check (see 6.2). |
| **`CSS_active`** | Preference: fresh `CSS_test` (≤ 8 wk) → proof-derived update → `CSS_hist` (≤ 8 wk) → self-report | Store `confidence` + `age_days`. |
| **`riegel_b`** | Fatigue exponent: default **1.06**; personal `b = ln(T2/T1)/ln(D2/D1)` when two recent efforts exist; clamp 1.03–1.12 | https://swimmingregimen.com/tools/time-predictor ; calculator ranges 1.05–1.10 https://calculatrex.com/swimming-race-time-predictor **[C]** |
| **`T_pred(D_goal)`** | `T_ref × (D_goal/D_ref)^b`, ref = best of {CSS-test 400, proof, best-efforts} | Cross-check vs CSS table (§2.3). |
| **`gap_ratio`** | `T_pred(D_goal) / T_goal` | Drives feasibility class at intake. |
| **`steady_pace`** | `CSS_active + 8 s` (range +6…+10); if no CSS: pace of last continuous ≥200 m | For capacity proofs. |
| **`fade_pct`** | (pace of last third − pace of first third)/pace(first third) on a continuous swim | Even-pacing quality; also a guard for "went out too hard." |
| **`stroke_drift`** | Δ strokes/length last third vs first third; SWOLF drift (25 m-normalized) | Technique-under-fatigue marker; threshold of "≥4 strokes per length jump" is a blog heuristic **[C]**. |
| **`sRPE_load`** | session RPE (1–10) × minutes | 1-tap post-swim; **[A]** validity vs HR-based in swimmers. |
| **`adherence`** | % prescribed sessions matched, rolling 14 d | Used for pacing, not for gating milestone dates (R15, R22). |
| **`hard_share`** | % of session distance in Endurance-2/Threshold/Fast | Guardrail vs "swim everything hard." |
| **`time_since_test`** | Days since valid CSS test | Triggers re-test prompt at ~42 d. |

HR is **not** used to set zones (GT5 wrist HR in water: §2.8).

### 6.2 Baseline cascade (thresholds proposals)

**"Sufficient history" (R7 placeholder)** — all must hold over last **56 days**:
- ≥ **4 pool swims** (≥ 600 m each) and ≥ **2 distinct weeks** with swims;
- ≥ **1 continuous segment ≥ 400 m** (for CSS_hist) *or* an explicit continuous capacity signal (`MCD`);
- Segments not flagged as mixed-stroke only (allow if free ≥ 70%).
→ else **guided test**.

**Guided test menu (choose by `MCD`):**

| `MCD` | Test | Output |
|---|---|---|
| ≥ 500 m | **CSS 400/200** (WU 300–500 + 4×50 build; 400 TT even-paced; 10–15 min easy/rest; 200 TT; CD 200) | `CSS_test`, `MCD≥400`, first `Riegel` point |
| 300–499 m | **Capacity test**: continuous swim to comfortable stop at steady effort (RPE ≤5) + 6×100 timed @ steady (T-pace style) | `MCD`, `steady_pace`; **no CSS yet** (CSS comes after first rung) |
| < 300 m | **Pre-ladder (Zero-to-X)**: Kazez-style breathing-rest sets | Skip pace track; capacity-only |

**Self-report fallback:** best recent continuous distance + time (or "can/can't do 400"); confidence = **low**; first block must be **conservative** (rung step 0.10–0.15; no threshold sets).

**Consistency check** (history CSS vs reality): if `CSS_hist` implies a 1500 m pace faster than the athlete's longest recent continuous swim pace by > 5%, downgrade to "provisional – re-test in week 1." (Grade **[D]** — Garmin auto-CSS "3–10 s/100 m off" claim supports caution.)

### 6.3 Milestone ladder algorithm (placement)

**Inputs:** `D_goal`, `T_goal`, `H` (weeks), `n` (sessions/week ∈ [2,5]), baseline (`MCD`, `CSS_active`, `confidence`).

1. **Feasibility triage at intake** (honest copy):
   - `p_goal = 100·T_goal/D_goal` (s/100).
   - `p_pred = 100·T_pred(D_goal)/D_goal`.
   - `Δp = p_pred − p_goal` (s/100; ≤0 means already there).
   - Weeks to close pace gap (planning bounds): `W_pace = Δp / g`, with **g ∈ [0.3, 0.5] s/100/week** (Swim Smooth; vendor guidance) and a **plateau** after ~8–12 weeks.
   - Weeks to close capacity gap `W_cap`: rungs needed × block length (below).
   - **Classes:** `A` (≤1.00: capacity only), `B` (1.00–1.05: normal), `C` (1.05–1.10: stretch—flag), `D` (>1.10 *or* `W_pace > H`: warn + offer revised time/horizon, but allow user to proceed with "ambitious" label).
2. **Capacity ladder** — rungs `R_0 = MCD`, `R_k = round_to_50(R_{k-1}·(1+s))` with **`s` default 0.20** (range **0.15–0.25**; use 0.10–0.15 if `confidence = low` or `MCD < 600`); last capacity rung capped at `D_goal`. Dogfood: `1000 → 1200` (+20%) is exactly the default rung (R13, S1).
   - Optional absolute weekly step (USMS 500-yd nonstop aggregate): `weekly_step = clamp(0.10·D_goal, 45 m, 0.25·MCD)` — relative `%` naturally decays as distance grows.
   - **`ladder_shape`:** `linear_to_goal` when `D_goal ≲ 800 m` (rehearse up toward goal); `capped_rehearsal` when `D_goal ≳ 1,500 m` (rehearse to ~0.6–0.8·`D_goal` + broken near-goal, then full Trial). Dogfood 1,200 m: default `linear_to_goal` **[D]**. (USMS 1-mile plan rehearses only ~61% before final.)
   - Use `round_to_pool_len_multiple` (e.g. 25 m×k) so continuous proof is turn-aligned.
   - Optional **intermediate "rehearsal rungs"** (non-proof) if `R_k − R_{k-1} > 300 m`.
   - Proof pass variants: continuous with `rest_gap_s ≤ 15` (default); optional **`pass_with_split`** (≤5 s pause to read time) — USMS 1-mile plan shape **[B/D]**.
3. **Block length per rung** (time between proofs): `L = ceil(sessions_needed / n)` weeks where `sessions_needed ≈ 6–8` for default step (2 aerobic-ladder + 2 rest-shrink/long-rep + 1 CSS/quality + 1 rehearsal + 1 shortened prep) → **~2.0–2.5 weeks @ 3–4×/wk; ~3–4 weeks @ 2×/wk**. If `n = 5`, block still ≥ 2 weeks (recovery). Cap rung block at **3 weeks** for dogfood alignment (R13: "2–3 weeks"). **[D]** (heuristic: no source specifies exact sessions-per-rung).
4. **Pace proofs** *(only if `T_goal` is present and `gap_ratio > 1.0` when capacity rung hits ≥ 0.8·`D_goal`)*:
   - **P1 (broken)**: `k × (D_goal/k)` at goal pace, ≤15 s rest, e.g. 3 × 400 for 1200 (cf. "3×500 at goal pace" race rehearsal for 1500; AquaPlan).
   - **P2 (long continuous)**: `0.6–0.7·D_goal` at goal pace.
   - **P3 (full)**: `D_goal` at goal pace — **the "goal-day" trial**; derived date.
5. **Insert CSS retests** at ~6-week intervals (or at rung boundaries); a retest **may replace** a rung's quality session. After a retest: recompute `CSS_active`, `T_pred`, `gap_ratio`, and **forecast** (6.8).
6. **Proof-day placement:** day after a rest/easy day; never within 24 h after a threshold session; two easy/technique days max before it; **proof is first work item after a short WU** (fresh), then CD. Reduce prior-3-day volume by ~30% (test-week practice per SwimTune).
7. **Horizon fitting:** if ladder + P-steps > `H`, either (a) compress by increasing `s` up to 0.25 (never above), (b) drop intermediate rehearsal rungs, (c) change the goal-day target to the last feasible rung and show "ultimate goal beyond horizon," or (d) extend horizon (user choice). Never silently compress below the minimum number of sessions per rung.

### 6.4 Scale volume by sessions/week

**Session length cap:** 45–60 min default (Third Coast, field consensus **[C]**); beyond that, add sessions before lengthening.

**Weekly role templates**

| `n` | Roles (ordered by priority if the user can only do some) | Notes |
|---|---|---|
| **2** | S1 **Endurance (long-rep + rest-shrink ladder)**; S2 **Quality** alternating CSS-reps / technique+aerobic | FORM recommends ≥2/wk for race plans; slower rungs (≈3–4 wk). 2/wk is "maintain + slowly build" per Third Coast's 3-session minimum claim → show a gentle note. |
| **3** (default, dogfood) | S1 **Endurance**; S2 **CSS/Quality** (threshold *or* goal-pace rehearsal); S3 **Technique + Aerobic** (easy/steady) | Mirrors Swim Smooth's weekly pattern. |
| **4** | Add S4 **Aerobic-volume / pull-kick support** (Easy/Steady) *or* second Endurance-light | Intensity share unchanged (extra sessions are easy). |
| **5** | Add S5 **Easy recovery / technique**; keep max **one** threshold-type and **one** long-rep per week | >5 not offered in v1 (recovery becomes limiting). |

**Volume targets (reference ranges; **[D]** calibrate)**
- **Key-session total distance** for adult *capacity* Agons: **`clamp(1,300–2,000 m)` per 45–60 min** (USMS nonstop plan sessions ≈1,370–1,960 m regardless of goal; Swim England 20-session ends ~2,000 m). The old **1.5–2.0 × `D_goal`** multiplier only informs when `D_goal ≥ 1,000 m` and still respects the clamp. Padlie median 4,300 m is club/competitive — upper bound sanity, not recreational default.
- **Support sessions** ≈ **0.8–1.2 × `D_goal`**, still within a softer clamp (~1,000–1,600 m).
- **Weekly:** `W_week(t+1) ≤ 1.10 × W_week(t)` (default +8%); **deload** every 3rd–4th week at ~**80%** of previous peak (Oliletriathlete; Triathlete's "week 3 dip" pattern); proof week uses −30% pre-proof. USMS-A7's +10–15%/4–6 wk is a *maintenance→more yardage* cadence — label separately from capacity-building weekly ramp.
- Start where history says: seed `W_week(0)` = median of last 4 non-zero weeks (floor 4 weeks of data) else `n × max(600 m, 0.9·MCD)`.
- Default **`n = 3`**; USMS nonstop plans assume **4/week** — note in provenance; optional n=4 shortens ladder blocks ~33%.

**Rest-interval policy** (reduces confusion): pattern schema supports `interval_mode: rest | sendoff`. *Endurance* sets: fixed **rest** ≤ 30 s at start, shrink 5 s per exposure toward 10 s then 5 s (or a send-off ladder for capacity — USMS-A8). *CSS reps*: **send-off = rep time at CSS + 10–15 s**; *Technique*: rest ≤15 s.

**Content safety:** never prescribe breath-hold / “as far as you can without breathing” sets (USMS shallow-water blackout warning). Planned breath-*counts* only, with stop-if-unwell copy.

### 6.5 Minimum session vocabulary (set patterns)

Designed as parameterized templates (`reps × distance @ effort, rest`) that scale to volume and `n`. **Author in Fathom notation; do not copy vendor text.** Suggested minimum **~20 patterns** in 5 roles.

**Notation:** `reps×dist` · effort ∈ {E=Easy, S=Steady, T=Tempo/Endurance‑2, C=CSS threshold, F=Fast} · `r` = rest · `+x` = pace offset vs CSS.

| ID | Role | Pattern (parametric) | Intent / when | Scaling |
|---|---|---|---|---|
| **WU1** | WU | 1×(200–400) E, free/choice stroke | default warm-up | WU = clamp(300, 0.15·S_total, 600) |
| **WU2** | WU | 200 swim E + 100 kick E + 100 pull E (+ optional 4×50 build) | adds kick/pull variation | when S_total ≥ 1800 |
| **WU3** | WU | 4–6×100 build 1→4, r=15 | before quality/test | quality days |
| **WU4** | WU/PRE | 6–10×50 (25 drill + 25 swim) E/S, r≤15 | technique prime | after WU1 |
| **PRE1** | PRE-proof activation | 4×50 S + 2×25 build, r=20 | before proof/test | proof/test days only |
| **AE1** | Main (Endurance) | `k×200 S, r=15→10` (k=5…8) | base aerobic, rest-shrink entry | early rung |
| **AE2** | Main | `k×300 S, r=15→10` (k=3…6) | rep-length ladder | mid rung |
| **AE3** | Main | `k×400 S/T (S→T on last), r=20→10` (k=2…6) | long-rep endurance | late rung |
| **AE4** | Main | `1×(R_k−100) S continuous` + `1×100 E` or `2×(R_k/2) S, r=10` | continuous rehearsal for proof | 5–10 days pre-proof |
| **AE5** | Main | Descending long set: `4×(500→300→200…)` or `5×500 desc 1–3` | pacing discipline; avoids going out hard | endurance day variety |
| **AE6** | Main | **Rest-shrink ladder:** `8×100 S` with r = 20/15/10/5 across 4 exposures | bridge to continuous | before proof |
| **CS1** | Main (Quality) | `8–15×100 C, r=10–15` (or send-off=CSS+10–15 s) | threshold; even splits | 1/wk max |
| **CS2** | Main | `3×200 C + 1×300 C …` ladder to 400 (e.g., 4×100 +200, 4×100 +300, 4×100 +400 at C) | CSS over longer continuous, scales by *cumulative time* | advanced; n≥3 |
| **CS3** | Main | `k×(0.2–0.4·D_goal) at goal pace, r=15–30` | goal-pace rehearsal (P1) | late rung |
| **SP1** | Main (optional) | `8–12×25/50 F, r=20–30` | speed support; **optional**; skip if capacity-only | pace track |
| **TK1** | Technique | `10×50` swim/drill alternate (KOS, catch-up, fist, 6/3/6) E/S, r=10–15 | stroke efficiency; one cue per set | S3 role |
| **TK2** | Technique | `4×(50 pull S + 50 swim S)` or `3×(100 pull + 50 swim)` | breathing rhythm/stroke length; pull-buoy as aid | beginners |
| **RC1** | Recovery | 20–30 min continuous E (any stroke allowed) or `8×100 E` | low-stress aerobic | recovery/n≥4 |
| **TST1** | Test | 400 TT even → 10–15 min E → 200 TT | CSS | week 1 / every ~6 wk |
| **TST2** | Test | 10×100 T-pace (total−rest)/10 | fallback T-pace | capacity-limited |
| **PRF1** | Proof | `1×R_k continuous S` (pass/fail) | capacity milestone | rung boundaries |
| **PRF2** | Proof | `P1/P2/P3` at goal pace | pace milestone | final rungs |
| **CD1** | CD | 100–300 E any stroke (≥200 after proof/test/CSS) | mandatory | CD = clamp(100, 0.07·S_total, 300) |

**Session assembly rules (hard constraints, deterministic):**
- Every session = WU (≥1) + optional PRE/TK + Main (≥1 pattern) + CD1 (R9).
- Max 1 Quality main/session; max 1 CS-type per week for `n≤3`.
- Total distance within ±10% of target; if over: drop optional TK/PRE then trim WU to floor 300.
- Easy-first: put TK before Main; put **PRF1 first after PRE1**.
- Forbid CS/SP the day before proof; require ≥1 E/TK day between Quality and proof for `n≥3`.

### 6.6 Warm-up / cool-down templates (concrete)

- **Standard WU (S_total 1500–2500 m):** `300 E → 4×100 (build 1→4) r15 → (opt.) 6×50 drill/swim r10`. ≈ 700–900 m, which is more than the 15–20% budget for a short session → always apply `WU = clamp(300, 0.15·S, 600)` and drop the optional blocks first.
- **Proof WU (PRF1 days):** `300 E → 4×50 S r20 → 2×25 build` then proof; **CD**: `200–300 E` after.
- **CSS test WU/CD:** WU 400–500 (E/S + 4×50 build); test; CD 200–300 E (Outdoor Swimmer/Swim Smooth test sessions total ~2.1–2.9 km).
- **CD**: 100–300 m E, any stroke, "stretch as needed" (Coach Ray lets the cooldown be any stroke); 5–8 min (swimer.app).

### 6.7 Proof pass/fail and slippage (R15, R22 consistency)

- **Pass (capacity):** completes `R_k` continuous (no wall stop > `rest_gap_s`), free stroke ≥ 90% of distance, **pace within steady band** (not > 5 s/100 faster than `steady_pace`; avoid "heroic fast then fade"), `fade_pct ≤ 8–10%` **[D]**. Option: allow one planned stroke-change "safety valve" flagged as `pass_with_assist` (counts as 0.5 progress).
- **Pass (pace proof):** distance met and mean pace ≤ target pace.
- **Near-pass (≥ 90% of `R_k`, or ≤ 10% fade fail):** **slip 1 week**, repeat rung with `s_next = 0.5·s` or keep `R_k` with rehearsal added.
- **Fail (< 85–90% or panic/stop early):** step back to last proven rung, **block repeats 1–2 weeks**, next rung `s_next = 0.10–0.15`; reflect honestly in forecast (dates move).
- **Delay (illness/travel):** pause clock; if gap > 10 days, re-enter with an easy "re-acclimation" session and **−1 s/100 CSS assumption per missed week** (Swim Smooth guidance: "Miss a week? Assume +1 s/100 CSS slowdown") **[C]**. https://blog.swimsmooth.com/p/understanding-training-zones
- **Single missed chore** shall not move milestone dates (R15); only loss of *exposures needed for a rung* (e.g., missed ≥50% of block sessions) triggers a recompute — consistent with split rules (streak forgiving vs milestone honest).

### 6.8 Ultimate goal-day forecast (derived, range)

`goal_day = max(capacity_complete, pace_complete) + taper_days` where:
- `capacity_complete` = date of final capacity rung `R = D_goal` (proof P-capacity) with rung blocks projected using *recent observed pass history* (fall back to defaults).
- `pace_complete` = now + `Δp / g` weeks, with `g` between **0.3** (pessimistic) and **0.5** (optimistic) s/100/week, plateaued after 8–12 weeks (**[C]**); recompute at each retest/proof using *observed* CSS slope (EWMA).
- `taper_days` 3–5 (light technique; `PRE1` + proof).
- **Show a range (earliest/likely/latest)** with explicit label "forecast"; widen when `confidence = low`.

### 6.9 Rules-pack data structure (provenance-first, deterministic)

```
RulePack v1
├─ meta: {version, authored_by, reviewed_by_coach?, change_log}
├─ formulas: [{id: css_400_200, expr, inputs, source_ids: [S1, S2], grade: A/C}, ...]
├─ zones: [{id: steady, css_offset_s: [6,10], rpe: [4,5], source_ids: [...]}, ...]
├─ patterns: [{id: AE2, role: MAIN, params:{reps:[3,6], dist:300, effort:S, rest:[10,15]},
│              scale: {...}, prerequisites:{min_MCD: 600}, intent_tags:[endurance,rung], source_ids:[...]}, ...]
├─ progression: {rung_step:{default:0.20, min:0.10, max:0.25}, deload:{every:4, factor:0.8}, vol_growth:{max_week:0.10}}
├─ session_rules: {max_quality_per_week:1, proof_pre_taper:0.7, wu_cd_bounds:{...}}
├─ proof_rules: {pass:..., near_pass:..., fail:...}
└─ sources: [{id, url, type, grade, access_date, license_note}]
```

- Store in **repo content files** (JSON/YAML) not code; unit-test the **generator** with golden fixtures: (i) dogfood 1000→1200, (ii) beginner 300→1000, (iii) 2×/wk, (iv) 5×/wk, (v) short horizon, (vi) infeasible time goal.
- Surface "why this session" explanations from the rule IDs (S5: explainable from rules+intake+baseline).

### 6.10 Worked example (dogfood-like)

**Intake:** `D_goal = 1200 m`, `T_goal = 22:00` (110 s/100 m), `H = 4 wk`, `n = 3`. Baseline from history: `MCD ≈ 1000 m`; recent best 400 m = 7:20 (440 s), 200 m = 3:30 (210 s).

- `CSS = (440 − 210)/2 = 115 s/100 m` (1:55). Steady = 1:55 + 8 ≈ **2:03/100**; Easy ≈ 2:07–2:10; Threshold ≈ 1:53–1:57.
- Riegel (b=1.06): `T_pred(1200) = 440 × 3^1.06 ≈ 440 × 3.204 ≈ 1410 s ≈ 23:30` → `p_pred ≈ 117.5 s/100`; `gap_ratio = 1410/1320 = 1.068` → **class C**, `Δp ≈ 7.5 s/100`. At 0.3–0.5 s/100/wk → ~**15–25 weeks** to close the pace gap — **exceeds the 4-week horizon**. Engine copy: *"Capacity goal (1200 m continuous) is realistic within ~2–3 weeks; the 22:00 time needs ~4–6 months at typical rates. Proceed with capacity ladder now; time goal tracked as forecast."*
- **Ladder:** `R_0=1000 → R_1=1200` (+20%), single rung, **proof at ≈ week 2–3**; then a second target (optional): `P-goal` at current `T_pred`.
- **Weeks (n=3):** W1: S1 AE3 (3×400 S r20) + S2 CS1 (10×100 C r15) + S3 TK1+AE1; W2: S1 AE6 (rest-shrink) + S2 CS3/AE4 (2×(600) S r10) + S3 RC/TK; W2/3 end: proof PRF1 `1200 S continuous`, CD 300. Weekly volume +8% w1→w2, **no deload before proof** (3-week block), then optional deload.
- **Pass:** 1200 continuous at ≈ steady pace (2:03 ±5 s) with `fade ≤ 8%`. **Next rung** (if pass): `s=0.15–0.20` → `1400` or pivot to pace track (P1: 3×400 @ goal-ish pace), CSS retest.

---

## 7. Risks, open questions, and calibration plan

| Risk / open question | Mitigation / next step |
|---|---|
| **CSS 400/200 at a novice's pacing skill** is noisy; sandbagging → too-fast CSS | Use pace bands; require `CSS_test` plausibility (400 pace slower than 200 by ≥ 4–6%; 200–400 delta sanity); fall back to T-pace/capacity mode; re-test earlier on outliers. |
| **Rung size (+15–25%) and sessions per rung (6–8)** are **synthesized heuristics**, not published | Dogfood: log rung outcomes; adjust `s` and block length; add coach review. |
| **History-derived MCD** may be misdetected (turn/rest inference, GT5 length detection) | Reuse Fathom canonical swim session computations (Swim Bible / invent-guard); only use sessions that pass coverage guards; show confidence. |
| **Pace-gain rates (0.3–0.5 s/100/wk)** come from one vendor's guidance; beginners may gain faster/slower | Treat as *planning bounds*; replace with observed slope after 2 tests. |
| **Wrist HR in water** unreliable | Pace+RPE only (§2.8). |
| **Mixed strokes in "continuous" proofs** | Define stroke-mix policy (e.g., ≥90% free for `pass`; `pass_with_assist` otherwise). |
| **Pool-length differences (SC/LC)** | Tag; compare within same pool; convert with explicit uncertainty (calculator blog ~2–3% SC→LC) **[C]**. |
| **Brand/trademark and content hygiene** | Rename sets; no verbatim vendor text; provenance registry; light legal review. |
| **Strava/AI policy drift** | Keep Programs engine free of Strava data; legal check before any Coach integration. |
| **No licensed coach review yet** | Budget a one-time coach pass on the rules pack and ~20 patterns. |
| **Thresholds deferred in requirements** (R7, proof matching, vocabulary size) | This doc proposes defaults in §6.2, 6.5, 6.7; finalize in planning. |

**Calibration instrumentation to add early:** `proof_result`, `planned vs actual pace`, `fade_pct`, `stroke_drift`, `sRPE`, `sessions_between_proofs`, `CSS_test` history.

---

## 8. Source list (grouped; URLs)

**Physiology / literature [A]**
- Wakayoshi et al. 1992 abstract — https://europepmc.org/article/MED/1521952
- Wakayoshi et al. (critical velocity validity) mirror — https://d.docksci.com/download/determination-and-validity-of-critical-velocity-as-an-index-of-swimming-performa_5ec52686097c47ac058b458c.html
- Dekerle et al. 2005 (CSS ≠ MLSS) — https://pubmed.ncbi.nlm.nih.gov/16195984/ ; https://www.thieme-connect.de/products/ejournals/abstract/10.1055/s-2004-821227
- CS reliability/validity (200/400, all strokes) — https://exa.ai/library/publication/55zjnt00rx0 ; https://exa.ai/library/publication/dnbs2f15jph
- Karsten et al. 2022 (updated CV methodology) — https://gala.gre.ac.uk/id/eprint/50514/3/50514%20KARSTEN_An_Updated_Methodology_To_Estimate_Critical_Velocity_In_Front_Crawl_%28AAM%29_2022.pdf
- Swimmer TID/periodization systematic review — https://journals.humankinetics.com/view/journals/ijspp/16/7/article-p913.xml
- Polarized vs other TID meta-analysis — https://pmc.ncbi.nlm.nih.gov/articles/PMC11329428/
- Polarized vs pyramidal in swimmers (summary article) — https://www.mlsjournals.com/Sport-Research/article/download/2597/1343
- sRPE in swimming — https://opus.lib.uts.edu.au/handle/10453/9495 ; https://journals.humankinetics.com/view/journals/ijspp/10/7/article-p848.xml
- Wrist/temple/chest HR in water — https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0231522 ; https://www.mdpi.com/2076-3417/15/11/5848 ; https://pmc.ncbi.nlm.nih.gov/articles/PMC12965795/ ; https://www.nature.com/articles/s41597-026-08084-4

**Coach texts / national-body [B]**
- Maglischo endurance-training summary — http://kinisiologia.phed.uoa.gr/fileadmin/kinisiologia.phed.uoa.gr/uploads/01vol2no1.pdf ; fast-twitch recruitment — https://rowperfect.co.uk/wp-content/uploads/2012/01/Training-fast-twitch-fibers.pdf ; book — https://books.google.com/books/about/Swimming_Fastest.html?id=cSSW4RhZOiwC
- Sweetenham & Atkinson / British Swimming zones — https://www.southeastswimming.org/wp-content/uploads/2020/05/Physiological-Training-Models-P1.pdf ; https://zwemfed.be/sites/default/files/2023_symposium_fv_bel.pdf ; https://www.rundna.com.au/p/championship-swim-training-by-bill-sweetenham-john-atkinson
- SDSU Swimming Science Bulletin (T-30 vs EN-1) — https://coachsci.sdsu.edu/swim/bullets/icar8990/icar17.htm
- HY-TEK T-30 module — https://hytek.active.com/User_Guides_HTML/SwTM7/HTML/t_30.htm
- USMS volume progression — https://www.usms.org/fitness-and-training/articles-and-videos/articles/simple-ways-to-add-volume-productively-to-your-swimming-workouts
- Swim Smooth — https://blog.swimsmooth.com/p/get-your-pace-right ; https://blog.swimsmooth.com/p/understanding-training-zones ; https://blog.swimsmooth.com/p/red-mist-vs-css-training-why-both ; https://blog.swimsmooth.com/p/challenge-yourself-with-our-2024 ; podcast https://scientifictriathlon.com/tts132/

**Coaching blogs / calculators / vendor docs [C]**
- CSS guides: https://swimtune.com/guides/css-critical-swim-speed ; https://www.swimio.app/guides/critical-swim-speed-test ; https://learnswimfast.com/tools/css-calculator ; https://www.trainingzones.io/en/guides/critical-swim-speed ; https://outpaceswimming.co.nz/wp-content/uploads/2021/09/Understanding-Critical-Swim-Speed.pdf ; https://envolcoaching.net/2023/10/13/css-swimming/ ; https://outdoorswimmer.com/coach/how-tos/testing-times-2/ ; https://outdoorswimmer.com/coach/how-do-i-stop-myself-swimming-too-fast/ ; https://www.midsussextriclub.com/training-zone/training-articles/what-is-critical-swim-speed-and-how-to-use-it/ ; https://triathlonpace.com/articles/estimate-your-critical-swim-speed-using-garmin-or-race-results
- Race-time prediction: https://swimmingregimen.com/tools/time-predictor ; https://calculatrex.com/swimming-race-time-predictor ; https://www.trainingzones.io/en/swim-predictor
- Sets/structure: https://swimer.app/en/swimming-workout-structure ; https://www.coachray.nz/2016/09/10/saturday-swim-session-build-400s-2/ ; https://www.coachray.nz/2017/05/27/saturday-swim-session-400s/ ; https://rockstartriathlete.com/how-to-structure-your-own-swim-workout/ ; https://breakingmuscle.com/a-beginner-s-guide-to-structuring-your-swim-workout/ ; https://thetriathlete.co.uk/sessions/css-main-set-12x100m-pool-session/ ; https://www.aquaplan.fit/blog/train-for-a-fast-1500m-freestyle ; https://www.aquaplan.fit/blog/recovery-swim-workout ; https://tritheos.com/setup-your-triathlon-swim-training-for-massive-swimming-improvements/ ; https://swimgym.com/fast-lane/how-to-improve-your-endurance
- Volume/frequency: https://thirdcoasttraining.com/how-to-build-swimming-endurance-guide-for-triathletes/ ; https://oliletriathlete.com/swim-endurance-training-distance-burnout/ ; https://www.triathlete.com/training/how-to-successfully-execute-a-swim-focused-block/ ; https://swimtune.com/guides/swim-training-load-recovery ; https://padlie.com/en/blog/beginner-adult-swimming-sessions-12-weeks ; https://chrisyau.me/en/blog/building-swimming-endurance
- Beginner plans: https://ruthkazez.com/swimming/ZeroTo1mile.html ; https://www.fitdrills.com/swim-1500-m-for-beginners/
- Garmin manuals: https://www8.garmin.com/manuals/webhelp/GUID-2492EDA1-1182-400B-8F43-D8B3211E4F3C/EN-US/GUID-F9FFE0BF-ED46-40D4-A562-92F1CB4C3650.html ; https://www8.garmin.com/manuals/webhelp/GUID-0221611A-992D-495E-8DED-1DD448F7A066/EN-US/GUID-92B2952D-C8D5-4F66-9FBF-5A00549F0390.html

**Products / platforms**
- MySwimPro — https://support.myswimpro.com/en/articles/9741919-new-improved-personalized-swim-training-plans-more-personalized-than-ever ; https://support.myswimpro.com/en/articles/6350436-getting-started-with-myswimpro ; https://support.myswimpro.com/en/articles/6350457-setting-up-personalized-intervals ; https://support.myswimpro.com/en/articles/6809628-test-sets ; https://blog.myswimpro.com/2017/08/13/what-are-swimming-training-zones/ ; https://blog.myswimpro.com/2025/08/12/how-to-structure-the-perfect-swim-workout-and-stop-swimming-mindlessly/ ; https://myswimpro.com/terms-of-use/
- Garmin Coach — https://www.garmin.com/en-US/blog/fitness/five-ways-to-use-garmin-coach-on-your-watch/ ; https://www.garmin.com/en-US/blog/fitness/which-adaptive-training-plan-is-right-for-you/ ; https://garminrumors.com/garmin-adds-triathlon-coach-to-adaptive-training-lineup-here-are-the-details/ ; Developer: https://developer.garmin.com/gc-developer-program/training-api/ ; https://developer.garmin.com/gc-developer-program/program-faq/
- FORM — https://www.formswim.com/blogs/all/personalized-training-with-headcoach-plans ; https://support.formswim.com/hc/en-us/articles/42290261828499-What-are-HeadCoach-Plans ; https://www.formswim.com/pages/premium ; https://www.formswim.com/blogs/media/form-introduces-headcoach%E2%84%A2-2-0-expert-coaching-tailored-to-your-goals ; https://www.wired.com/review/form-smart-swim-2-lt-goggles/
- TrainingPeaks plans — https://www.trainingpeaks.com/training-plans/triathlon/olympic/tp-284491/1500m-open-water-swim-programme-8wk ; https://www.trainingpeaks.com/training-plans/other/swimming/tp-179731/1500-metre-front-crawl-open-water-swim-12-week-plan ; https://www.trainingpeaks.com/training-plans/other/swimming/tp-111948/open-water-swim-1500m-triathlon-race-plan-10-weeks ; https://www.trainingpeaks.com/training-plans/triathlon/ironman/tp-117016/open-water-swim-3-8km-race-plan-12-weeks ; https://www.trainingpeaks.com/training-plans/other/swimming/tp-656725/1500m-focus-beginner-16-weeks ; https://www.trainingpeaks.com/training-plans/other/swimming/tp-656776/1500m-focus-beginner-12-weeks ; https://www.trainingpeaks.com/training-plans/other/swimming/tp-656782/1500m-focus-beginner-8-weeks

**Data / licensing**
- USA Swimming — https://www.usaswimming.org/times ; https://websiteprodcoresa.blob.core.windows.net/sitefinity/docs/default-source/timesdocuments/general-docs/times-policy-manual-2022-0414.pdf ; https://devswimsthirdpartydocs.usaswimming.org/ ; https://websitedevsa.blob.core.windows.net/sitefinity/docs/default-source/technology/api-access-program-application.pdf?sfvrsn=c75c1932_1
- NCAA memo — https://ncaaorg.s3.amazonaws.com/championships/sports/swimdive/d1/2025-26D1XSW_MEMOPreSeasonInfo.pdf
- SwimCloud — https://www.swimcloud.com/terms/ ; https://support.swimcloud.com/hc/en-us/articles/7159725331347-Submitting-Meet-Results ; https://support.swimcloud.com/hc/en-us/articles/115007665388-Managing-Your-Times-FAQ ; https://github.com/maflancer/SwimScraper
- World Aquatics — https://www.worldaquatics.com/legal ; https://data.worldaquatics.com/TermsAndConditions/TermsAndConditions.htm ; DSG — https://dsg-api.com/doc/swimming/get_results/485/
- Strava — https://cdn-1.strava.com/legal/api_policy ; https://communityhub.strava.com/developers-api-7/is-my-app-compliant-13485 ; https://support.strava.com/en-us/articles/15401526-strava-api-and-mcp-faq
- USMS — https://www.usms.org/workout-library ; https://www.usms.org/fitness-and-training/articles-and-videos/articles/us-masters-swimming-launches-exclusive-workout-library-for-members ; https://www.usms.org/coach-central/online-coaching-program ; https://community.usms.org/swimming/f/workouts/19665/new-free-workouts-database-online
- Open datasets/directories — https://huggingface.co/datasets/t22000t/swimming-resources ; https://github.com/timothy22000/swimming-resources ; https://github.com/brunnergino/swimming-recognition-lap-counting ; https://www.kaggle.com/datasets/ruslanbredun/swimming-styles-imu-data ; https://www.kaggle.com/datasets/commcollabs/multimodal-wearable-swimming-technique-dataset ; https://rdrr.io/cran/youngSwimmers/f/README.md ; Barry et al. Zenodo-linked study pages — https://pure.ul.ie/en/publications/the-design-and-evaluation-of-an-integrated-training-load-and-inju/ ; https://www.mdpi.com/2076-3417/14/22/10411 ; SWOLF normalization threads — https://forum.intervals.icu/t/swimming-statistics-swolf-strokes-length-stroke-distance/11387

**Community (via search snippets; verify in-browser)**
- r/Swimming — https://www.reddit.com/r/Swimming/comments/1r05pfb/adult_swimmer_how_did_you_build_up_to_a_mile/ ; https://www.reddit.com/r/Swimming/comments/1j2icwn/for_a_decent_swimmer_how_long_would_it_take_to/ ; https://www.reddit.com/r/Swimming/comments/1v1cujf/couch_to_1k_doable_in_14_weeks/ ; https://www.reddit.com/r/Swimming/comments/1vawbmq/how_to_get_better_at_swimming_laps/ ; https://www.reddit.com/r/Swimming/comments/1uovst1/what_actually_helped_you_learn_to_swim_as_an/ ; Swimmit history — https://www.reddit.com/r/Swimming/comments/ef0ea/we_finally_have_a_lane_available_after_being/
- r/triathlon — https://www.reddit.com/r/triathlon/comments/1je1oz2/do_you_swim_the_full_distance_in_training_without/ ; https://www.reddit.com/r/triathlon/comments/1djf62x/swimming_pace_has_plateaued_at_what_point_do_i/ ; https://www.reddit.com/r/triathlon/comments/1uts1xa/swim_advice/ ; https://www.reddit.com/r/triathlon/comments/1vtf3j4/really_struggling_with_swimming_looking_for_any/ ; https://www.reddit.com/r/triathlon/comments/1td2l7n/first_sprint_tri_in_45_days_can_only_swim_5075m/ ; https://www.reddit.com/r/triathlon/comments/1u36dvx/firsttimer_tips/
- Slowtwitch — https://forum.slowtwitch.com/t/swim-plateau-1/687781

---

## Appendix A — Formulas (copy-paste for engine spec)

```
CSS_pace_per_100(T400, T200)     = (T400 - T200) / 2                     # seconds
CSS_speed_mps(Dl, Ds, Tl, Ts)    = (Dl - Ds) / (Tl - Ts)                 # generalized
pace_per_100(speed_mps)          = 100 / speed_mps
T_pred(D2; T1, D1, b)            = T1 * (D2 / D1) ** b                   # b default 1.06 ; clamp [1.03, 1.12]
b_personal(T1, D1, T2, D2)       = ln(T2/T1) / ln(D2/D1)
zone_pace(zone)                  = CSS_pace + offset_range[zone]         # see §2.3
rung_next(R, s)                  = round_to_multiple(R * (1 + s), 50)
steady_pace                      = CSS_pace + 8                          # range +6..+10
SWOLF_25(len_time_s, strokes, pool_len_m) = (len_time_s + strokes) * (25 / pool_len_m)   # normalization approach, see Intervals.icu thread
sRPE_load                        = RPE_1_10 * duration_min
```

## Appendix B — Quick checklist of "what to say honestly in copy"
- "Pace goals move in months; distance goals move in weeks."
- "CSS is a planning anchor, re-test every ~6 weeks."
- "Wrist heart rate isn't reliable in the water; Programs uses pace and effort."
- "We built these sessions from published training principles and your own swim history; no third-party workout library."
- "If you miss a proof, we move the next date, not your streak."

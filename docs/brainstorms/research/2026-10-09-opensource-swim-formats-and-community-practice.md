---
date: 2026-10-09
topic: opensource-swim-formats-and-community-practice
status: research-complete
type: research
feeds:
  - docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md
  - docs/brainstorms/research/2026-10-09-swim-data-sources-four-questions.md
  - docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md
  - docs/plans/2026-10-09-002-feat-pool-swim-programs-plan.md  # U3 Rules Pack
author: best-practices-researcher subagent
---

# Open-source swim formats + community practice — deep rabbit hole for Fathom Agon v1

> Deep notes on five user-cited sources plus community practice (search-index when Reddit blocked). Distinguishes **ingest / distill / ignore**. Not legal advice — verify licenses before shipping third-party files. **Do not copy copyrighted workout text verbatim**; patterns below are Fathom-authored meters shapes.

---

## 0. Executive — adopt THIS week vs later

### THIS week (Agon v1 / plan U3)

| Adopt | Why |
|---|---|
| **OSW-inspired Agon prescription subset** | Sections (WU / Main / CD), `reps×distance`, stroke/activity, effort level+shape, interval `rest` **or** single-athlete send-off, course `{length, unit}`. Enough for phone-planned chores; skip multi-lane speed groups for v1. |
| **Fathom-owned Rules Pack patterns (§6)** | 12 original meter shapes distilled from community + MSNSW/Swim Smooth *shapes*; provenance-tagged grade C/B. |
| **CSS 400/200 as primary test**; T-30 / 10×100 as fallbacks | Community + Slowtwitch + Swim Smooth consensus; matches algorithms doc. |
| **Session roles @ 2–4×/week** | Endurance + Quality (+ Technique when n≥3); ≤1 threshold main/week for distance goals. |
| **Wrist HR = soft/secondary only** | Swim Smooth + optical-HR literature; never zone driver. |
| **OpenSwim architecture lessons** | Serializable workout model, flatten to instruction stream, pool-length divisibility gate, restore in-progress session — **not** as content feed. |

### Later (post-v1 / Q4 R&D)

| Defer | Why |
|---|---|
| Full OSW multi-group sparse send-offs, nested brace repeats, OCR/SwimText import | Coach whiteboard fidelity; overkill for single-athlete Agon v1. |
| SwimWorkoutKit Swift package as dependency | Fathom is Flutter/Kotlin; **port schema ideas**, don't bind Swift. |
| Zhuang PMC6891622 CNN + periodic matching on GT5 | Needs raw 50 Hz IMU stream Fathom does not yet expose; small private-ish dataset; **algorithm ideas only**. |
| SwimBIT trunk elevation / body balance / rotation | Lower-back AHRS; GT5 is wrist — indicators don't transfer directly. Steal **pitch for turn/rest**, **roll for stroke peaks**, energy features for stroke class **if** motion streams appear. |
| swimming-resources as RAG corpus | Useful link index (CC BY 4.0 **for the index**); linked sites remain their own licenses — not a workout library. |
| Commercial plan bodies (MySwimPro, Swim Smooth GURU, USMS Workout Library) | Distill shapes only; no ingest. |

### Honesty one-liner

**Build Rules Pack + thin Agon schema this week. Ingest OpenSwim MIT model *patterns* and OSW *schema fields*. Distill community/CSS/MSNSW shapes. Ignore commercial libraries, World Aquatics scrapes, and papers whose sensors aren't GT5 wrist.**

---

## 1. Open Swim Workout / SwimText

**URLs:** https://www.openswimworkout.com/ · Spec/schema/reference: https://github.com/rickybloomfield/SwimWorkoutKit (MIT) · Schema: https://raw.githubusercontent.com/rickybloomfield/SwimWorkoutKit/main/Spec/schema/open-swim-workout.schema.json · Spec: https://raw.githubusercontent.com/rickybloomfield/SwimWorkoutKit/main/Spec/SPEC.md

### What it is

Open, JSON interchange for **prescribed** workouts (coach whiteboard), not recorded activities. Canonical encoding `.swimworkout` (`format: "open-swim-workout"`, `version: "0.2"`). Human companion **SwimText** round-trips for the canonical subset. Reference impl: Swift `SwimWorkoutKit` + optional UI highlighter; CLIs `swimtext` / `swimocr` / `swimclaude`.

### Schema capabilities Fathom needs

| Capability | OSW support | Agon v1 need |
|---|---|---|
| **Course** | `{ length: 25\|50, unit: "m"\|"yd" }` SCY/SCM/LCM | **Yes** — GT5 pool length + meter programs |
| **Sections + statedDistance** | Warmup / Main / Cool Down with checksum totals | **Yes** — chore structure R9 |
| **Sets** | `reps × distance`, stroke, activity (orthogonal), equipment, effort, interval | **Yes** — core |
| **Effort** | `level` (easy…race) + `shape` (steady/build/descend/…) + `%` | **Yes** — map to CSS offsets + RPE |
| **Intervals** | `sendoff` (per-group map) · `rest` · `open` | **Partial** — single send-off or rest; defer multi-lane maps |
| **Nested repeats** | Brace `repeat` with `rounds` / `roundsPerGroup` | **Later** — flatten for watch display |
| **Segments / perRep** | Intra-rep kick/drill/swim; odd/even variants | **Nice** — technique sets |
| **Speed groups** | Ordered A→C sparse send-offs | **No for v1** — one athlete |
| **sourceText / note** | Verbatim at every level | **Yes** — LLM/OCR later; provenance now |
| **Interop** | Lossy → Garmin FIT / Apple WorkoutKit | **Later** — phone Agon first |

### Compare to Agon v1

Agon v1 needs: **one athlete**, meter pool (yards convert at boundary), WU/Main/CD, parameterized `reps×dist @ effort + rest`, CSS-relative pace targets, pool-length divisibility, estimated duration for feasibility. OSW is a **superset** aimed at masters coaches with 3–4 lanes.

**Recommendation:** Define `AgonWorkout` as an OSW-compatible **profile** (subset): ignore `groups` or force one group; prefer `interval.mode: rest` for beginners and `sendoff` only when CSS send-off is known; flatten nested repeats at plan-time into linear steps for watch/phone UI. Do **not** depend on SwimWorkoutKit (Swift); re-implement types in Dart from the MIT schema.

**License / ingest:** Spec + schema + SwimWorkoutKit = **MIT** → schema ingest OK. Example workouts in Spec are for format illustration — treat as **format fixtures**, not Fathom program content.

**Verdict:** **ingest schema ideas** · **ignore** as workout content corpus.

---

## 2. timothy22000/swimming-resources

**URL:** https://github.com/timothy22000/swimming-resources · HF: https://huggingface.co/datasets/t22000t/swimming-resources

### Structure (410 entries / 20 categories)

Machine-readable index (JSON / JSONL / CSV / Parquet) + Python source modules `scripts/data_part*.py`. Fields: `id`, `category`, `subcategory`, `name`, `type`, `audience`, `description`, `url`, `pricing`, `region`, `language`, `year_founded`, `status`, `notes`, `tags`, `verified`.

| # | Category | n | Q1–Q4 help |
|---|---|---|---|
| 1 | Governing bodies | 41 | Weak Q1 (records only) |
| 2 | Learn-to-swim | 25 | Capacity beginners (Q1/Q3) |
| 3 | Technique | 14 | Q2/Q3 distill |
| 4 | YouTube | 26 | Q2 soft |
| 5 | **Training plans & workout repos** | **19** | **Q3 primary** |
| 6 | Apps & tech | 19 | Format/competitors — mostly ignore as feed |
| 7 | Books | 34 | Maglischo etc. — distill |
| 8 | Certifications | 23 | Low |
| 9 | **Sports science** | **19** | **Q2/Q4 papers portals** |
| 10–12 | News / podcasts / gear | — | Low |
| 13–14 | Open water / triathlon | 20+15 | Q3 triathlon CSS culture |
| 15 | **Masters** | **16** | **Q3 adult progress** |
| 16–17 | Para / drowning | — | Out of Agon v1 |
| 18 | Records/rankings | 32 | Weak Q1 benchmarks only |
| 19–20 | College / recruiting | — | Ignore |

### License claim

- **Database content (`data/`):** Creative Commons Attribution 4.0 (**CC BY 4.0**) — share/adapt including commercial **with attribution**.
- **Build scripts:** MIT (`LICENSE-CODE`).
- Citation requested in README (Timothy Sum, 2026, v1.0.0).

**Critical honesty:** CC BY covers the **index** (names, URLs, descriptions). It does **not** re-license the linked workout libraries (USMS, MySwimPro, Swim Smooth GURU, etc.).

### High-value links followed (no paywalled scrape)

| Link | Pricing | Fathom action |
|---|---|---|
| Swim Smooth zones blog — https://blog.swimsmooth.com/p/understanding-training-zones | Public article | **distill** CSS week structure, HR critique, 0.3–0.5 s/100/wk |
| MSNSW Tempo / CSS — https://mastersswimmingnsw.org.au/coaches-and-officials/coaching/coaching-tips/tempo-trainers/ | Free tips | **distill** CSS + tempo-trainer pacing |
| MSNSW Training Programs hub — https://mastersswimmingnsw.org.au/coaches-and-officials/coaching/training-programs/ | Free PDFs | **distill shapes** (aerobic vs sprint, Level 1–3); do not ship PDFs |
| MSNSW Training Sets for Racing PDF | Free | **distill** FES/BES/CSS formulas; CSS = (T400−T200)/4 → 50 m pace |
| 220 Triathlon swim hub — https://www.220triathlon.com/training/swim-training | Free articles | **distill** benchmarks/drills ideas; skip race-day OW noise |
| SwimSwam Workouts category | Free posts | Spot-check shapes only; copyrighted posts |
| GoSwim / Effortless / YourSwimLog | mixed | Technique cues → Q2 later |
| USMS Workout Library / MySwimPro / TrainingPeaks | paid/freemium | **ignore** as feed; already covered elsewhere |
| Rushall Swimming Science Bulletin — https://coachsci.sdsu.edu/swim/bullets/table.htm | Free | Optional Q2/Q4 deep reading |
| PubMed / Journal of Swimming Research | free portals | Discovery only |

**Verdict:** **ingest index optionally** (attribution) for research RAG · **distill** free plan/CSS/masters tips · **ignore** paid libraries behind the links.

---

## 3. Danielbunckenburg/openswim

**URL:** https://github.com/Danielbunckenburg/openswim · Site: https://danielbunckenburg.github.io/openswim/ · **MIT** (Copyright 2026 OpenSwim contributors)

### How workouts are modeled

Kotlin `kotlinx.serialization` types in `core/`:

```
Workout { id, name, type, estimatedMinutes, sections[] }
  └── WorkoutSection { name, sets: RepetitionSet[] }
        └── RepetitionSet { repetitions, step: WorkoutStep }
              └── WorkoutStep { distance, stroke, intensity, equipment,
                                restAfter, targetPace?, targetInterval?, note? }
```

Enums: `Stroke` (incl. KICK, DRILL, CHOICE), `Intensity` {EASY, MODERATE, STRONG, SPRINT}, `Equipment`. Helpers: `instructions()` flattens to a linear stream of (section, set, rep); `supportsPoolLength(length)` requires every step distance divisible by pool length. Session state machine restores in-progress guided workout after restart. Watch does **not** auto-count laps — athlete taps **Rep done** / **Log length**.

### The 12 offline workouts (meters, original)

| id | Name | Category | ~min | Shape (summary) |
|---|---|---|---|---|
| easy-reset | Easy Reset | Easy | 24 | 200 choice · 4×100 free E r20 · 4×50 back E r15 · 200 |
| easy-mixed | Easy Mix | Easy | 28 | 200 free · 4×50 kick · 4×100 choice · 200 back |
| technique-catch | Find Your Catch | Technique | 30 | drills + 4×75 free focus + kick |
| technique-balance | Body Balance | Technique | 32 | 6×50 side-kick drill · 4×100 free line |
| aerobic-rhythm | Steady Rhythm | Aerobic | 35 | 6×100 free · 4×50 kick |
| aerobic-pull | Pull & Breathe | Aerobic | 40 | 4×200 pull buoy · 4×50 back |
| endurance-long | Long Water | Endurance | 48 | 3×400 free · 4×100 strong |
| endurance-ladder | Distance Ladder | Endurance | 55 | 200–300–400–300–200 pyramid |
| threshold-build | Tempo Builder | Threshold | 42 | 5×200 strong even |
| threshold-hold | Hold the Line | Threshold | 38 | 3×300 strong · 4×100 strong |
| sprint-finish | Fast Finish | Sprint | 25 | 8×25 sprint · 4×50 strong |
| sprint-kick | Kick & Go | Sprint | 27 | kick + 8×25 sprint |

Categories map cleanly onto Fathom session roles: Easy/Aerobic → Steady; Technique → TK; Endurance → AE; Threshold → CS; Sprint → optional SP.

### MIT reuse notes

May copy/modify/merge model code and **these original workouts** under MIT with copyright notice. Still: Fathom should **author its own** parameterized Rules Pack (CSS-anchored) rather than ship OpenSwim names/copy as product content — reuse as **architecture + shape inspiration**. Do not confuse with commercial open-swim.com (different product, personal-use ToS).

### Architecture lessons for watch / offline Agon

1. **Shared serializable core** independent of UI framework — Fathom: Dart domain models in `rules_pack/`.
2. **Flatten for execution** — planner emits linear steps; watch/phone never evaluate nested trees mid-lap.
3. **Pool-length gate** — refuse plans that don't divide by 25/50 m.
4. **Manual progression OK for v1** — GT5 auto-lap is separate; chore matching can use session totals until guided-rep UX exists.
5. **Restore in-progress** — persist chore cursor if guided mode ships.
6. **Meters-first** — OpenSwim omits yards; Fathom should author meters and convert SCY at boundary.
7. **History optional** — OpenSwim skips completed history; Fathom **must** keep chore/proof ledger (gamification).

**Verdict:** **ingest** model patterns + MIT lessons · **distill** the 12 category shapes into Rules Pack · **ignore** as scientific validation.

---

## 4. PMC6891622 — Smartwatch sport HADR (Zhuang & Xue, Sensors 2019)

**URL:** https://pmc.ncbi.nlm.nih.gov/articles/PMC6891622/

### Methods / n / sensors

- Device: **Pacewear** smartwatch, **50 Hz** triaxial accel + gyro (6-D).
- Two custom datasets (not PAMAP2/DSA — those lack motion-state duration labels):
  - **Badminton (NP_CMS):** n=12 (8M/4F), ~5 min each + video, annotated serve/swing intervals; 10 s fragments.
  - **Swimming (WP_CMS):** n=16, 25 m pool, 3–4 lengths × **four strokes**, samples stored per stroke (no per-cycle time labels — only stroke counts).
- Preprocess: per-axis normalize, Gaussian smooth; tile 6-D into “virtual image” for CNN (+ zero-pad between accel/gyro for badminton).

### Algorithms (steal ideas)

| Idea | Detail | GT5 relevance |
|---|---|---|
| Fixed sliding windows fail on weak-periodic swim | Variable cycle length → windows mix strokes / partial cycles | High if raw IMU available |
| **Classification-based periodic matching** | Autocorrelation peaks across 6 channels → vote (±10 samples) → single-cycle crop; classifier confirms; advance by period or by `z` | **Steal for stroke segmentation** |
| Interval-based detection (Faster R-CNN-like) | Candidate anchors + cls/reg for non-periodic sports | Lower priority for continuous freestyle |
| CNN vs classic ML | With periodic matching: CNN ~97.9%, SVM ~98.0%; without matching ~4 pp worse | Prefer light SVM/energy features on-watch if ever |

### Accuracy (swim)

With periodic matching, stroke recognition accuracy ≈ **96–98%** across CNN/SVM/RF/KNN/NB on their held-out 4 athletes. Authors warn: small n; results may drop on larger data; not yet deployed real-time on watch (CNN 37 ms / 10 s on desktop CPU).

### Data availability

**No public download** found. Acknowledgement: Pacewear Technology Ltd. database convenience — treat as **private / not redistributable**. Code not linked as open source in the paper.

### Fathom GT5 relevance

- **Q4 inform only.** GT5 companion path today: totals + laps (+ fragile HR). Without continuous IMU at ≥25–50 Hz, cannot reproduce.
- Prefer **Brunner ISWC 2019** (already in sibling research) if wrist IMU eval appears — closer problem statement.
- Steal: **don't train stroke classifiers on fixed windows**; segment cycles first (autocorr / peak on roll) then classify.

**Verdict:** **distill algorithm ideas** · **ignore** as dataset · **out of Agon v1 critical path**.

---

## 5. PMC6915422 — SwimBIT (Félix et al., Sports 2019)

**URL:** https://pmc.ncbi.nlm.nih.gov/articles/PMC6915422/ · MDPI: https://www.mdpi.com/2075-4663/7/11/238

### Methods / n / sensors

- **AHRS** IMU (accel + gyro + mag) → Euler/heading; log **100 Hz** CSV to SD (WiFi unusable in water).
- Placement: **lower back** in sealed bag (~55 g) — athletes preferred vs wrist/head.
- n=**13** triathletes (11M/2F), age 20.8±3.5; mostly 100 m × 4 strokes in **25 m** pool → **202 laps** (48 fly, 50 back, 50 breast, 54 free).
- Firmware logging board open: https://github.com/PIA-Group/firmware-bitalino-riot-openlog — **not** the analysis code/dataset.

### Signals & algorithms to steal for rhythm / segmentation

| Indicator / step | Method | Steal for wrist? |
|---|---|---|
| **Lap / turn / stop** | Pitch ≈ ±20° while swimming; turn → pitch → ±90°; stop if max–min ≥3 s | **Yes if pitch available** — wall events |
| **Backstroke** | Accel z ≈ −1 g | Orientation feature |
| **Stroke class (other 3)** | Channel **energy** after 0.5 Hz LPF → SVM/ANN | **~90%** on their set |
| **Stroke count (asym)** | Roll sinusoid peaks, 3 Hz LPF, min rotation 20° | **Wrist roll may proxy** arm stroke — different placement |
| **Stroke count (sym)** | Pitch mins + DTW vs mean wave | Breast/fly — wrist weaker |
| **Trunk elevation / balance / rotation** | Pitch/roll ranges per style | **Lower-back specific** — don't claim from GT5 wrist |

Reported: **100%** lap segmentation; backstroke **100%**; fly/breast/free **~89.6%** ANN; stroke-count accuracy ~91–97% by style.

### Data / code availability

- **Raw CSV dataset:** not published (no Zenodo/GitHub dataset found 2026-10-09).
- **Analysis algorithms:** described in paper; no official open analysis repo.
- **Firmware only** is open.

### Fathom relevance

- **Q4 inform:** pitch-based turn/rest, energy-based stroke class, roll peak stroke rate — re-derive on wrist with Brunner/GT5 streams later.
- **Not** a Programs Rules Pack input.
- Novel indicators (trunk elevation etc.) are coaching gold **on trunk IMUs** — out of scope for wrist Agon.

**Verdict:** **distill** segmentation heuristics · **ignore** dataset · **ignore** for Agon prescription schema.

---

## 6. Community practice → engine rules (evidence grade **C**)

Sources: search-index snippets from r/Swimming & r/triathlon (direct reddit.com fetches blocked); Slowtwitch CSS threads; Swim Smooth public blog; MSNSW free coaching tips; EntrenAI/USMS public plan blurbs. Verify quotes in-browser before product copy.

| Community finding | Engine rule (Agon / Rules Pack) | Grade |
|---|---|---|
| After 0→1650, sticky week = Mon intervals (e.g. 8×200 rest-shrink) + Wed tech/power + Fri long endurance cycling 3×500 → 2×750 → 1000+500 → 1500 test | Session roles: Quality / Technique / Endurance; endurance main cycles long-rep ladders toward proof | C |
| Capacity 500→mile often **4–8 weeks** at 2–3×/wk; many need **2–3 months**; technique often the bottleneck | Separate capacity vs pace tracks; feasibility warning if horizon too short for pace | C |
| Beginners regret: all-out every day; jumping distance too fast; ignoring technique → shoulder pain | Cap ≤1 threshold main/week; weekly volume +5–10%; TK role when n≥3 | C |
| What worked: rest-shrink on fixed pace; lengthen reps; continuous ladder; lessons for breathing | AE rest-shrink + continuous rehearsal patterns; optional technique chores | C |
| 2×/wk: still progress if Endurance + Quality; 3× preferred; 4–5 add easy only | `n=2` → Endurance+Quality; `n=3` add TK/Aerobic; `n=4–5` add Easy | C |
| Trusted tests: **CSS 400 then 200** (rested, all-out); T-30 / 1000 TT; **10–20×100** hold as CSS validity check | TST1 = CSS; TST2 = 10×100; T-30 optional | C |
| Slowtwitch: CSS is decay-rate sensitive; sandbagging 400 or crushing only 200 skews result; CSS 100s easier than CSS 400s | Label CSS confidence; allow coach offset −2…+4 s/100 on long reps; prefer ranges | C |
| Swim Smooth: HR unreliable in pool; zones from CSS; miss week ≈ +1 s/100 | **Never** drive intensity from wrist HR; miss-week CSS slowdown rule | B/C |
| Anti-pattern: hypoxic to failure | No “hypoxic fail” patterns in v1; breath ladders optional easy only | C |
| Anti-pattern: all threshold every day | hard_share guardrail + max 1 CS/week | C |
| Anti-pattern: wrist HR zones | Soft HR display only | B |
| Masters: need continuous ~200–400 before joining; lane by 100 pace | Intake: continuous baseline; don't prescribe masters-club send-offs without CSS | C |

---

## 7. Concrete Rules Pack patterns (12 shapes) — original meters

Fathom-authored parametric shapes for U3. Notation: effort {E,S,C,F}; `r` = rest seconds; paces relative to CSS. **Do not copy vendor workout text.**

| ID | Role | Pattern (meters) | When |
|---|---|---|---|
| **FP-WU** | Warm-up | `1×300 E free` + `4×50 build 1→4, r=15` | Every session (scale WU 300–600) |
| **FP-CD** | Cool-down | `1×(100–300) E choice` | Every session; ≥200 after test/proof/CSS |
| **FP-AE-R** | Endurance | `k×200 S, r=20→10` (k=5…8) | Early capacity rungs |
| **FP-AE-L** | Endurance | `k×400 S, r=25→15` (k=2…5) | Mid/late rungs |
| **FP-AE-P** | Endurance | Pyramid `200–300–400–300–200 S, r=25–35` | Variety endurance day |
| **FP-AE-C** | Endurance | Continuous rehearsal `1×(R_k−100) S` + `1×100 E` | 5–10 d pre-proof |
| **FP-CS-100** | Quality | `10–15×100 C, r=10–15` | ≤1×/week threshold |
| **FP-CS-MIX** | Quality | Mixed CSS hold: blocks of `4×100 C` alternating with `1×(200→400) C, r=15` | n≥3, later weeks |
| **FP-TK** | Technique | `8×50` as `25 drill + 25 swim E, r=15` (one cue) | Technique role |
| **FP-TST-CSS** | Test | WU → `1×400 TT` → `10–15 min E` → `1×200 TT` → CD | Intake + every ~6–8 wk |
| **FP-TST-10** | Test | `10×100 strongest sustainable avg, r=10–15`; T-pace = (total−rest)/10 | CSS fallback |
| **FP-PRF** | Proof | `1×R_k continuous S` (pass/fail; near-pass ≥90%) | Milestone rung |

**Assembly:** WU + optional TK + one Main + CD. Max one FP-CS\* per week for n≤3. Volume +5–10%/wk; deload ~80% every 3rd–4th week.

**Superset path:** USMS clean-room pass proposes **26 patterns + 6 modifiers** (send-off ladders, weekly drill rotation, `pass_with_split`, etc.) — see `2026-10-09-usms-masters-workout-sources.md`. Ship these **12 FP-\*** first; expand under the “rule of two” provenance gate. Align ladder engine with USMS amendments already folded into the algorithms doc (`ladder_shape`, session clamp 1,300–2,000 m, no breath-hold sets).

---

## 8. Honesty matrix — ingest vs distill vs ignore

| Source | Ingest | Distill | Ignore |
|---|---|---|---|
| Open Swim Workout / SwimWorkoutKit | JSON Schema + SPEC field list (MIT) | — | Example SCY workouts as product content |
| swimming-resources index | Optional CC BY index JSON with attribution | Free linked plan/CSS tips | Linked paid libraries' bodies |
| OpenSwim (Daniel) | Model architecture under MIT | 12 category shapes → FP-\* | Claim scientific authority |
| PMC6891622 | — | Periodic matching + avoid fixed windows | Dataset (unavailable); Agon v1 path |
| SwimBIT PMC6915422 | Firmware link only if hardware play | Pitch/turn + energy stroke ideas | Raw data; trunk indicators on wrist |
| Swim Smooth public blog | — | CSS zones, week roles, miss-week rule | GURU / paid plans |
| MSNSW free PDFs/tips | — | Session elements, CSS/BES framing | Shipping PDF text |
| r/Swimming / Slowtwitch | — | Progress timelines, anti-patterns | Verbatim forum posts in UI |
| MySwimPro / USMS library / TP | — | Taxonomy only if public blurbs | Scrapes / member content |

---

## 9. Twelve actionable recommendations for Fathom Agon v1

1. **Ship a Dart Agon profile** aligned to OSW v0.2 subset: course, sections, sets, effort, rest/sendoff-single — not full lane groups.
2. **Author Rules Pack v1** with the 12 FP-\* meter patterns above; stamp version + provenance on every generated program (plan U3).
3. **Anchor intensity on CSS (400/200)** with confidence label; offer 10×100 and T-30 fallbacks; never wrist-HR zones.
4. **Encode 2/3/4–5 session roles** from Swim Smooth + Reddit sticky weeks; enforce ≤1 threshold main/week for distance goals.
5. **Treat capacity and pace as separate tracks** with honest horizon warnings (pace ~0.3–0.5 s/100/wk early).
6. **Borrow OpenSwim execution lessons**: flatten instructions, pool-length divisibility, serializable models, in-progress restore — keep Fathom chore ledger.
7. **Optional MIT review** of OpenSwim `Workout.kt` / `SampleWorkouts.kt` for shape inspiration; do not ship their strings as Fathom IP.
8. **Use swimming-resources as a curated link index** (CC BY + attribution) for research; never treat it as a redistributable workout corpus.
9. **Park Zhuang + SwimBIT on Q4 backlog** until GT5 motion streams exist; prefer Brunner for wrist IMU eval.
10. **Distill MSNSW/Swim Smooth free materials into formulas** (CSS, rest-shrink, long-rep ladders); do not embed PDFs or GURU text.
11. **Hard-ban anti-patterns in the pack**: hypoxic-to-failure, daily threshold, HR-zone mains.
12. **Calibrate on owner GT5 history** — public sources fill shapes; longitudinal truth is CanonicalSwimSession + proofs.

---

## 10. Source checklist (fetched 2026-10-09)

| # | Source | Status |
|---|---|---|
| 1 | openswimworkout.com + SwimWorkoutKit Spec/schema | Read |
| 2 | timothy22000/swimming-resources README + JSONL filter | Read |
| 3 | Danielbunckenburg/openswim README, LICENSE, Workout.kt, SampleWorkouts.kt | Read |
| 4 | PMC6891622 full text | Read |
| 5 | PMC6915422 full text + MDPI PDF | Read |
| + | Swim Smooth zones, Slowtwitch CSS threads, MSNSW tips/PDFs, 220 Triathlon hub, Reddit search-index | Read (partial / snippets) |

---

## 11. Related docs

- `docs/brainstorms/research/2026-10-09-swim-data-sources-four-questions.md`
- `docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md` — CSS / ladder engine (USMS amendments applied)
- `docs/brainstorms/research/2026-10-09-usms-masters-workout-sources.md` — 26+6 vocabulary + clean-room protocol
- `docs/brainstorms/research/2026-10-09-fathom-data-for-programs.md`
- `docs/plans/2026-10-09-002-feat-pool-swim-programs-plan.md` — U3 Rules Pack

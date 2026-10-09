---
date: 2026-10-09
topic: swim-data-sources-four-questions
status: research-complete
type: research
origin: user-shared GPT source list + expanded non-USMS pass (additional sources catalog)
feeds:
  - docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md
  - docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md
  - docs/brainstorms/research/2026-10-09-usms-masters-workout-sources.md
  - docs/brainstorms/research/2026-10-09-fathom-data-for-programs.md
  - docs/plans/2026-10-09-002-feat-pool-swim-programs-plan.md
author: best-practices-researcher subagent
---

# Swim data sources for Fathom — four questions, ingest vs inform

> Broader pass beyond USMS and the GPT shortlist. Distinguishes **downloadable datasets** from **papers / workout libraries / schemas / APIs**. Not legal advice — verify license before shipping any third-party file. No invented download URLs.

---

## 0. Executive verdict

Fathom needs answers to **four different questions**. No single corpus covers all four. Most “swim datasets” on the web are **sensor labels** (Q4) or **competition times** (weak Q1) — not training trajectories or adult recreational benchmarks.

| Q | Question | Best Fathom answer today |
|---|---|---|
| **1** | How am I improving? | **P0: own GT5 / CanonicalSwimSession history** + repeatable Trial / Sounding tests. Public longitudinal corpora are competition results or small lab studies — **benchmark layer**, not embed. World Aquatics / Swim.com are **not** integrable feeds. |
| **2** | Why am I slow / inefficient? | **Inform algorithms** from Maglischo/FINIS/stroke literature + SWOLF/stroke/pace already on device. SwimXYZ / Malta video are **future video**, not TCX. GT5 cannot see body alignment. |
| **3** | What should I train next? | **Build Rules Pack** (CSS + milestone ladder + set patterns). Distill Swim Smooth / Maglischo / MSA–MSNSW / FINIS / TP plan *shapes*; adopt **Open Swim Workout** (or swiML / OpenSet) as *format*, not content. |
| **4** | Can we extract more from GT5-like watches? | **P1: Brunner** (already covered) for stroke/turn/rest if motion streams appear. **P2: Cosoli HR Zenodo** (already covered) + additional wrist-vs-chest papers to keep optical HR soft. Kaggle IMU cards are weak / license-unknown / likely synthetic — do not treat as GT5 ground truth. |

### Integrate vs inform (priority)

| Pri | Action | Resource |
|---|---|---|
| **Integrate (code / fixtures)** | P0 | Owner GT5 session history |
| | P1 | Open Swim Workout schema (+ compare swiML / OpenSet) for Agon prescriptions |
| | P1 | Fathom-owned Rules Pack (formulas + ~20 patterns), provenance-tagged |
| | P1 | Brunner IMU (offline eval only) — already covered |
| | P2 | Cosoli HR CSV — already covered |
| **Inform algorithms (distill)** | — | Swim Smooth CSS zones / 10-wk progression; Maglischo training-zone papers; FINIS Tempo Trainer protocols; MSA planning PDF; MSNSW aerobic/sprint program *shapes*; TrainingPeaks CSS plan *structure* from public blurbs; Outdoor Swimmer CSS endurance; GoSwimFast category shapes; Applied Sciences / Polar OH1 wrist-HR papers |
| **Ignore as product feed** | — | World Aquatics GMS/rankings scrape; Swim.com bulk API (none); TrainingPeaks paid plan bodies; USMS member library; Kaggle “technique feedback” multimodal CSV (synthetic-looking); commercial OpenSwim app corpus |

**Still missing:** OpenPowerlifting-style *training* trajectories for adult recreational pool swimmers. Build the benchmark layer from published study *statistics*, labeled competition results, own longitudinal Tests, and (later) opt-in anonymized Fathom users.

---

## 1. Classification key

| Tag | Meaning |
|---|---|
| **(a)** | Downloadable / embeddable dataset (files on disk under a stated license) |
| **(b)** | Algorithm-informing paper / article / coach method |
| **(c)** | Workout format / schema / interchange |
| **(d)** | Paywalled / member-only / commercial ToS-restricted |
| **ingest** | May use locally under license (fixtures, offline eval, schema). Not “ship inside APK” unless redistribution is allowed. |
| **distill** | Encode patterns into *our* rules; do not copy verbatim text/workouts. |
| **ignore** | Wrong problem, wrong population, unusable license, or not a real feed. |

Honesty rule: separate **measured facts** (GT5), **research-derived expectations** (published stats), and **Fathom hypotheses** (forecast goal-day).

---

## 2. Additional sources catalog (beyond already-covered shortlist)

> **Already covered as primary — not re-researched here:** USMS articles/library; Brunner ISWC 2019; Cosoli Scientific Data 2026 / Zenodo 18992173; SwimBIT PMC6915422; Intelligent Swimming Analytics PMC8348079; SwimXYZ Zenodo 8399376; PMC6891622 smartwatch; timothy22000/swimming-resources; openswimworkout.com; Danielbunckenburg/openswim; swiML.org; MastersPostal ePostal; Swim England membership plans.

Each row below is **additional**. Types: (a)/(b)/(c)/(d) as above.

### A1. Swim Smooth — CSS zones & 10-week progression

| Field | Value |
|---|---|
| **Name** | Swim Smooth public blog + GURU CSS tools |
| **URLs** | https://blog.swimsmooth.com/p/understanding-training-zones · https://blog.swimsmooth.com/p/challenge-yourself-with-our-2024 · https://www.swimsmooth.guru/css/calcsingle |
| **Serves** | **Q1** (CSS retest cadence, ~0.3–0.5 s/100/wk gains, plateau 8–12 wk), **Q3** (zones, session roles, Goldilocks-style CSS sets) |
| **Type** | **(b)** public articles; full 40-session plans / GURU library **(d)** |
| **License** | Blog readable; commercial product content © Swim Smooth — no redistribution of workout library. Older FINIS brochure once linked a `CSS_Development.xlsx`; **current delivery is GURU-gated** — do not invent a live download URL. |
| **Fathom** | **distill** — already central to algorithms doc (CSS formula anchors, zone offsets, missed-week +1 s/100 rule). Do **not** ingest GURU workouts. |

### A2. Maglischo — training zones / fast-twitch papers (public PDFs)

| Field | Value |
|---|---|
| **Name** | Ernest Maglischo — “Training Zones Revisited” + fast-twitch fiber training manuscripts |
| **URLs** | https://onewiththewater.org/downloads/ART-Training-Zones.pdf · https://cdn.ymaws.com/swimmingcoach.org/resource/resmgr/swimresearch/manuscript-maglischo-vol19.pdf · https://rowperfect.co.uk/wp-content/uploads/2012/01/Training-fast-twitch-fibers.pdf |
| **Serves** | **Q3** (zone definitions, endurance set durations, HI vs LI balance); weak **Q2** (fiber / intensity rationale for “why fatigue”) |
| **Type** | **(b)** |
| **License** | Published coaching/research PDFs hosted by third parties; treat as **cite + distill**, not republish. Full book *Swimming Fastest* (Human Kinetics) is **(d)** / borrow-only on Internet Archive (`access-restricted-item`). |
| **Fathom** | **distill** into Rules Pack zone wording and “≤1 quality session / week for distance goals” posture. Do not digitize book chapters. |

### A3. Sweetenham & Atkinson — *Championship Swim Training*

| Field | Value |
|---|---|
| **Name** | Bill Sweetenham & John Atkinson — *Championship Swim Training* (Human Kinetics, 2003) |
| **URLs** | Publisher/catalog: https://books.google.com/books/about/Championship_Swim_Training.html?id=o3wz_eJH6EAC · Open Library: https://openlibrary.org/works/OL18441710W/Championship_swim_training |
| **Serves** | **Q3** (benchmark sets, long-term program structure, taper); some **Q2** drill progressions |
| **Type** | **(d)** commercial book |
| **License** | © Human Kinetics — no free redistribution corpus |
| **Fathom** | **distill** high-level ideas only (if a coach owns a copy). **ignore** as ingest. |

### A4. World Aquatics / FINA results & rankings endpoints

| Field | Value |
|---|---|
| **Name** | World Aquatics competition results pages + rankings PDF endpoints + GMS |
| **URLs** | https://www.worldaquatics.com/ · rankings-style endpoint pattern e.g. `https://api.worldaquatics.com/fina/rankings/swimming/report/pdf?...` · GMS login: https://data.worldaquatics.com/home/ · GMS ToS: https://data.worldaquatics.com/TermsAndConditions/TermsAndConditions.htm · Site legal: https://www.worldaquatics.com/legal |
| **Serves** | Weak **Q1** (elite competition times only) |
| **Type** | Undocumented / login GMS; not a documented public commercial API. Third-party paid APIs (e.g. DataSportsGroup) are **(d)**. |
| **License / deprecation note (2026-10-09)** | GMS Terms: users acquire **no rights** to system Data; lawful use limited to **non-commercial, educational, private or domestic**; broader use needs **prior written consent**. Site ToS prohibit data mining / commercial use. **No sunset of a public developer API found** — because there is **no licensed public developer API** for Fathom-style reuse. |
| **Fathom** | **ignore** as ingest/feed. Optional human-readable elite context only under counsel. |

### A5. Swim.com

| Field | Value |
|---|---|
| **Name** | Swim.com (lap-swim tracker / analytics) |
| **URLs** | https://blog.swim.com/importing-and-exporting-data-from-your-swim-com-swim-feed/ · https://blog.swim.com/fit-file-exports-link-strava-mapmyfitness-others/ |
| **Serves** | Weak **Q1** (per-user history only) |
| **Type** | Consumer app; **no documented public developer API** for bulk workout analytics. Per-workout FIT/CSV/XML export (historically web; mobile migration notes on blog). |
| **License** | Proprietary user data; ToS apply |
| **Fathom** | **ignore** as corpus. Do not scrape. Owner may export own FIT for personal comparison — not a Fathom dependency. |

### A6. TrainingPeaks — CSS / triathlon swim plans (public plan pages)

| Field | Value |
|---|---|
| **Name** | TrainingPeaks marketplace CSS swim plans + structured-swim FAQ |
| **URLs** | Example public plan blurbs: https://www.trainingpeaks.com/training-plans/other/swimming/tp-432070/16-week-triathlon-swim-plan-css-200-215-per-100m · https://www.trainingpeaks.com/training-plans/other/swimming/tp-396436/css-booster · FAQ: https://help.trainingpeaks.com/hc/en-us/articles/9121983425421-Structured-Swim-Workouts-FAQ |
| **Serves** | **Q3** (3-session week: CSS / VO2-style / extensive endurance; ~20–30 min CSS volume targets; retest weeks) |
| **Type** | Plan *descriptions* public; full structured workouts **(d)** paid |
| **License** | © coaches / TrainingPeaks — no scrape of plan bodies |
| **Fathom** | **distill** session-role structure from public descriptions only. **ignore** plan files. |

### A7. Intervals.icu Open API (swim workouts + own activities)

| Field | Value |
|---|---|
| **Name** | Intervals.icu Open API |
| **URLs** | https://www.intervals.icu/features/open-api/ · forum guide: https://forum.intervals.icu/t/downloading-planned-workouts-from-the-api/93737 |
| **Serves** | **Q1** for *the authenticated athlete’s* history; **Q3** via `workout_doc` / FIT/ZWO exports (**c**-like native format) |
| **Type** | Per-user REST API (API key / OAuth) — **not** a public swim corpus |
| **License** | Athlete-owned data under Intervals.icu ToS; third-party apps need scopes. Client wrappers (e.g. npm `intervals-icu-api`) are MIT — that is **code**, not Intervals content. |
| **Fathom** | **ignore** as public dataset. Optional later **interop** if owner links Intervals; useful as **schema inspiration** for step/repeat/distance targets. |

### A8. Kaggle — “Swimming styles IMU data”

| Field | Value |
|---|---|
| **Name** | Ruslan Bredun — Swimming styles IMU data |
| **URL** | https://www.kaggle.com/datasets/ruslanbredun/swimming-styles-imu-data |
| **Serves** | **Q4** (Acc/Gyr/Mag slices by style) |
| **Type** | **(a)** CSV slices (~11.75 MB listed) |
| **License** | Kaggle card: **Unknown** (as of 2026-10-09) |
| **Fathom** | **ignore** until license clarified; even then short multi-second slices — weak GT5 generalization. Prefer Brunner if any IMU eval is needed. |

### A9. Kaggle — “Multimodal Wearable Swimming Technique Dataset”

| Field | Value |
|---|---|
| **Name** | commcollabs — Multimodal Wearable Swimming Technique Dataset |
| **URL** | https://www.kaggle.com/datasets/commcollabs/multimodal-wearable-swimming-technique-dataset |
| **Serves** | Claimed **Q2** + **Q4** (IMU + stroke phases + HR + “Technique_Feedback” labels) |
| **Type** | Listed **(a)** CSV, CC0 |
| **License** | Card states **CC0: Public Domain** |
| **Honesty** | 12.5k rows with coach ratings, hydration, blood O₂, perfectly tiled Session_IDs — **strongly resembles synthetic / tabular ML toy data**, not a wearable capture study. No paper DOI on the card. |
| **Fathom** | **ignore** for product science. Do not train or cite as real biomechanics. |

### A10. Masters Swimming Australia — planning resource

| Field | Value |
|---|---|
| **Name** | MSA coaching “Planning” reading (annual / phase / weekly / session) |
| **URL** | https://mastersswimming.org.au/wp-content/uploads/2021/10/Reading-Planning_Updated-13-10-2021.pdf |
| **Serves** | **Q3** (Endurance / Quality / Race Prep / Taper phases; test-set placement; volume undulation) |
| **Type** | **(b)** public PDF |
| **License** | MSA coaching education material — cite; do not republish wholesale. “Swim for (Your) Life” handbook announced as **member free download** (https://mastersswimming.org.au/swim-for-your-life/) → treat as **(d)** until membership terms checked. |
| **Fathom** | **distill** periodization vocabulary into Rules Pack provenance. |

### A11. Masters Swimming NSW — aerobic / sprint programs + drills handbook

| Field | Value |
|---|---|
| **Name** | MSNSW Training Programs (Anne Smyth) + Coaching Drill Handbook + Manly 2021 Excel |
| **URL** | https://mastersswimmingnsw.org.au/coaches-and-officials/coaching/training-programs/ |
| **Serves** | **Q3** (aerobic vs sprint taxonomies, threshold-pace freestyle sets, level 1–3 differentiation); weak **Q2** via drill handbook |
| **Type** | Public web library of session PDFs / links + Excel share — **(b)/(LIBRARY)** not a research dataset |
| **License** | Club/association coaching resources; courtesy share — **distill patterns**, do not scrape into APK |
| **Fathom** | **distill** set shapes (descending intervals, broken 100s, threshold maintain-pace) into original meter patterns. |

### A12. FINIS Tempo Trainer Pro — manuals & CSS pacing protocols

| Field | Value |
|---|---|
| **Name** | FINIS Tempo Trainer Pro Manual + Reference Guide; MSNSW Tempo Trainer coaching tips |
| **URLs** | https://www.finisswim.com/documents/Manuals/Tempo%20Trainer%20Pro%20Manual%20.pdf · https://www.finisswim.com/documents/Other/TTP_ReferenceGuide_Spreads.pdf · https://mastersswimmingnsw.org.au/coaches-and-officials/coaching/coaching-tips/tempo-trainers/ |
| **Serves** | **Q3** (Mode 2 lap-pace beeps, CSS “stay with beep” / “beat the beep”, 10-week CSS control-set outlines in older reference guide); **Q2** (stroke-rate Mode 1 / SPM Mode 3 as efficiency levers) |
| **Type** | **(b)** vendor + association tips |
| **License** | © FINIS / MSNSW — cite; rewrite protocols in Fathom voice |
| **Fathom** | **distill** into optional “pace cue” coaching copy and CSS session templates (no hardware dependency). |

### A13. OpenSet — sport-agnostic workout JSON standard

| Field | Value |
|---|---|
| **Name** | OpenSet (getdiby/openset) |
| **URLs** | https://openset.dev/ · https://github.com/getdiby/openset |
| **Serves** | **Q3** interchange only |
| **Type** | **(c)** JSON Schema 2020-12; MIT |
| **License** | MIT (repo) |
| **Fathom** | **ingest schema for comparison** — swimming is a supported sport tag, but examples skew strength. Prefer **Open Swim Workout** for pool-native semantics; keep OpenSet as cross-sport fallback. Early-stage (few stars as of research date). |

### A14. University of Malta SWIM2 stroke videos (Zenodo)

| Field | Value |
|---|---|
| **Name** | Videos of Swimming for Every type of Stroke (SWIM2 ONLY) [001] |
| **URL** | https://zenodo.org/records/19882319 (DOI 10.5281/zenodo.19882319) |
| **Serves** | **Q2** (real video of stroke segments — turn→finish underwater context) |
| **Type** | **(a)** multi-part zip (~49 GB part listed); part of a larger split dataset |
| **License** | **CC BY 4.0** (© 2025 University of Malta) |
| **Fathom** | **ignore for Programs v1**; **P3 ingest** only if a camera technique module appears. Not usable for TCX/GT5 Agon. |

### A15. Wrist optical HR agreement papers (beyond Cosoli dataset)

| Field | Value |
|---|---|
| **Name** | Applied Sciences 2025 — wristwatch vs temple OH1+ vs chest strap (front crawl); Polar OH1/M600 validation (Frontiers/PMC) |
| **URLs** | https://www.mdpi.com/2076-3417/15/11/5848 · https://pmc.ncbi.nlm.nih.gov/articles/PMC7161966/ |
| **Serves** | **Q4** (GT5-like wrist PPG unreliability; temple optical much closer to chest) |
| **Type** | **(b)**; raw data **on request** (not a public download URL) |
| **License** | Open-access articles (MDPI/CC BY family typical for MDPI; PMC paper states data in paper / request) |
| **Fathom** | **distill** into product honesty: wrist HR soft-only; do not invent a Fathom download of their raw files. Complements Cosoli (already covered) without replacing it. |

### A16. Outdoor Swimmer — CSS / masters / endurance articles

| Field | Value |
|---|---|
| **Name** | Outdoor Swimmer Magazine coach articles (masters sessions, 10 km plan, CSS pacing) |
| **URLs** | https://outdoorswimmer.com/coach/how-tos/train-like-a-master/ · https://outdoorswimmer.com/coach/how-tos/10km-open-water-training-plan/ |
| **Serves** | **Q3** (CSS+3–5 s/100 endurance pace; masters-style set shapes); weak **Q1** (retest framing) |
| **Type** | **(b)** public articles; OW volume tips transferable to long-pool endurance |
| **License** | © Outdoor Swimmer — cite + distill; do not republish workouts |
| **Fathom** | **distill** endurance-pace offset and multi-session week shapes into Rules Pack (pool meters). OW-only skills (sighting) stay out of pool v1. |

### A17. GoSwimFast — free public workout library (~150)

| Field | Value |
|---|---|
| **Name** | GoSwimFast free workout library |
| **URLs** | https://goswimfast.com/workouts |
| **Serves** | **Q3** pattern catalog (sprint, distance, pacing, kick, technique, recovery, open water) |
| **Type** | **(b)/(d)** free to read on web, no signup — still copyrighted pages, not an open dataset |
| **License** | Site content © — **distill shapes only**; no scrape / no embed |
| **Fathom** | **distill** category taxonomy + a few set *shapes* into original meter patterns. Same posture as USMS public articles. |

### Catalog map (quick)

| ID | Source | Q1 | Q2 | Q3 | Q4 | Rec |
|---|---|---|---|---|---|---|
| A1 | Swim Smooth | ✓ | | ✓ | | distill |
| A2 | Maglischo PDFs | | ~ | ✓ | | distill |
| A3 | Sweetenham book | | ~ | ✓ | | distill / ignore ingest |
| A4 | World Aquatics | ~ | | | | ignore |
| A5 | Swim.com | ~ | | | | ignore |
| A6 | TrainingPeaks CSS plans | | | ✓ | | distill blurbs |
| A7 | Intervals.icu API | own | | ✓ fmt | | ignore corpus |
| A8 | Kaggle styles IMU | | | | ✓ | ignore (license) |
| A9 | Kaggle multimodal technique | | ✗ | | ✗ | ignore |
| A10 | MSA Planning PDF | | | ✓ | | distill |
| A11 | MSNSW programs | | ~ | ✓ | | distill |
| A12 | FINIS Tempo Trainer | | ✓ | ✓ | | distill |
| A13 | OpenSet | | | ✓ | | compare schema |
| A14 | Malta SWIM2 video | | ✓ | | | P3 only |
| A15 | Wrist HR papers | | | | ✓ | distill |
| A16 | Outdoor Swimmer CSS | ~ | | ✓ | | distill |
| A17 | GoSwimFast library | | | ✓ | | distill shapes |

---

## 3. Q1 — How am I improving? (brief)

| Source | Type | Use |
|---|---|---|
| **Own GT5 / `CanonicalSwimSession`** | Measured | **ingest (P0)** |
| **CSS / proof retests** (Swim Smooth cadence) | Method | **distill → product** |
| **World Aquatics / Swim.com** | Competition or proprietary | **ignore** as feed |
| **ePostal / meet CSVs** (already covered) | Competition | **inform** percentiles only |
| **Intervals.icu** | Own-athlete API | Optional interop later |

Gap unchanged: no public recreational **training trajectory** corpus.

---

## 4. Q2 — Why am I slow? (brief)

| Source | Use |
|---|---|
| GT5 SWOLF / stroke count / pace | **ingest (P0)** proxies |
| FINIS stroke-rate / DPS pacing cues | **distill** |
| Maglischo / Sweetenham drill logic | **distill** (owned book) |
| SwimXYZ (already covered) — **synthetic** | P3 video only |
| Malta SWIM2 — **real video**, CC BY 4.0 | P3 only |
| Kaggle multimodal technique CSV | **ignore** (likely synthetic) |

Without video/multi-IMU on the athlete, do not invent catch/hip-rotation diagnoses from wrist TCX.

---

## 5. Q3 — What should I train next? (brief)

| Source | Use |
|---|---|
| Fathom Rules Pack | **build** |
| Open Swim Workout / swiML (already covered) | **format (P1)** |
| OpenSet | **format compare** |
| Swim Smooth / Maglischo / MSA / MSNSW / FINIS / TP blurbs | **distill** |
| USMS / Swim England (already covered) | **distill** public only |
| Paid TP / GURU / USMS member libraries | **ignore** as ingest |

---

## 6. Q4 — GT5-like wearables (brief)

| Source | Use |
|---|---|
| Brunner (already covered) | **ingest offline (P1)** if motion streams exist |
| Cosoli Zenodo (already covered) | **ingest CSV (P2)** for HR honesty |
| A15 wrist vs temple papers | **distill** |
| Kaggle A8/A9 | **ignore** / license-unknown |

GT5 Programs path today: totals + laps, fragile HR — keep Q4 R&D off the Agon v1 critical path.

---

## 7. GPT list — corrections & caveats

User-shared GPT shortlist, checked 2026-10-09. Corrections that matter:

| GPT item | Verified? | Caveat (do not overclaim) |
|---|---|---|
| Brunner smartwatch recognition | **Yes** — GitHub labeled 30 Hz training data | Confirm commercial reuse; historically “raw soon” may still be incomplete |
| Cosoli 2026 wearable HR | **Yes** — Nature article + Zenodo CSV | **Article CC-BY-NC-ND ≠ redistribute/adapt the article text.** Dataset on Zenodo is separately **CC BY 4.0**. Do not confuse the two. |
| SwimBIT | **Yes** — paper | Confirm downloadable raw before calling it an embeddable dataset |
| Intelligent Swimming Analytics | **Yes** — paper | Adolescent competitive; architecture reference, not adult recreational benchmarks |
| **SwimXYZ** | **Yes** — Zenodo CC BY 4.0 | **Synthetic** motions/videos (SMPL + rendered frames). Not real athlete performance sessions. Useless for TCX Programs v1. |
| PMC6891622 wrist IMU | **Yes** — paper | Confirm files in data-availability |
| swimming-resources | **Yes** | **Index of links**, not measurements |
| Open Swim Workout | **Yes** | **Format/schema**, not measured data or validated physiology |
| **OpenSwim** (Danielbunckenburg) | **Yes** — GitHub | **Format + ~12 original offline workouts** — easy/technique/aerobic/endurance/threshold/sprint. **Not science validation.** Review before reuse. Do not confuse with commercial **open-swim.com** app (ToS: workouts personal-use only). |
| swiML | **Yes** | Alternate FORMAT (XML) to OSW |
| USMS / Swim England libraries | Partial | Public articles ≠ member libraries; member content is not a scrapable dataset |

**Correct framing:** a downloadable dataset ≠ a research paper ≠ a workout library ≠ an API. CC-BY on a *paper* does not grant a *data* dump; NC-ND forbids derivative redistribution of the licensed text even when the companion Zenodo file is more permissive.

---

## 8. Decision table (integrate vs inform)

| Priority | Resource | Capability | Action |
|---|---|---|---|
| P0 | Own GT5 history | Progress + Trial evidence | Ship against `CanonicalSwimSession` |
| P1 | Open Swim Workout (± swiML / OpenSet compare) | Planned vs actual | Adopt schema for Agon |
| P1 | Brunner IMU | Stroke/turn/rest validation | Offline until motion on device |
| P1 | Fathom Rules Pack | Next session + milestones | Build; provenance-tag distilled patterns |
| P2 | Cosoli HR Zenodo | HR honesty | Offline analysis; soft copy |
| P2 | Swim Smooth / Maglischo / MSA–MSNSW / FINIS / TP blurbs / Outdoor Swimmer / GoSwimFast | Pattern seeds | Distill into original meters |
| P2 | A15 wrist-HR papers | Product honesty | Distill |
| P3 | SwimXYZ / Malta SWIM2 | Video technique | Defer |
| — | World Aquatics / Swim.com / TP plan files / USMS member lib / Kaggle A9 | Content or ToS | **Do not scrape / ignore** |
| — | Strava | Logs | **No AI/model use** per policy |

---

## 9. Recommended next engineering steps

1. **Lock Agon prescription schema** — spike Open Swim Workout vs swiML vs OpenSet; prefer OSW for pool semantics.
2. **Rules Pack v1** — CSS + capacity ladder + session roles; provenance from Swim Smooth CSS + Maglischo zones + MSA/MSNSW shapes + FINIS pacing cues (plus already-covered USMS/Swim England).
3. **Benchmark layer v0** — published improvement rates with population footnotes — **not** a downloadable athlete DB.
4. **HR honesty** — Cosoli CSV notebook + A15 paper quotes → Soft-warn language; no zone engine from wrist PPG.
5. **Q4 spike (optional)** — Brunner only; skip Kaggle A8/A9.

---

## 10. Related docs

- `docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md` — CSS, TID, rules recommendations
- `docs/brainstorms/research/2026-10-09-usms-masters-workout-sources.md` — USMS only
- `docs/brainstorms/research/2026-10-09-opensource-swim-formats-and-community-practice.md` — OSW / OpenSwim / PMC papers / community → Rules Pack patterns
- `docs/brainstorms/research/2026-10-09-fathom-data-for-programs.md` — what GT5 already stores
- `docs/plans/2026-10-09-002-feat-pool-swim-programs-plan.md` — U3 Rules Pack

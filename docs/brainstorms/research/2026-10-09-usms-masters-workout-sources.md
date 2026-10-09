---
date: 2026-10-09
topic: usms-and-masters-swim-workout-sources
status: research-complete
type: research
feeds:
  - docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md (R8–R11, R13; rules-pack authoring)
  - docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md (§3 data inventory, §6.5 set vocabulary — this doc amends/confirms)
author: best-practices-researcher subagent
---

# USMS & masters-swim workout sources — dataset, license, or distill?

> Research input for the **Fathom Programs v1 rules pack**. Question: can U.S. Masters Swimming (USMS) and similar masters/coach content supply a usable *workout/program dataset* or a *distillable rules pack*? **Not legal advice.**

---

## 0. Executive summary (one page)

**Honest answer: USMS is a publisher of articles and a member-gated library, not a dataset.** There is no API, no bulk export, no open license, no CSV/JSON, and no public archive of "Workout of the Week" or "Tip of the Week" at usms.org (I looked; see §2.6). What USMS *does* offer is (a) ~14 public coach-written articles — four of them print ~3–5 complete workouts each (~15–20 workouts total) and the rest give workout-writing rules, (b) a member-only Workout Library (7 specialties, "1000's" of workouts), (c) **35 member-only six-week plans (24 workouts each), six of which are literally "swim N nonstop"** — the closest published analog to Fathom's capacity-milestone ladder, and (d) a delivery integration with Swim.com for pushing library workouts to watches (not a data feed, and not GT5-compatible).

**Recommendation for Fathom: DISTILL. Do not license, do not scrape, do not ignore.**

| Option | Verdict | Why |
|---|---|---|
| **License** | **No (for v1); one cheap exception** | No licensable feed exists. Only path is a bespoke USMS partnership (long shot; their Swim.com deal is the template). The one cheap, legitimate step: a **$75 individual membership** (listed through Dec 31, 2026) so a *human* can read the 750/1,000/1,650 "nonstop" plans and log **aggregate shape only** — after checking member terms (I could not locate a USMS website ToS). |
| **Scrape** | **No** | Library and plans are member-gated; public PDFs reachable by direct URL are still copyrighted ("only accessible to our members"); USMS's own volunteer guidance says "never copy and publish someone else's written intellectual property." Marginal value is low: ~25 set families saturate quickly. |
| **Distill** | **Yes — primary** | Training structure (warm-up → drill → main → pull/kick → cool-down; reps×distance×rest; ladders; rest-shrink; test sets) is **idea/method, not protectable expression** under 17 U.S.C. §102(b) (Bikram Yoga; Copyright Office). Write our own parametric patterns in our own words, tag provenance. |
| **Ignore** | **No** | USMS is the most *citable, named, authoritative* public source for adult-swimmer structure, and its nonstop plans **independently corroborate** our existing rung-ladder rules (see §4). |

**Three findings that change the prior doc (§4):**
1. USMS now lists **35** six-week plans, not 17 (the "17" figure is stale on three USMS pages). Six are nonstop-capacity plans (200/500/750/1,000/1,650/3,000 yd) — directly relevant.
2. The publicly fetchable **500-yd nonstop plan** shows the longest closing swim grows **+50 yd every week** (200→250→300→350→400→450→500 final), i.e. **+10 % of goal per week**, ~4 sessions/week, 1,500–2,150 yd per session. Cross-check: Fathom dogfood (MCD 1,000 m vs goal 1,200 m ≈ 83 %) maps to "week 5 of 6 → ~2 weeks to goal," matching our "+20 % rung, 2–3 weeks."
3. USMS's **1-mile plan** rehearses only to ~61 % of goal (a 1,000-yd swim with a ≤5 s split pause) before the 1,650 final — a *capped-rehearsal* shape that differs from the 500-yd plan's *linear-to-goal* shape. Our single "+15–25 % rung" rule should become a **ladder-shape parameter keyed on goal length**.

**Top recommendation:** Adopt the **clean-room distillation protocol (§5.4)** → ship a **26-pattern + 6-modifier** vocabulary (§7) with a **source registry** and a "rule of two" corroboration gate; keep all set text Fathom-authored; spend $75 + one afternoon on the nonstop plans for *aggregate* calibration; ask USMS for written permission only if we ever want to name them in-app.

---

## 1. Method and honesty notes

- Web search + page fetches on 2026-10-09. I fetched the user-cited article in full and downloaded two publicly reachable USMS plan PDFs (500-yd nonstop; 1-mile open-water) to read their **structure** (not to reproduce them). Where I only saw search-engine snippets, it's labelled **[snippet]**.
- **Could not verify:** (i) any USMS website Terms of Use (several guessed URLs returned 404; search surfaced only the Privacy Policy, 2006 Publishing Policy, Community rules, and volunteer copyright guidance); (ii) Workout Library contents (login wall; community.usms.org also redirects to login); (iii) the 750/1,000/1,650 nonstop PDFs (no public URL found); (iv) Kaggle pages (reCAPTCHA); (v) Swim England 20-session plan contents (members only, only length counts shown).
- Evidence grades follow the prior doc: **[A]** peer-reviewed, **[B]** national-body / established coach text, **[C]** blog/vendor/forum, **[D]** Fathom-calibrated.
- Units: USMS writes **yards** (25-yd pools). 1 yd = 0.9144 m. 500 yd ≈ 457 m; 1,650 yd ≈ 1,509 m; Fathom's 1,000→1,200 m ≈ 1,094→1,312 yd.
- I deliberately do **not** reproduce workouts from USMS pages in this doc; where I describe them, I describe structure and totals only.

---

## 2. Inventory — what USMS (and peers) actually publish

### 2.1 USMS workout-rich public articles (fetched)

| ID | URL | Author / date | What it contains (structure, not text) | Distance | Population |
|---|---|---|---|---|---|
| **USMS-A1** | https://www.usms.org/fitness-and-training/articles-and-videos/articles/best-workouts-for-masters-swimmers | Goodrich, 2021-05-05 (**user-cited**) | **5 complete workouts**: pace set (mixed reps + long swim at one pace), USRPT-style short race-pace, 10×100 test set, planned-breathing/breath-control (with explicit safety warning), recovery. Each is warm-up / main / cool-down with printed totals. | 2,550–3,300 yd printed totals | Masters generalist; sprint/competitive tilt; "choice" stroke default |
| **USMS-A2** | …/best-swimming-workouts-for-beginners **[snippet]** | Goodrich, 2021-05-05 | 5 beginner workouts; workout 1 "Breathe" ≈1,500 yd; workout 2 "Learn your intervals" 20×50 on a fixed send-off ≈1,800 yd; teaches rest vs send-off; stroke-count goal (≤15 per 25 yd) | 1,500–1,800 yd | Beginner |
| **USMS-A3** | …/best-3000-yard-swimming-workouts | Goodrich, 2024-01-02 | 3,000-yd-ish workouts with block subtotals (e.g., warm-up 850 / main 1,900 / cool-down 300); kick-focused, stroke/IM rounds, freestyle-focus 3× rounds | 2,900–3,050 yd (~57–65 min) | Masters, triathletes (workout 3) |
| **USMS-A4** | …/best-sprint-workouts-for-swimming-faster | Donovan, 2021-05-05 | 5 sprint sessions (~1 h each): breathing-pattern ladder with 25s, repeat sprints with fins, kick+swim rounds, descend-to-sprint, broken 200. Prescribes ~2 min rest between blocks; explains "why" for each | ≈1 h each (distance not printed) | Sprint/speed |
| **USMS-A5** | …/how-to-write-a-swimming-workout | Heggy, 2023-01-11 | **Best structural spec**: Warm-up / drill-technique / main / pull-or-kick / supplementary / cool-down; main = **1/3–2/3** of practice; rest-vs-sendoff semantics; set-duration formulas; ladders/pyramids/bookends; scaling to slower swimmers (fewer reps, shorter reps, or time-boxed) | n/a (rules) | Coaches & self-coached |
| **USMS-A6** | …/writing-masters-workouts-for-all-your-swimmers | Goodrich, 2021-08-11 | Warm-up evidence from coach practice: many Masters need **4–8 × 100** to hold pace; **1,200–1,500 yd** warm-up if time allows; alternatives for injuries; per-rep stroke substitution; cool-down tricks (stroke-count-drop 4×25; ascending last set) | n/a (rules) | Masters (age 18–90) |
| **USMS-A7** | …/simple-ways-to-add-volume-productively-to-your-swimming-workouts | Donovan, 2019-08-26 | Volume rules: log first; **warm-up ≤15–20 min**; after 4–6 weeks stable, **+10–15 % (20 % if diligent) every 4–6 weeks**, spread across the week; "10×100 → 10×125" set-level growth; beginners: time not distance (30 min active) | n/a | Self-coached |
| **USMS-A8** | …/how-to-swim-a-mile-nonstop | Bay, 2022-11-01 | Four capacity-building methods: brute force (+lengths per visit), **rest-interval ladder** (33×50 → 100s → 200s, shrink rest), **repetition/send-off ladder** (25s on :30 → 50s on 1:00 → … → 500s on 10:00), plus link to the plans | 1,650 yd goal | Adult beginner → mile |
| **USMS-A9** | …/what-coaches-should-do-after-a-long-layoff-from-workouts | Heggy, 2020-05-17 | Return-to-training rules: technique first; reps +1 per repeat day *or* longer interval then shrink rest; **repeatable test set for 4–6 weeks** (timed 500/800/1000; 10×100 on fixed send-off) | n/a | Returning swimmers |
| **USMS-A10** | …/how-to-write-creative-workouts-every-day **[snippet]** | — | Template: warm-up, technique, kicking, work set, cool-down; adjust work set by how technique went | n/a | Coaches |
| **USMS-A11** | …/masters-workout-writing-made-simple **[snippet]** | Bay, 2013-06-19 | Same volume ≠ same stimulus (50s on 2:00 vs :40); tie set to aerobic/threshold/speed intent | n/a | Coaches |
| **USMS-A12** | …/open-water-swim-training-plan-how-to-train-year-round-in-the-pool | Howley, 2026-06-30 | Pool→open-water translation: aerobic base, speed work, sighting, fewer wall push-offs, drafting | n/a | OW/triathlon |
| **USMS-A13** | …/how-to-develop-your-swim-training-plan **[snippet]** | Bay, 2019-05-24 | Self-logging, individual response, taper personalization | n/a | Self-coached |
| **USMS-A14** | …/the-10-most-read-usms-articles-of-2022 **[snippet]** | — | Weight-loss guidance: mix shorter moderate/high sessions with longer low-intensity | n/a | Fitness |

> Printed totals in articles can be wrong. Recomputing the "test set" workout in USMS-A1 from its printed sets yields ~3,300 yd vs "3,000" printed; the 500-yd plan PDF prints "1,1650" for one session. **Any ingestion must recompute totals** — another reason not to bulk-copy.

### 2.2 USMS Workout Library (member-gated)

- URL: https://www.usms.org/workout-library — 7 specialties (launch post 2020-07-23: basic, sprint, high-volume, stroke & IM, open water, triathlon, low-volume/limited mobility), filters by course/distance/set type, weekly email, print, "send to watch" via Swim.com. Membership copy says "1000's of searchable online workouts." Launch: https://www.usms.org/fitness-and-training/articles-and-videos/articles/us-masters-swimming-launches-exclusive-workout-library-for-members
- **Public by-product worth reusing as *facts*:** the library's time-estimate convention — default pace **2:00/100 m or 1:49/100 yd**, stroke multipliers (choice 1.0×, free 0.90×, back 1.1×, fly 1.2×, breast 1.2×, drill 1.5×, kick 2.0×) and the two interval notations (**send-off** `@2:00` vs **rest** `@:30 rest`). These are method facts, citable, and useful for Fathom's duration estimator.
- No API, no export, no license text found. Individual workout pages are behind login.

### 2.3 USMS six-week plans (member-gated; two PDFs reachable by URL)

- Index: https://www.usms.org/fitness-and-training/six-week-swim-training-plans/six-week-swim-training-plan-information — "**35** customized swim training plans… 24 workouts… six weeks… only accessible to our members."
  - **Swim Farther** (6): nonstop 200 / 500 / 750 / 1,000 / 1,650 / 3,000 yd.
  - **Get Faster** (≈24 listed): per-event (50–1650 free, back, breast, fly, IM) + "100 free in 2:30…1:00." (My count of listed titles is 34 vs the page's "35"; one title is probably not shown.)
  - **Open water** (4): 300 m, 1 mile, 2.4 mile, 5k.
- **Publicly reachable PDFs I read (structure only):**
  - 500 yd nonstop: https://www.usms.org/-/media/usms/pdfs/training%20plans/swimming%20nonstop%20distance%20training%20plans/lb-training%20plan%20-500-nonstop.pdf (header text credits "USMS/LaneMate Training Plan")
  - 1-mile open-water: https://www.usms.org/-/media/usms/pdfs/training%20plans/open%20water%20race%20training%20plans/training%20plan%20-%201-mile-ow_2025_df_final.pdf
  - Neither PDF carries a copyright/licensing notice in its extracted text; the index page nonetheless says plans are member-only. **"Publicly reachable" ≠ "licensed."**
- Observed aggregate shape (my own tallies from the two PDFs; units yd):

| Metric | 500-yd nonstop | 1-mile OW (goal 1,650) |
|---|---|---|
| Sessions | 24 in 6 weeks (**4/week**) | 24 in 6 weeks (**4/week**) |
| Session total | 1,500 → 2,150 (≈3.0×–4.3× goal) | 1,500–2,150 (≈0.9×–1.3× goal) |
| Longest closing/continuous swim by week | W1 200 · W2 250 · W3 300 · W4 350 · W5 400 · W6 450 · swim 24: **500** | W1 500 · W2 300–800 · W3 500–600 · W4 **1,000 (≤5 s pause at 500 for time)** · W5 500 · W6 800 · final: **1,650 for time** |
| Longest rehearsal as % of goal | 90 % before final | **~61 %** (1,000) before final (+65 % jump) |
| Weekly pattern | Each week a *dedicated drill*; equipment tags per session; cool-down "100 easy" not written | Mix: long continuous, ladders (300-400-500), descending sets, drill/kick, IM |
| Intensity words | "swim," "pull," "kick," "fins" — no pace zones | "descend," "build," "smooth," "tempo up with distance" — no pace zones |

### 2.4 Other USMS surfaces

| Surface | URL | Finding |
|---|---|---|
| Swim.com integration | https://www.usms.org/fitness-and-training/workout-tracking/swimcom-integration-information | Delivery rail from USMS library → Swim.com app → Apple/Garmin/Samsung/WearOS watches. Not a data export; no Huawei GT5 path. Swim.com is "official workout and training platform" since 2019-07-23 (https://blog.swim.com/swim-com-becomes-the-official-swim-workout-and-training-platform-of-u-s-masters-swimming/). |
| USMS USRPT slides (2018 committee deck) | https://www.usms.org/admin/minutes/ptp-2018-5-17-1.pdf **[snippet]** | Useful *rule* idea: set protocol with fail rules (two back-to-back misses or three total ends the set); training distance 3–5× race distance. |
| Legacy convention workouts | https://www.usms.org/admin/conv97/bonniesworkout.php | 1997 convention sessions — structurally interesting (ascending-interval 50s, lane-scaled rep lengths) but dated, single-author. |
| Community workouts forum | https://community.usms.org/swimming/f/workouts/19665/new-free-workouts-database-online | Login-walled; a prior thread mentions a ~500-workout free coach database with no explicit license (see prior doc). |
| Publishing policy (2006) | https://www.usms.org/admin/policies/pubs_policies.pdf | "Reproduction… shall be subject to applicable copyright laws and contractual requirements"; "digital archives shall be protected against unauthorized use." |
| Community rules | https://community.usms.org/usms-community-faqs/w/faq/8/usms-community-rules | "Do not post copyrighted articles… You may post a synopsis in your own words… brief quotes with commentary… Do not post entire articles." |
| Volunteer guidance (LMSC/clubs) | https://lanemate.usms.org/admin/lmschb/content/newshints | "Never copy and publish someone else's written intellectual property… without getting permission." |
| Membership | https://www.usms.org/join-usms/join-or-renew | $75 through 2026-12-31 or $125 through 2027-12-31 (as listed 2026-10-09); benefits include searchable workouts, SWIMMER magazine, Swim.com/FLOG tracking. |

### 2.5 "Workout of the Week", "Tip of the Week", "GO Swim" — what they turned out to be

| Name from the brief | What I found |
|---|---|
| **Workout of the Week (WOW)** | A **Swim.com** segment partnered with USMS from Sept 2020 (e.g., https://blog.swim.com/workout-of-the-week-rebooted/, written by elite coach Celia Wolff). **No WOW archive on usms.org.** Swim.com's blog retains individual posts; Swim.com's web tracking was retired in favor of mobile (https://blog.swim.com/swim-com-web-being-retired/). Weekly *emails* of Workout Library entries exist but are member-only. |
| **Tip of the Week** | **Not found at USMS.** Nearest equivalents are the training articles above. |
| **GO Swim** | Ambiguous: (a) **GoSwim.tv** — a paid third-party app/video library (Glenn Mills); listed in the open directory below; (b) USMS **Go the Distance** — a yardage-logging program, **not** workout content. Neither supplies a usable dataset. |

### 2.6 Peer organizations and vendors

| Source | URL | Access | What it offers | Fathom use |
|---|---|---|---|---|
| **Swim England Masters Training Room** | https://www.swimming.org/masters/masters-training-room/training-workouts/ | Public list of coach-authored workout posts (2014–2018: Mel Marshall 2-hour set, Steve Bratt endurance/race-pace, technique session, Becky 2 km lunchtime, 12 Days of Christmas) | Single-author sets with warm-up / main / swim-down | Idea source only; ©Swim England; 2014–18 posts |
| **Swim England 20-session plan** | https://www.swimming.org/members/swimming-fitness-training-plan/ | Members only (sessions 1 & 11 free) | **Total length counts per session** are public: 12, 14, 18, 20, 24, 28, 30, 32, 36, 38, 40, 44, 48, 50, 54, 60, 62, 66, 72, 80 lengths (300 m → 2,000 m in 25 m pool). Every session has warm-up, skill development, main set, swim down. | **Public numeric progression** = a second independent corroboration of "session volume ≈ +5–15 %/session, capped ~2 km" (my reading of the length list) |
| **Masters Swimming Australia** | https://mastersswimming.org.au/tag/training-programs-coaches/ | Member area (login) — Manly Masters programs, 12-month program, drills, "Swim for (Your) Life" handbook (https://mastersswimming.org.au/swim-for-your-life/, members) | Handbook by Mark Morgan; programs | Not accessible; member-only |
| **Masters Swimming Queensland** | https://mastersswimmingqld.org.au/coaching/training-programs/ | Public index of ~100 "Programs" by coach Mark Erickson (titles: mainly freestyle, pyramid, mixed strokes, mainly aerobic); "may be used by individuals… a coach or members of a club" | Plain-language permission for *use at training*; not a license to republish | Human skim for set families; no ingestion |
| **Swim Smooth** | https://www.swimsmooth.guru/terms ; pricing https://www.swimsmooth.guru/pricing | Paid; 1,000+ sessions behind subscription; ToS reserves all copyright; GB patent on parts of Guru | Free blog posts describe CSS zones/weekly roles and a named ladder set | Cite blog ideas (already in prior doc); **no library ingestion; avoid trademark names** (Goldilocks, Red Mist, Pink Mist, Session Roulette, Swim Type) |
| **TrainingPeaks** | https://www.trainingpeaks.com/terms-of-use/ | Paid per-author plans; ToS grants personal download/print license, **forbids robots/data mining**, copying, derivative works | e.g., "Masters Swim Training (6 workouts + 1 drill session/week)" — 12 weeks, 72 workouts + 12 drill sessions, ~3,000–3,300 yd each (https://www.trainingpeaks.com/training-plans/other/swimming/tp-155922/masters-swim-training-6-workouts-1-drill-session-per-week) | **Structure only** (plan descriptions are public): confirms 3,000-yd Masters session norm |
| **Padlie coach study** | https://padlie.com/en/swim-training-study | **Public aggregates; "free to reuse… with a link"** | 6,269 coach-written workouts / 487 coaches (2017–2026, mostly France): **median 4,300 m**, IQR 2,800–6,100 m; **~5 blocks/session** (WU, drills, main, speed, CD); freestyle 69.7 %, swimmer's-choice 8.9 %, IM 8.1 %; intensity by volume: Z1+Z2 ≈ 63 %, Z3 ≈ 18.9 %, Z4–Z7 ≈ 18.2 %; equipment per set: paddles 10.6 %, pull buoy 9.3 %, fins 6.8 %, kickboard 2.0 % | **Best open "field-practice" calibration** for session size/blocks (club/competitive bias noted by the authors) |
| **IRONMAN / Matt Dixon (Purplepatch)** | https://www.ironman.com/news/endurance-swim-workouts | Public article | 4 scalable endurance sessions (e.g., 33×100 on three intervals); warm-up 10 min, pre-set, main, cool-down 200–300 m | Idea source; ©IRONMAN |
| **AquaPlan free workout PDFs** | https://www.aquaplan.fit/swim-workout-pdf/masters | Free downloads | Short, parametric masters/aerobic/IM sessions | Idea source |
| **Triathlon Regimen** | https://triathlonregimen.com/guides/triathlon-swim/best-swim-workouts-triathletes | Public | CSS-zone-relative endurance sessions (2.4–2.8 km) | Corroboration only |

### 2.7 Machine-readable / "dataset" candidates (reality check)

| Item | URL | License / terms | What it is | Useful? |
|---|---|---|---|---|
| `timothy22000/swimming-resources` (GitHub + Hugging Face `t22000t/swimming-resources`) | https://github.com/timothy22000/swimming-resources ; https://huggingface.co/datasets/t22000t/swimming-resources | **CC-BY-4.0** (verified via GitHub/HF API 2026-10-09) | 410-row **directory** (JSON/JSONL/CSV/Parquet): 19 `training_plans` rows, 16 `masters` rows — URLs + metadata, no workouts. Training-plan rows: MySwimPro, USMS Workout Library (tagged *paid*), SwimSwam Workouts, Swim Smooth, TrainingPeaks, Commit, GoSwim, Swimplan, Beyond the Black Line, 220 Triathlon, etc. | **Bookmark list only.** |
| `bartneck/swiML` | https://github.com/bartneck/swiML | **MIT** (verified); last push 2026-07-23 | XML/XSD "Swimming Markup Language" + Python lib + HTML transform; sample = Jasi Masters (NZ) sessions | **Yes — as a *schema reference*** for naming set elements/strokes (not content). |
| `eriktaubeneck/swim-sets` | https://github.com/eriktaubeneck/swim-sets/ | **MIT** (verified) | Tiny YAML → printed swim practice (nested `SwimSet`, rounds, per-lane distance/time) | Schema inspiration for nested sets; no workouts corpus |
| `swimsets/swimsets.github.io` | https://github.com/swimsets/swimsets.github.io | No license; last push 2017 | Static set-generator site | No |
| `alan-couzens/data/workouts.csv` | https://github.com/alan-couzens/data/blob/master/workouts.csv | No license seen | ~21 *generic multisport* session archetypes with zone-minutes (e.g., Technique Swim 45 min, Long Swim 90 min) | Cute reference for session-role taxonomy; not swim-set data |
| Kaggle | https://www.kaggle.com/datasets/commcollabs/multimodal-wearable-swimming-technique-dataset ; …/karaadavis/swim-fitness-tracker (captcha-blocked) | Not verified | Sensor/technique data | Wrong problem (IMU), as in prior doc |
| Zenodo | — | — | **No open Zenodo dataset of masters workouts/sets found.** Only physiology items (e.g., "Swimming versus Land-Based Training and Age") | No |
| Garmin FIT exports | https://jbogomolovas2.github.io/Julius-s-Blog/posts/swim-css-pipeline/index.html | Blog; own data | Method for estimating "base pace" from routine swims (GAM adjusting for rep length, position-in-rep, fatigue, rest, stroke rate) | **Methodological idea for `CSS_hist`** — complements prior doc §6.1 (not workout data) |

**Bottom line on datasets:** there is no open workout corpus. The only open structured assets are *directories* (CC-BY) and *schemas* (MIT). Padlie's aggregates are the only quantitative public "what coaches program" source.

---

## 3. What USMS content is *worth* to Fathom (value ranking)

1. **Structural spec (A5, A6, A10)** — the canonical Masters session grammar and rationale. High value, low copy risk (it is a method).
2. **Capacity-ladder methods (A8, A9, A7) + nonstop plan shapes (P500, P1M)** — directly validates the milestone ladder. High value; *aggregate numbers only*.
3. **Warm-up/age rule of thumb (A6, A7)** — Masters need longer to reach pace; cap 15–20 min unless needed. Medium value; refines WU sizing.
4. **Example workouts (A1–A4)** — good for confirming our vocabulary is complete (pace set, USRPT, test set, breathing, recovery, kick/IM, sprint). Medium value; **not for copying**.
5. **Time-estimate conventions (workout-library glossary)** — default 1:49/100 yd, stroke multipliers. Small but handy.
6. **Test-set doctrine (A1 #3, A9)** — repeatable 10×100 / timed 500–1000 each 4–6 weeks. Corroborates our CSS/test cadence.

Low value for Fathom v1: sprint/USRPT sets, multi-stroke IM-heavy sets (Padlie: freestyle ≈ 70 % of coach volume; our adult free-first athlete population differs from competitive Masters), meet-pace plans.

---

## 4. Comparison vs `2026-10-09-swim-training-algorithms-datasets.md` — update / confirm

**Confirmed (no change):**
- "No clean public workout/program dataset; **build a Fathom-owned, provenance-tagged rules pack**" — **confirmed and strengthened.** USMS adds *no* feed.
- USMS workout library = **member-only, no open license/API** (prior doc §3.1) — confirmed; Swim.com is a delivery rail only.
- Warm-up → (technique) → main → cool-down session grammar (prior §2.7, §6.5) — confirmed by USMS-A5 (adds pull/kick + supplementary blocks).
- Volume progression: USMS-A7 (+10–15 % / 4–6 wk; 20 % if diligent) is already cited — **note it is a *4–6-week* cadence, slower than the 5–10 %/week used for Fathom.** Our weekly rule is a *capacity-building* rule (nonstop goal), not USMS's *maintenance-to-more-yardage* rule; keep both labelled.
- Don't reuse brand names (Goldilocks, Red Mist) — reinforced; add Swim Smooth ToS reference.

**Amend / add:**

| # | Prior doc says | Evidence from this research | Proposed amendment |
|---|---|---|---|
| 1 | "17 six-week plans" (USMS) | USMS index lists **35**; "17" still appears on older pages | Correct to 35; flag the six nonstop plans as the key peers |
| 2 | Rung step `s` default **+20 %** of current MCD (range 0.15–0.25) | P500 grows the closing swim **+50 yd/week** (≈ +25 %→+11 % relative; **+10 % of goal per week**) | Keep default; add an **absolute weekly-step** option: `weekly_step = clamp(0.10·D_goal, 45 m, 0.25·MCD)`; the *relative* step naturally decays as distance grows. Dogfood: 0.10 × 1,200 = 120 m/week → 1,000→1,200 m in ~2 weeks (vs our "+20 % rung over 2–3 weeks") — consistent |
| 3 | One ladder shape | **Two observed shapes:** *linear-to-goal* (500-yd plan: 40 %→90 % of goal then final) vs *capped-rehearsal* (1-mile plan: ≤ ~61 % rehearsal then final) | Add `ladder_shape` = `linear_to_goal` (goal ≤ ~800 m) / `capped_rehearsal` (goal ≥ ~1,500 m; cap 0.6–0.8·D_goal + a *broken* near-goal swim). Dogfood 1,200 m sits between: default `linear_to_goal` with a capped final step [D] |
| 4 | Sessions/week default **n = 3** | USMS nonstop plans assume **4/week** (24 in 6 weeks) | Keep n = 3 default (owner schedule), but show "USMS plans assume 4/week" in provenance; ladder block length for n=3 ≈ +33 % longer than USMS's weekly steps. Consider n=4 optional |
| 5 | Key-session total ≈ **1.5–2.0 × D_goal** | P1M sessions ≈ **1,500–2,150 yd (≈1,370–1,960 m)** regardless of goal; P500 sessions total 3–4× goal; TrainingPeaks masters ≈ 3,000 yd; Padlie median 4,300 m (competitive) | Replace multiplier with **clamp**: `session_total = clamp(1,300–2,000 m, per 45–60 min)` for adult capacity plans; the multiplier only informs *goal ≥ 1,000 m*. Cite P1M, SE-20 (300→2,000 m) and Padlie as bounds |
| 6 | Proof = continuous, rest-gap ≤ 15 s | P1M's "1,000 with ≤5 s pause to read time" | Add `pass_with_split` (≤5 s pause for timing) as an accepted proof variant; keep ≤15 s as the Fathom `rest_gap_s` default [D]. |
| 7 | Rest only (`r=…`) | USMS-A5/A8 distinguish **rest** vs **send-off** and use send-off ladders for capacity | Add `interval_mode: rest | sendoff` to the pattern schema; add pattern AE-B (send-off ladder) |
| 8 | Warm-up = clamp(300, 0.15·S, 600) | USMS-A6: Masters often need 4–8×100 to reach pace; 1,200–1,500 yd if time; A7 caps warm-up at 15–20 min | Add `warmup_scale_age` modifier: for athletes ≥ ~40 (if age known) bias WU +10–15 %; keep time cap 15–20 min [C/D] |
| 9 | Hard share ≤ ~20 % | Padlie: coaches program ~37 % above Z2 (club/competitive); USMS nonstop plans specify **no pace zones** | Keep our pyramidal-easy default for *capacity* goals; note that field practice is harder — don't treat our rule as "what coaches do," treat it as "safe for adult capacity goals" |
| 10 | Pool/yardage units meters | USMS yards | Add `unit_source` on provenance; convert via 0.9144; do not round-trip silently |
| 11 | Weekly dedicated drill not in vocab | P500 assigns **one named drill per week** (kickboard-swim → 6-3-6 → catch-up) | Add TK-B "weekly drill rotation" pattern |
| 12 | Planned-breath-count work only implicit | USMS-A1/A4: explicit **safety stance** on breath control (never swim as far as possible without a breath) | Add **content safety rule**: Fathom never prescribes breath-hold/hypoxic sets; only planned breath counts (TK-D) |

**Net:** USMS does **not** change the architectural decision; it **raises confidence** in ladder rules and adds three vocabulary items (send-off mode, weekly drill, split-pause proof).

---

## 5. Turning article workouts into a Fathom session vocabulary — without copying proprietary text

### 5.1 What you can lift vs what you must not

| Layer | Example | Copyable? |
|---|---|---|
| **Method / structure** | "warm-up → drill → main → cool-down"; main = 1/3–2/3 of session; rest vs send-off; ladders; descend 1–4 | **Yes (idea)** — cite |
| **Generic set shapes** | `10×100 @ rest 15 s`, `4×50 build`, `3×(100 pull + 50 swim)` | **Yes** — ubiquitous vocabulary; not creative expression |
| **Numeric aggregates** | "closing swim grows +50 yd/week", "24 sessions in 6 weeks", "1,500–2,150 yd" | **Yes (facts)** — cite |
| **Specific composition of one author's workout** | an author's exact combination of reps/rests/notes that is distinctive | **Avoid** — treat as expression-adjacent; generalize into a family with *our* numbers |
| **Prose** | coach commentary, rationale paragraphs, drill descriptions, titles | **No** — author fresh |
| **Branded names** | Goldilocks/Red Mist/Session Roulette/DynamicSwim/HeadCoach/USRPT-as-brand | **No** (trademark/reputation) — use neutral names |
| **Layout/tables** | USMS's "Swim Tracker" table design | **No** |

### 5.2 Fathom session vocabulary (own notation)

**Block types (superset of USMS-A5 and Padlie's 5-block norm):**
`WU` (warm-up) · `PRE` (drill/technique or activation) · `MAIN` (one or two) · `SUPP` (pull/kick/supplementary) · `CD` (cool-down).

**Set atoms:** `{reps, dist_m, stroke ∈ {free, choice, nonfree, im, pull, kick, drill}, effort ∈ {E,S,T,C,F}, interval: {mode: rest|sendoff, value}, equip?[], note_id}`; *effort uses the CSS-offset zones from the prior doc §2.3 — not HR.*

**Intent tags (from USMS-A5/A11):** `warmup, technique, aerobic_base, capacity_rung, rest_shrink, threshold, pacing, test, recovery, breath_control, speed (optional)`.

**Derived time:** `dur = Σ reps × (swim_time + rest)`; or `Σ reps × sendoff` (USMS-A5 formulas). Default swim time = `dist × pace_default × stroke_factor` (library glossary factors: free 0.90, back 1.1, fly/breast 1.2, drill 1.5, kick 2.0) — **replace defaults with athlete's own pace** once known.

**Example (own notation, own text — not a USMS workout):**

```yaml
pattern: AE-A
role: MAIN
intent: [capacity_rung, rest_shrink]
params:
  reps: [6, 12]
  dist_m: 100
  effort: S
  interval: {mode: rest, value_s: [20, 10]}   # shrink across exposures
scale: {by: rung, rule: "reps*dist_m ≈ 0.6-0.9 × next_rung_m"}
prov:
  - {src: USMS-A8, role: idea}            # rest-interval ladder method
  - {src: USMS-P1M, role: shape}          # long-reps with short :05 rest
  - {src: SG-RS, role: corroborates}      # SwimGym rest-shrink recipe (prior doc)
verbatim_copied: false
```

### 5.3 Provenance tag grammar

```
prov entry := {src: <registry id>, role: idea | shape | numeric-fact | corroborates | caution,
               indep: bool, evidence: A|B|C|D, note?: <≤12 words, our paraphrase>}
pattern accepted iff  count(indep && role in {idea, shape, numeric-fact}) ≥ 2   # "rule of two"
```

### 5.4 Clean-room distillation protocol (do this once, with a log)

1. **Read** the source *as a human*; **never paste** source text into the repo or a prompt that will output prose.
2. **Observation log (facts only):** `{src, block, reps×dist, rest/sendoff, intent guess, equipment, total}` in a spreadsheet — data points, not sentences.
3. **Cluster** observations into *families*; drop anything seen in only one source unless it is physiologically principled (note as `single_source`).
4. **Author** patterns from the *family*, not from one workout: choose our own numbers/ranges; add our own cues.
5. **Name** our patterns neutrally (`AE-A…`); no brand words.
6. **Overlap check:** no consecutive run of **> ~8 words** and no *exact multi-set composition* of a single source's workout survives into the pack; scan with a simple n-gram diff against saved source extracts (kept outside the repo).
7. **Register** sources (§8) with access date, license note, and "no text stored" flag.
8. **Coach review (one-time, paid):** a certified masters coach signs off families (prior doc §3.3).
9. **Re-audit** at v1.1.

---

## 6. Legal / ToS caveats (not legal advice)

**Short answers to the brief's questions**

| Question | Answer |
|---|---|
| Can we copy USMS article workouts **verbatim** into Fathom? | **Don't.** The *workout idea/method* is unprotectable, but the *written article* (incl. explanatory notes, layout, selection in a curated page) is protected expression; USMS's own policies say reproduction needs permission and that archives are protected. The verbatim-copy benefit is near zero because our vocabulary needs ~25 families, not copied texts. |
| Can we **distill patterns**? | **Yes.** Copyright doesn't extend to "any idea, procedure, process, system, method of operation, concept, principle" (17 U.S.C. §102(b)). |
| Can we **cite**? | **Yes**, and we should (internal registry; optional "Inspired by public coaching practice" page). Citing ≠ endorsement; don't use USMS marks or imply affiliation. |

**Legal grounding (primary sources)**

- *Bikram's Yoga College of India v. Evolation Yoga* (9th Cir. 2015): a **sequence of 26 poses + breathing exercises** is an idea/process/system for health and **not copyrightable**, even as a "compilation" or "choreographic work"; only the *words and pictures describing it* are protected. https://law.justia.com/cases/federal/appellate-courts/ca9/13-55763/13-55763-2015-10-08.html
- **U.S. Copyright Office**: compilations of exercises are refused registration where order/selection is functional; film/description of a routine may be protected but "not the movements themselves." https://www.federalregister.gov/documents/2012/06/22/2012-15235/registration-of-claims-to-copyright ; Circular 52 lists "general exercise routines… A series of aerobic exercises… A yoga sequence" as non-registrable. https://copyright.gov/circs/circ52.pdf ; Circular 31 (ideas/methods) https://copyright.gov/circs/circ31.pdf
- *Implication:* a swim set like `10×100 @ 15 s rest` and the *shape* of a six-week ladder are functional training methods → low protection. Risk concentrates in **text, distinctive curated selections of text, images, and databases.**

**Paraphrase vs verbatim**

| Use | Risk (qualitative) | Guidance |
|---|---|---|
| Verbatim paste of full workouts/articles | **High** (expression + site/policy reproduction rules) | Don't |
| Verbatim paste of a single short set line (`10 × 100 on 2:00`) | Very low (merger of idea/expression; ubiquitous) | OK, but unnecessary |
| Light paraphrase (swap synonyms) of a workout page | **Medium** (still tracks one author's selection/arrangement/text) | Avoid; use clean-room §5.4 |
| Re-authored parametric pattern from ≥2 sources | **Low** | Target state |
| Aggregate facts (+50 yd/week, 24 workouts/6 weeks) | **Very low** | Cite the source |
| Scraping login-gated pages/PDFs | **Contract/technical** risk even if copyright is thin | Don't; USMS plans are "only accessible to our members" |

**ToS / policy facts I could verify**

- USMS **plans index**: "These plans are only accessible to our members." (https://www.usms.org/fitness-and-training/six-week-swim-training-plans/six-week-swim-training-plan-information)
- USMS **Publishing Policy (2006)**: reproduction subject to copyright and Editorial Committee approval; commercial reproduction needs Executive Committee approval; archives protected. (https://www.usms.org/admin/policies/pubs_policies.pdf)
- USMS **volunteer guidance**: "you always have to get permission from creators… Never copy and publish someone else's written intellectual property." (https://lanemate.usms.org/admin/lmschb/content/newshints)
- USMS **Community rules**: synopsis in own words + link allowed; brief quotes with commentary; no whole articles. (https://community.usms.org/usms-community-faqs/w/faq/8/usms-community-rules)
- **No general website Terms of Use located** (searched; guessed URLs 404). Treat as unknown; do **not** infer permission. A PDF reachable at a public `/-/media/` URL is not a license.
- **Swim Smooth ToS**: "all the copyright and other intellectual property rights… are reserved"; Guru partly patented (GB2014106.5). (https://www.swimsmooth.guru/terms)
- **TrainingPeaks ToS (updated 2026-07-28)**: personal print/download license; **no data mining/robots**; coach plans are per-author. (https://www.trainingpeaks.com/terms-of-use/)
- **MySwimPro / Strava / World Aquatics / USA Swimming**: see prior doc §3.1 (restricted; unchanged).

**Other caveats**
1. **Author vs publisher:** articles are bylined (Goodrich, Donovan, Heggy, Bay, Howley) — rights may be work-for-hire, assigned, or retained; unknown.
2. **Jurisdiction:** UK/AU sources (Swim England, MSA) may carry **database rights** or different moral-rights regimes; our distillation approach (no copying) stays safe, scraping would not.
3. **Distribution vs personal use:** if Fathom is a *private local app*, risk is lower than a published app; still design for the latter.
4. **Trademarks:** don't use "USMS," "U.S. Masters Swimming," "LaneMate," "Swim.com," "Swim Smooth," etc. as product claims ("USMS-approved"). Neutral internal citations are fine.
5. **AI/LLM:** USMS has no published AI-use policy I could find. Don't paste source text into a model to "rewrite"; do the observation-log method. (Contrast: Strava's June-2026 API policy explicitly bars AI use — prior doc.)
6. **Safety/liability:** USMS prints a **breath-hold danger warning** (shallow-water blackout). Fathom should carry the same posture (no breath-hold sets; "stop if unwell"), consistent with prior doc §1's "educational, consult a physician."
7. **Permission is cheap if wanted:** if we ever want to name USMS or lift anything beyond ideas, ask in writing. Their Swim.com deal shows they license; expect a "no" or a fee for content, a "yes" for attribution-only.

---

## 7. Concrete v1 extraction plan — 26 set patterns (+6 modifiers) with provenance

> **Legend.** Source IDs → §8. `role` per §5.3. **All pattern text below is Fathom-authored and parametric.** Prior-doc IDs show reconciliation with `…swim-training-algorithms-datasets.md` §6.5. "Indep" = number of independent sources (rule of two).
> Units: `m` internally; source numbers in yards were converted by 0.9144.

### 7.1 Warm-up / pre-set (5)

| ID | Pattern (parametric) | Intent | Prior ID | Provenance tags (`src:role`) | Indep |
|---|---|---|---|---|---|
| **FP-WU1** | `1× 200–400 E, free/choice` ± a swim/kick/pull triad (`100 each`) | warm-up base | WU1/WU2 | USMS-P500:shape, USMS-A5:idea, IRM-DX:idea (10 min easy, non-free every 4th lap), SE-20:corroborates (warm-up + skill + main + swim down) | 4 |
| **FP-WU2** | `4–6×100 build 1→4, r=15 s` | pre-quality activation | WU3 | USMS-A1:shape (4×75 kick/drill/build), USMS-A4:shape (4×50 build), SG-WU:corroborates (prior doc §2.7) | 3 |
| **FP-WU3** | **Diagnostic 10×100 warm-up** (`S, r=15 s`; note rep at which pace stabilizes) | learn personal warm-up length (feeds modifier M-AGE) | new | USMS-A6:idea (Masters need 4–8 reps), USMS-A7:numeric-fact (warm-up 15–20 min cap) | 2 |
| **FP-PRE1** | `4×50 S + 2×25 build, r=20 s` | proof/test activation | PRE1 | prior doc §6.5 (own), USMS-A9:corroborates (long technique warm-up before tests) | 2 |
| **FP-TK-A** | `6–10×50: 25 drill + 25 swim, r≤15 s` | technique prime | WU4/TK1 | USMS-P500:shape, USMS-A5:idea (drill/technique block), RS-TP:corroborates (Rock Star, prior doc) | 3 |

### 7.2 Technique / skill (3)

| ID | Pattern | Intent | Prior | Provenance | Indep |
|---|---|---|---|---|---|
| **FP-TK-B** | **Weekly drill rotation**: one named drill per week (e.g., kick-board-swim → six-kick-rotation → catch-up) attached to PRE | technique | new | USMS-P500:shape (dedicated drill each week), USMS-A5:idea, CR-DRILL:corroborates (Coach Ray list, prior doc) | 3 |
| **FP-TK-C** | **Stroke-count / distance-per-stroke set**: `4×200 or 8×100 S`, record strokes/length; goal = hold or reduce count | efficiency; fade guard | new | USMS-A2:shape (≤15 strokes/25 yd goal), USMS-P1M:shape (distance-per-stroke 4×200), USMS-A6:idea (cool-down drop-a-stroke) | 3 |
| **FP-TK-D** | **Planned breath-pattern ladder**: `4–8×25/50` alternating every-3/5/7 (or 2/4/6) with **planned count only — never hypoxic** | breath control (capacity-limited athletes) | TK2 variant | USMS-A1:caution+idea, USMS-A4:idea, Reddit-breath (prior doc §4.2):corroborates | 3 |

### 7.3 Endurance / capacity (9)

| ID | Pattern | Intent | Prior | Provenance | Indep |
|---|---|---|---|---|---|
| **FP-AE-A** | **Rest-shrink rep ladder**: same total with reps lengthening (50→100→200→400) and rest shrinking (30→20→10→5 s) across exposures | capacity rung | AE1/AE2/AE6 | USMS-A8:idea, USMS-A9:idea, SG-RS:corroborates, RDT-1je:corroborates | 4 |
| **FP-AE-B** | **Send-off ladder**: `reps×dist on fixed send-off` rising `25→50→100→200→400` with proportional send-off | capacity (steady cadence) | new | USMS-A8:idea (repetition-interval method), USMS-A5:idea (send-off vs rest), USMS-A2:shape (20×50 on fixed send-off) | 3 |
| **FP-AE-C** | **Long-rep block**: `3–5×(0.25–0.5)·R_k S, r 20→10 s` | rung rehearsal | AE2/AE3 | USMS-P500:shape (3–4 reps at 150–250 yd), USMS-P1M:shape, SS-ZONES:corroborates (400s) | 3 |
| **FP-AE-D** | **Closing continuous swim** at current rung `R_k` placed last (or after short PRE) of main block; step `≈ +10 % of D_goal` per week | proof-prep / rung | AE4 | **USMS-P500:numeric-fact (+50 yd/week, 200→500)**, USMS-P1M:shape ("track progress each long continuous swim"), USMS-A8:idea (brute-force +lengths) | 3 |
| **FP-AE-E** | **Stepped continuous ladder with easy 3×50 between** (`0.3,0.4,0.5 × D_goal`), tempo rises with distance | pacing + rung | new (extends AE5) | USMS-P1M:shape (300-400-500 with easy 50s), USMS-A1 #1:idea (pace-lock) | 2 |
| **FP-AE-F** | **Broken continuous with ≤5 s pause for split** (e.g., `R_k` with a read-time pause at midpoint) | proof variant `pass_with_split` | new | USMS-P1M:shape (1,000 with :05 pause to read time) | **1 → flag `single_source`**; physiologically principled |
| **FP-AE-G** | **Descending long set** (`4×R/4 descend 1–4`; or `2× 3×100 descend`) | pacing discipline | AE5 | USMS-A4:shape, USMS-P1M:shape (4×100 descend), TRI-TH:corroborates (Tritheos, prior doc) | 3 |
| **FP-AE-H** | **Pace-lock set**: alternate short reps and one long swim at the *same* pace target (e.g., 100s & a 0.4·R_k swim) | even-pacing skill | CS3 variant | USMS-A1 #1:idea, USMS-A8:idea | 2 |
| **FP-AE-I** | **Pull-aerobic block**: `3–5×(150–300) pull with buoy S` | aerobic volume / breathing rhythm | TK2/AE | USMS-P500:shape (pull blocks in most sessions), SE-20:corroborates, USMS-A5:idea (pull/kick set) | 3 |

### 7.4 Threshold / quality (4)

| ID | Pattern | Intent | Prior | Provenance | Indep |
|---|---|---|---|---|---|
| **FP-CS-A** | **10×100 best-average** at hold-even pace, r=15–20 s | threshold test / T-pace | TST2/CS1 | USMS-A1 #3:idea+numeric-fact (10×100, 15–20 s), USMS-A9:idea (repeat each 4–6 weeks), OS-T10:corroborates (Outdoor Swimmer, prior doc) | 3 |
| **FP-CS-B** | **CSS ladder**: `4×100 + 1×200 | 4×100 + 1×300 | 4×100 + 1×400` at CSS (neutral name) | threshold volume at CSS | CS2 | SS-ZONES:idea (branded name — rename), SS-WU:corroborates (same ladder family in prior doc §2.4) | 1 → keep `single_source` + physiology (CSS volume at threshold, Maglischo) |
| **FP-CS-C** | **Broken target distance**: `D_goal/k × k`, r 10–15 s, at goal pace (e.g., broken 200 = 100 + 2×50 form) | pace proof P1 | CS3 | USMS-A4 #5:idea, USMS-A5:idea (200 broken at 50s), AQ-1500:corroborates (3×500 goal-pace) | 3 |
| **FP-CS-D** | **Repeat-until-miss race-pace block (optional v1.1)**: `reps×25/50 at goal pace`; set ends after 2 consecutive misses | fail rule; race rehearsal | SP1 | USMS-A1 #2:idea, USMS-PTP-2018:idea (fail rules), — | 2 |

### 7.5 Test / proof (2)

| ID | Pattern | Intent | Prior | Provenance | Indep |
|---|---|---|---|---|---|
| **FP-TST-A** | **Repeatable timed benchmark** (continuous 400/800/1000 or `10×100 on fixed send-off`) every 4–6 weeks | monitor fitness; CSS refresh | TST1/PRF1 | USMS-A9:idea+numeric-fact, USMS-A1 #3:idea, SS-CSS:corroborates | 3 |
| **FP-TST-B** | **CSS 400/200 test** (existing) | CSS anchor | TST1 | prior doc §2.2 (A: Wakayoshi/Dekerle), SS-CSS | 2 |

### 7.6 Recovery / cool-down / support (3)

| ID | Pattern | Intent | Prior | Provenance | Indep |
|---|---|---|---|---|---|
| **FP-RC1** | **Mixed kick/drill/swim recovery, no target pace**: cycles of `kick 25–50 · drill 50 · swim 100`, easy | recovery | RC1 | USMS-A1 #5:idea, AQ-REC:corroborates (AquaPlan recovery, prior doc) | 2 |
| **FP-CD1** | `100–300 E any stroke` (default **100 easy** when unspecified) | cool-down | CD1 | USMS-P500:numeric-fact ("cool-down… 100 easy"), USMS-A6:idea, RK-CD:corroborates (Rock Star "≤300 m") | 3 |
| **FP-CD2** | **Hidden cool-down**: final set ascending effort *or* `4×25` dropping one stroke each | CD for time-boxed sessions | new | USMS-A6:idea (both variants) | 1 → `single_source`, low-risk |

### 7.7 Modifiers (6) — not counted as patterns

| ID | Modifier | Provenance |
|---|---|---|
| **M-VOL** | Grow a set by length before count: `10×100 → 10×125` (≈ +25 %), or `8×125` for the same yardage with longer work time | USMS-A7:idea |
| **M-TIME** | Time-box a set: "as many reps as fit in X min" for mixed-speed groups; beginners prescribe *active minutes* not distance | USMS-A5:idea, USMS-A7:idea |
| **M-INJ** | Provide an alternative path per block (e.g., pull-only or kick-free) at authoring time | USMS-A6:idea |
| **M-STROKE** | Per-rep stroke substitution preserving total (`25 fly / 75 free`) — default to free-first for Fathom's population | USMS-A6:idea, USMS-A7:idea; Padlie:numeric-fact (freestyle ≈ 70 % of coach volume) |
| **M-AGE** | Warm-up scale: bias WU +10–15 % when age ≥ ~40 or when FP-WU3 shows ≥ 5 reps to reach pace; cap 15–20 min | USMS-A6:idea, USMS-A7:numeric-fact |
| **M-EQUIP** | Equipment tags (`fins, pull, paddles, board`) as *optional hints*; GT5 can't verify; Padlie: paddles/pull most common | Padlie:numeric-fact, USMS-P500:shape |

### 7.8 What to *not* extract from USMS

- USRPT-heavy, sprint, IM-heavy sets (outside capacity v1; keep CS-D as optional).
- Any set requiring *breath-hold* or "no breath" prescriptions (**safety; excluded**).
- Plan-level calendars as units (USMS plans specify no weekdays).
- Verbatim drill descriptions (use generic drill names + our own 1-line cues).

### 7.9 Coverage check vs prior doc's ~20 patterns

Prior doc's 20 patterns + this plan → **26** patterns: adds `AE-B` (send-off ladder), `AE-E` (stepped continuous ladder), `AE-F` (split-pause proof), `TK-B` (weekly drill), `TK-C` (stroke-count set), `TK-D` (breath ladder), `WU3` (diagnostic), `CD2`, `CS-D` (miss-rule). `SP1` stays optional/out-of-v1 by default.

---

## 8. Source registry (for the rules pack `sources[]`)

| ID | Title / URL | Type | Grade | Access | License note |
|---|---|---|---|---|---|
| **USMS-A1** | Best Workouts for Masters Swimmers — https://www.usms.org/fitness-and-training/articles-and-videos/articles/best-workouts-for-masters-swimmers | article | B | public | © USMS/author; do not copy |
| **USMS-A2** | Best Swimming Workouts for Beginners — …/best-swimming-workouts-for-beginners | article | B | public | © |
| **USMS-A3** | Best 3,000-Yard Swimming Workouts — …/best-3000-yard-swimming-workouts | article | B | public | © |
| **USMS-A4** | Best Sprint Workouts for Swimming Faster — …/best-sprint-workouts-for-swimming-faster | article | B | public | © |
| **USMS-A5** | How to Write a Swimming Workout — …/how-to-write-a-swimming-workout | article | B | public | © |
| **USMS-A6** | Writing Masters Workouts for All Your Swimmers — …/writing-masters-workouts-for-all-your-swimmers | article | B | public | © |
| **USMS-A7** | Simple Ways to Add Volume Productively… — …/simple-ways-to-add-volume-productively-to-your-swimming-workouts | article | B | public | © |
| **USMS-A8** | How to Swim a Mile Nonstop — …/how-to-swim-a-mile-nonstop | article | B | public | © |
| **USMS-A9** | What Coaches Should Do After a Long Layoff — …/what-coaches-should-do-after-a-long-layoff-from-workouts | article | B | public | © |
| **USMS-A10–A14** | Other USMS articles (§2.1) | article | B/C | public | © |
| **USMS-WL** | Workout Library — https://www.usms.org/workout-library | member library | B | member (glossary public) | © / members only |
| **USMS-6W** | Six-Week Plans index — https://www.usms.org/fitness-and-training/six-week-swim-training-plans/six-week-swim-training-plan-information | plan index | B | public index; plans member-only | © |
| **USMS-P500** | 500 Yards Nonstop plan PDF — (URL in §2.3) | plan | B | PDF reachable; member-only per USMS | © USMS/LaneMate; shape-only use |
| **USMS-P1M** | 1-Mile Open-Water plan PDF — (URL in §2.3) | plan | B | PDF reachable; member-only per USMS | © shape-only use |
| **USMS-PTP-2018** | USRPT committee slides — https://www.usms.org/admin/minutes/ptp-2018-5-17-1.pdf | slides | C | public | © |
| **SE-20** | Swim England 20-session plan — https://www.swimming.org/members/swimming-fitness-training-plan/ | plan | B | public lengths list; sessions members-only | © Swim England |
| **SE-TR** | Swim England Masters Training Room — https://www.swimming.org/masters/masters-training-room/training-workouts/ | articles | C | public | © |
| **SW-WOW** | Swim.com Workout of the Week — https://blog.swim.com/workout-of-the-week-rebooted/ | blog | C | public | © Swim.com |
| **MSQ** | Masters Swimming Queensland programs — https://mastersswimmingqld.org.au/coaching/training-programs/ | programs | C | public index | © MSQ/author |
| **SS-ZONES / SS-CSS / SS-WU** | Swim Smooth blog posts (prior doc §2.3–2.4) | blog | B/C | public (some paid) | © Swim Smooth; ToS reserved |
| **TP-MASTERS** | TrainingPeaks Masters 12-wk plan page — https://www.trainingpeaks.com/training-plans/other/swimming/tp-155922/masters-swim-training-6-workouts-1-drill-session-per-week | plan description | C | public description | © author; ToS no mining |
| **PADLIE** | https://padlie.com/en/swim-training-study | aggregates | C | public; **reuse with link** | Reuse permitted with attribution |
| **IRM-DX** | https://www.ironman.com/news/endurance-swim-workouts | article | C | public | © |
| **AQ-*, RS-TP, CR-DRILL, SG-RS, RDT-1je, OS-T10, TRI-TH, RK-CD** | See prior doc §8 | blog/forum | C | public | © |
| **LEGAL-BIKRAM** | https://law.justia.com/cases/federal/appellate-courts/ca9/13-55763/13-55763-2015-10-08.html | case | A | public | public record |
| **LEGAL-CO** | https://www.federalregister.gov/documents/2012/06/22/2012-15235/registration-of-claims-to-copyright ; https://copyright.gov/circs/circ52.pdf | agency | A | public | public record |
| **SCHEMA-swiML** | https://github.com/bartneck/swiML | schema | — | MIT | MIT |
| **SCHEMA-swim-sets** | https://github.com/eriktaubeneck/swim-sets/ | schema | — | MIT | MIT |
| **DIR-swimming-resources** | https://huggingface.co/datasets/t22000t/swimming-resources | directory | — | CC-BY-4.0 | attribute |

---

## 9. Risks, unknowns, and next steps

| Item | Status / next step |
|---|---|
| USMS website ToS not located | Open-question email to USMS: *ToS? attribution-only permission? interest in content license?* Don't block v1 on a reply. |
| 750/1,000/1,650 nonstop plans not read | **Optional $75 membership + one afternoon**: log weekly longest-continuous, sessions/week, session totals only; update §4 rows 2–5. Re-confirm member terms first. |
| Single-source flags (AE-F, CS-B, CD2) | Keep but mark `single_source`; fine because principled or low-risk; upgrade if the member plans corroborate. |
| Yard→meter rounding | Always compute in m internally; show `source_unit` in registry. |
| Author unknown / mixed copyright | Treat all non-open sources as © reserved; rely on §102(b) + clean-room. |
| Padlie bias (clubs, France) | Use for bounds (session size, blocks), not for prescription. |
| Pattern count creep | v1 cap = 26; new patterns need two independent sources or a physiology citation. |
| Re-check cadence | Re-run source scan at v1.1 (~6 months); watch USMS plan page (35 → more) and any USMS data/API announcement. |

**Concrete actions (ordered):**
1. Adopt §5.4 protocol + §5.3 provenance grammar in the rules-pack repo (`sources[]` from §8).
2. Author the 26 patterns + 6 modifiers (§7) in Fathom's own words; golden-test the generator with the prior doc's six fixtures.
3. Amend the prior doc per §4 rows 1–5, 6, 7, 11, 12 (small edits; no change to architecture).
4. (Optional) $75 USMS membership → aggregate-only log of the three missing nonstop plans.
5. (Optional) Email USMS for attribution/content permission; one-time coach review of pattern families.

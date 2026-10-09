---
date: 2026-10-09
topic: pool-swim-programs-fathom-data-inventory
status: draft
origin: Programs brainstorm research follow-up #2 (Fathom data inventory for baseline / adherence / proofs)
related:
  - docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md
  - docs/brainstorms/2026-10-08-pool-swim-detail-redesign-requirements.md
  - docs/architecture/swim-session-insight-contract.md
  - docs/plans/2026-10-09-001-feat-pool-swim-detail-redesign-plan.md
  - docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md
  - docs/brainstorms/2026-08-20-recovery-v1-timing-hooper-requirements.md
informs: R4–R7 (baseline), R17–R18 (soft-warn), R23–R24 (proof / adherence evidence)
scope: read-only inventory of what Fathom (this repo) already stores and computes. Not a design, not a plan. Thresholds are deliberately NOT chosen here.
---

# Fathom data that Programs can consume

## 0. How to read this

**Code state inspected:** branch `feat/pool-swim-programs-brainstorm` at `5261f23` (merge of PR #14, pool-swim-detail-redesign). `git log main..HEAD` is empty, so this is `main`. Everything marked ✅ was read in `lib/` or `android/` on that commit.

| Tag | Meaning |
| --- | --- |
| ✅ | Verified in code on `main` (file:line cited) |
| 🟡 | Exists, with a caveat that changes how Programs may use it |
| ❌ | Not present in the repo (a gap) |
| 🌿 | Exists only on an **unmerged** branch |
| 📄 | Doc-only claim; not confirmed in code |
| 🧪 | Observed in local sync log `lib/sync_logs.txt` (**untracked** dev artifact, 2026-07-19 → 2026-09-19, ~65 workouts). Shape evidence only; do not treat as a fixture. |

**Honesty rules inherited from the product** (`docs/architecture/swim-session-insight-contract.md`, Home/Hooper locks): omit over invent; null ≠ 0; no quality / readiness / 0–100 scores; no hard/easy/rest coaching (Recovery v1 lock). The inventory is organised so Programs can keep those rules.

---

## 1. Executive summary

1. **Pool-swim history is lap-grain, not set-grain.** Each synced pool swim becomes a `CanonicalSwimSession` with total distance/duration, pool length, and ordered lap rows (distance, duration, strokes, SWOLF, pace, stroke style). It has **no per-lap timestamps and no rest rows**. "Continuous", "main set 4×200", "time-bounded 12-minute distance", and "warm-up vs proof effort inside one workout" cannot be *proven* from stored data — only approximated from totals.
2. **`SwimSessionInsight` is a good *read* seam for verdict + tip + chips, but a poor *numeric evidence* source.** KPIs are partly pre-formatted strings, it is only assembled inside a Flutter widget, and it intentionally omits Totals-only HR. Programs should read `CanonicalSwimSession` / lap list for numbers and the insight only for athlete-facing story/tip. The contract says Programs "may later **read** this assembler's output; do not invent a parallel insight pipeline."
3. **In-session swim HR is real but fragile.** It exists only when a 7-byte HR stream locks against Totals min/max. `p0.hrCoverage` is **not** a reliable "HR available" flag (the log shows native `sampleCount=0` on swims whose HR still locks).
4. **Soft-warn has raw data but no ready signal.** Sport types, per-session load / TE / recovery-minutes, sleep, and a one-tap feel answer exist. There is **no weekly/acute load aggregate, no "other-load" function, and no soft-warn code** in `lib/` (the only `softWarn*` symbols are export file-size thresholds). **Badminton is not a known sport type anywhere in the repo.**
5. **Hooper-4 is NOT on `main`.** `main` has a single 5-option emoji "feel on wake" string. The 1–7 four-item `MorningWellness` model lives only on unmerged `feat/hooper4-morning-wellness` 🌿.
6. **Sleep/recovery data is stronger than older docs say.** TruSleep SEQUENCE_DATA (score, HRV, avg/min/max HR, SpO₂, breath rate, efficiency, latency, deep-part, bed/asleep/wake/rise times) ships on `main`, contradicting the 2026-08-20 handoff's "HRV absent" lock (which predates `POC-2026-09-12-seq-dict`).
7. **Biggest Programs-critical gaps** (full register in §10): continuous-distance proof, time-bounded proof, set structure, workout↔prescription identity, same-day multi-swim disambiguation, "sufficient history" thresholds, Programs-owned persistence/Forget semantics, and a non-widget composition function for insight + HR lock.

---

## 2. Data flow and storage

```
Watch GT5-A07 ─Huawei BR─> HuaweiWorkoutSync.kt
   Totals TLV (0x17:0x08) · swim segments (0x17:0x0e) · data pages (0x17:0x0a)
        │
        ▼
WorkoutSummary  (lib/core/huawei/huawei_link.dart:1872)   prefs `workouts_json`
   ├─ segments: List<WorkoutSegment> (huawei_link.dart:1812)
   ├─ data pages ─ side-files `workouts/data_pages` (RunSessionStore.loadDataPages)
        ▼
CanonicalSwimSession.fromWorkoutSummary (canonical_swim_session.dart:77)
   side-file `workouts/canonical_swim/swim_<n>.json`
        ▼
SwimP0Metrics (swim_p0_metrics.dart:60) → analyzeSwimSession → diagnoseSwimSessions → buildSwimSessionInsight
```

| Store | Key / path | Writer | Notes |
| --- | --- | --- | --- |
| All workouts, every sport | prefs `workouts_json` (`lib/features/device_pairing/domain/gate_a_prefs.dart:23`) | `_mergeAndPersist` (`lib/features/workout_history/data/repositories/workout_history_repository_impl.dart:636`) | Read newest-first (`:92`). **Identity = `number` + `startTime`**: same number with a new `startTime` is a different session (prior scalars not merged). |
| Canonical swims | `workouts/canonical_swim/swim_<n>.json` (`GateAPrefs.canonicalSwimDir`) | `_swimStore.saveAll` (`:742`) | A Totals-only re-pull cannot overwrite a richer lap file (`_swimIncomingThinner`, `:958`). |
| HR / data pages | `workouts/data_pages` via `RunSessionStore.loadDataPages(n)` (`lib/features/workout_history/data/run_session_store.dart:56`) | native peel → `_persistPeeledSideFiles` | Enrichment-monotonic; never replaced by a sparser payload. |
| Sleep sessions | prefs `sleep_sessions_json`; stages `vitals/sleep_stages`; TruSleep summary in enrich side-files | `VitalsRepositoryImpl` | See §7. |
| Daily HR | prefs `daily_hr_json` + series `vitals/hr_series/<yyyy-MM-dd>.json` | same | See §7. |
| Feel on wake | prefs `sleep_feel_on_wake_json` (`gate_a_prefs.dart:41`) | `saveFeelOnWake` (`lib/features/vitals/data/repositories/vitals_repository_impl.dart:223`) | One string per sleep `mergeKey`; write-once. |

**Access via DI (`sl<>()`; `lib/core/di/injector.dart`).** `WorkoutHistoryRepository` (`lib/features/workout_history/domain/repositories/workout_history_repository.dart`):

- `loadLocal()` :9 — every workout, all types. ✅ **Only way to see non-swim sessions for soft-warn.**
- `loadAllCanonicalSwims()` :32 — pool **and** open-water; rebuilds from summaries when the side-file is missing (impl `:199`).
- `loadCanonicalSwim(n)` :26 · `canonicalSwimFromSummary(w)` :29.
- `loadSwimDiagnosisReport({focusWorkoutNumber})` :35 — session diagnoses for the focus + trends over **all** canonical swims (pool and OW mixed, any pool length — see G11).
- `isSyncOrMergeInFlight` :15 — Programs should not score adherence mid-merge.
- `clearLocal()` :23 — Forget wipe; Programs state needs an explicit Forget policy (G13).

**Sync reach / retention (matters for baseline):**
- Cold start window = 14 days (`HuaweiLink.activityWindowDays`, `lib/core/huawei/huawei_link.dart:41`; `coldStartWindowDays`, `workout_history_repository_impl.dart:62`). Delta start = `lastSyncCursor − 86400 s` (`:59`).
- One-shot full-history Count from 2022-06-10 (`fullHistoryStartUnix`, `:79`) fires when `currentRunSessionParserVersion` (`:76`, = 4) bumps. Whether older sessions are still on the watch is not guaranteed.
- 🧪 On this device: pool swims run #6 (2026-07-19) → #67; ~**31 pool swims in ~3 months**, 1 open-water (#27, type 8). Sessions after 2026-09-19 are absent from the snapshot.
- Completion evidence is only visible **after a Sync** (Home tracks `home_last_sync_at_ms`, `GateAPrefs.homeLastSyncAtMs`).

---

## 3. Pool swim — verified fields

### 3.1 Session level (`WorkoutSummary` → `CanonicalSwimSession`)

Native Totals parse: `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiWorkoutSync.kt:750-800`. Dart model: `lib/core/huawei/huawei_link.dart:1872`.

| Programs need | Field | Type / unit | Wire tag | Status | Caveat |
| --- | --- | --- | --- | --- | --- |
| Identity | `number`, `startTime`, `endTime` | int, **unix s UTC** | `0x02` `0x04` `0x05` | ✅ | Key on `(number, startTime)`. Derive local day with `.toLocal()` (Home does this: `_localDayKey`, `lib/features/home/data/repositories/home_repository_impl.dart`). |
| Sport type | `type` (+ `observedType`) | int | `0x14` (`HuaweiWorkoutSync.kt:759`) | ✅ | Pool = **6**, open water = **8** (`isSwimWorkout`, `lib/features/workout_history/presentation/view/workout_history_formatters.dart:21`). Pool frozen from an N=1 owner probe (`docs/catalogs/gt5-a07-full-metrics.md` type-freeze table). |
| Total distance | `distanceM` | int m | `0x07` | ✅ | Totals value. The insight KPI prefers the **lap-sum** instead (`swim_session_insight.dart:390`) — see G6. |
| Wall duration | `durationSec` | int s | `0x12` / `0x09`, fallback `end−start` | ✅ | Includes rest. 🧪 pool sessions 809–5734 s (median 3298 s). |
| Moving duration | derived `Σ lap.durationSec` | s | segments | 🟡 | Rest = `durationSec − moving` is **derived, not watch-reported**. Insight only shows moving when `0 < moving ≤ duration`. |
| Pool length | `poolLength` (cm) → `poolLengthM` | m | `0x18` | ✅ | `poolLengthCmToMeters` (`swim_p0_metrics.dart:229`): ≥100 → ÷100, else assumed already metres. Native `unitType` is read but **dropped** (`parseNestedSwimLap`, `HuaweiWorkoutSync.kt:924`), so yard pools are indistinguishable. |
| Watch length count | `laps` → `p0.reportedLaps` | int | `0x19` | ✅ | Can exceed parsed rows → `lengthCoveragePartial`. |
| Parsed lap rows | `p0.lapCount`, `p0.laps` | int / list | swim segments | ✅ | 🧪 5–40 rows per pool swim (median 20; `swim-style-outcome … laps=N`). |
| Total strokes | `strokes` → `p0.totalStrokes` | int | `0x16` | ✅ | Falls back to Σ lap strokes. |
| Stroke rate | `strokeRate` → `p0.strokeRatePerMin` | spm | `0x17` | ✅ | Derived `strokes*60/seconds` when absent. |
| Session SWOLF | `avgSwolf` → `p0.avgSwolf` | int | `0x1a` | ✅ | Insight KPI recomputes the mean of guarded lap SWOLFs when available. |
| Session pace | `p0.avgPaceSecPer100m` | int s/100 m, **floor** division | derived | 🟡 | Includes rest. |
| Moving pace | `p0.movingAvgPaceSecPer100m` | int s/100 m | Σ dur / Σ dist | ✅ | Excludes rest; undercounts if rows are partial. |
| Swim type | `swimType` | int | `0x15` | 🟡 | Session-level Medley mapping deferred (runbook verdict). |
| Calories | `calories` | int | `0x06` | ✅ | |
| HR min / max / peak | `hrMin`, `hrMax`, `hrPeak` | bpm | `0x0c` | ✅ | Totals only; **does not** produce an HR KPI by itself (see §3.5). |
| Load / TE / recovery | `load`, `aerobicEffect`, `anaerobicEffect`, `recoveryTime`, `trainingPoints` | ints; `recoveryTime` = **minutes**; TE wire value = TE × 10 (run/swim UI divides by 10) | `0x0d` `0x0e` `0x20` `0x11` `0x63` (`HuaweiWorkoutSync.kt:772-780`) | 🟡 | Parsed for **all** types. Whether the watch sends them on pool swims is **unverified** — `docs/brainstorms/2026-09-12-home-today-instrument-requirements.md:157` still lists it open. |

### 3.2 Lap / interval rows (`SwimLapMetrics`, `lib/features/workout_history/domain/swim_p0_metrics.dart:17`)

| Field | Type | Wire | Notes |
| --- | --- | --- | --- |
| `index` | int | `0x09` (−1 when ≥1) | Sort key. |
| `distanceM` | int? | `0x04` | Row distance. |
| `durationSec` | int? | `0x0d` | Row time, **not** a wall-clock offset. |
| `strokes` | int? | `0x0b` | |
| `swolf` | int? | `0x0c` | Watch value per row. |
| `paceSecPer100m` | int? | `0x06`, else `dur*100/dist` (`HuaweiWorkoutSync.kt:963`) | Wire pace wins over computed. |
| `style` | int? | `0x0a` | `1` Breaststroke · `2` Freestyle · `3` Butterfly · `4` Backstroke · `5` Medley; unknown → `Stroke N`; null → `"null"` (`lib/features/workout_history/domain/swim_stroke_label.dart:6,18`). Canonical build uses `s.style ?? s.swimType`. |

**Verified absences on a lap row (hard limits for proof / set matching):**
- ❌ No start offset or timestamp; wire `0x07` pointIndex is ignored (`HuaweiWorkoutSync.kt:~942`). Rest gaps between rows are **not locatable** — only total rest is derivable.
- ❌ No rest rows, no set / rep / interval-number concept from the watch.
- ❌ No equipment / drill / kick flag.
- 🟡 **Row = length or interval?** Still open: `lengthCoveragePartial` (`computeSwimP0`, `swim_p0_metrics.dart:133`), `length_semantics_open` diagnosis, and `docs/plans/2026-07-23-001-product-roadmap-swim-bible-v0.md:70` ("Length-vs-interval still pending owner controlled probe"). The in-app rec `log_another_session` (continuous freestyle, counted lengths, minimal floating — `swim_recommendations.dart`) exists to close this.
- 🧪 Row counts × 25 m are *consistent with* rows ≈ lengths, but that is inference, not proof.

### 3.3 Derived analytics already computed (pure domain, `lib/features/workout_history/domain/`)

| Output | Function | Rule | Programs relevance |
| --- | --- | --- | --- |
| Pace decay % (2nd half vs 1st half) | `analyzeSwimSession` (`swim_session_analytics.dart:73`) | ≥2 paced rows | Efficiency scorecard input |
| Pace CV % | same | σ/μ of row pace | Pacing consistency scorecard |
| SWOLF delta (last − first) | same | ≥2 SWOLF rows | Efficiency scorecard |
| Strokes / 25 m per row | `SwimIntervalEfficiency.strokesPer25m` | `strokes*25/distanceM` | Normalised to **25 m**, not pool length |
| Confidence | `_baseConfidence` (`swim_session_analytics.dart:150`) | ≥6 paced rows & not partial → high; ≥4 → med; else low; partial → med | Existing numeric precedent for R7 "insufficient history" |
| Session diagnoses | `diagnoseSwimSessions` (`swim_trends_diagnosis.dart:148`) | ids: `fatigue_onset`, `pacing_uneven`, `pacing_steady`, `efficiency_decline`, `efficiency_improve`, `length_semantics_open`, `insufficient_intervals`, `no_strong_signal` | Reusable for chore feedback |
| Trends | `buildSwimTrends` (`:83`) | earliest→latest pace/SWOLF/volume deltas, totals | 🟡 mixes OW + all pool lengths; insight deliberately **does not** use these deltas for chips |
| Invent-guard | `filterSwimLapsForAnalytics` (`swim_invent_guard.dart:54`, `_classify` `:103`) | hides rows `<40%` of pool length, absurd strokes/duration outliers | Any Programs lap math should run on guarded laps or state otherwise |
| Allow-listed recs | `kSwimRecCatalog` (`swim_recommendations.dart:33`) | 8 ids | Next-session cue vocabulary |

### 3.4 Warm-up / main / cool "sets" (do not mistake for structure)

`buildSwimIntervalSets` (`lib/features/workout_history/presentation/widgets/swim_interval_sets.dart:31`) groups laps **positionally**: ≤4 rows → one "Main"; ≤24 → warm-up = `max(2, ⌊20%⌋)`, cool = `max(2, ⌊15%⌋)`, rest main; >24 → four equal-ish blocks. It is a **presentation heuristic** (`SwimSetKind`, `:25`), not athlete- or watch-declared structure, and lives in a widget file. Programs must not use it to claim "main set completed".

### 3.5 Heart rate on a pool swim (three different things)

| Signal | Where | Status | Rule |
| --- | --- | --- | --- |
| Totals min / max / peak | `WorkoutSummary.hrMin/hrMax/hrPeak` | ✅ | Always-on when watch sends `0x0c`. Not average. |
| In-session HR stream (locked) | `lockInSessionHrPoints` (`lib/features/workout_history/domain/in_session_hr_lock.dart:17`), swim decoder `decodeSwimSevenByteHrPoints` (`:86`) | ✅ 🟡 | Pages must concatenate to `0x05` bodies, length ≥14 and `% 7 == 0`; bytes 1/3/5 of each record must be 0; series min/max must agree with Totals `hrMin`/`hrMax` within 1 bpm; ≥2 in-band samples. Failure → empty (omit). ~5 s cadence, **no timestamps beyond offset = index×5 s**. |
| Avg / max HR KPI | `SwimLockedHrKpis` (`swim_session_insight.dart:101`) | 🟡 | **Computed in a widget** (`_kpisFromHrPoints`, `lib/features/workout_history/presentation/widgets/swim_session_coaching_fold.dart:174`) as mean of in-band samples (≥2). Not callable from domain. |
| `p0.hrCoverage` | `_hrCoverage` (`swim_p0_metrics.dart:196`) | 🟡 | Derived from native `sampleCount` (>0 → `present`) else Totals HR → `partial`. 🧪 log: swim #67 `sampleCount=0 … dataPages=14 persisted=true`, so coverage reads `partial` even when the stream locks. **Do not use as the HR-available flag.** |

Honesty rule to carry forward: *"Watch totals alone never promote HR"* (`docs/plans/2026-10-09-001-feat-pool-swim-detail-redesign-plan.md:126`; contract table row `kpis`).

---

## 4. `SwimSessionInsight` — the existing seam, as it actually is

Source: `lib/features/workout_history/domain/swim_session_insight.dart` · contract note: `docs/architecture/swim-session-insight-contract.md`.

```text
buildSwimSessionInsight({           // :132
  required CanonicalSwimSession focus,
  required List<SwimLapMetrics> inventGuardedLaps,
  required List<SwimDiagnosis> sessionDiagnoses,   // session only; trend_* ignored for tip
  required List<CanonicalSwimSession> recentHistory,
  SwimLockedHrKpis? lockedHr,
}) → SwimSessionInsight { story, storyDiagnosisId?, chips[0..3], primaryTip?, kpis, secondaryFindings }
```

| Field | Verified behaviour | Consumable by Programs as… | Limits |
| --- | --- | --- | --- |
| `story` | Always non-empty; coverage-honest copy when tipless. Catalog in `_athleteStoryCopy` (`:206`) | Chore feedback copy | Pure prose; no machine fields beyond `storyDiagnosisId`. |
| `storyDiagnosisId` / `primaryTip.sourceDiagnosisId` | Same winning *session* diagnosis; priority `fatigue_onset` 0 → `efficiency_decline` 1 → `pacing_uneven` 2 → `pacing_steady` 3 → `efficiency_improve` 4 (`kSwimTipDiagnosisPriority`, `:116`); coverage-only ids never win (`:109`) | A **stable machine key** for adherence/adaptation rules | Ids are internal but stable; no versioning. |
| `primaryTip` | `{recId, title, why, sourceDiagnosisId}` from `kSwimRecCatalog` | "Next cue" on a chore | Null → empty-tip escape. |
| `chips` | 0–3 of Pace / SWOLF / Volume vs **prior comparable** pool swim (type 6, same `poolLengthM`, within last `kSwimChipLookbackPoolSessions = 10`, `:125`); omitted for open water, missing pool length, or thin history | Habit/efficiency scorecards (relative) | `deltaLabel` is a **formatted string** (`'+3s/100'`), direction enum only; not numeric. |
| `kpis` | `SwimSessionKpis` (`:80`): `distanceM` (lap-sum else Totals), `durationPrimaryLabel` + `durationHint` (**strings**, moving `m:ss` + "swim · rest"), `avgPaceSecPer100m` (mean of guarded lap paces), `avgSwolf`, `avgHr/maxHr` (only if lock passed) | Distance, avg pace, SWOLF | Duration is **string-only**; pace is **unweighted mean of row paces**, which can differ from `p0.movingAvgPaceSecPer100m`. |
| `secondaryFindings` | Other session diagnoses; coverage-only ids dropped | Optional | |

Tests: `test/features/workout_history/swim_session_insight_test.dart` (9 cases: tip priority, escape story, thin history, mid-history focus, moving-vs-duration, type-8, HR omit, banned vocabulary).

**Contract non-goals that Programs must respect or consciously amend** (`swim-session-insight-contract.md`): no second Programs-facing DTO or versioned API (this cut), no quality/readiness/0–100 scores, dig-deeper prefs and orientation never enter the builder, open-water narratives may defer.

**How the insight is composed today (the real seam):** `_load()` in `swim_session_coaching_fold.dart:84` — `CanonicalSwimSession.fromWorkoutSummary` → `loadSwimDiagnosisReport(focus)` → `loadAllCanonicalSwims()` → `_resolveHrPoints()` (`:144`; `loadDataPages` → `lockInSessionHrPoints` with `observedType ?? type`) → `filterSwimLapsForAnalytics(includeFiltered:false)` → `buildSwimSessionInsight` (`:127`). There is no domain use-case wrapping this (G9).

---

## 5. Sport types (for soft-warn)

Single source of labels: `kWorkoutTypeLabels` (`lib/features/workout_history/presentation/view/workout_history_formatters.dart:4`). Unknown → `workoutTypeLabel` returns `'Workout type $type'` (`:18`).

| Wire `type` | Label | Helper | Evidence of real data |
| ---: | --- | --- | --- |
| 1 | Walk | `isRunWorkout`, `isOutdoorLandWorkout` | 🧪 5 sessions (742–2624 s) |
| 2 | Run | same; `isOutdoorRunWorkout` | 🧪 2 sessions |
| 3 | Cycle | — | none seen |
| 4 | Climb | — | none seen |
| 5 | Indoor run | `isRunWorkout` | 🧪 6 sessions, 433–693 s; **each starts 64–339 s after a Strength (140) row ends** |
| 6 | Pool swim | `isSwimWorkout` | 🧪 29 in log (+#6, #7 via style log) |
| 7 | Indoor cycle | — | none seen |
| 8 | Open water | `isSwimWorkout` | 🧪 1 (#27, 3990 s) — contradicts catalog "deferred / unobserved" |
| 9 | Elliptical | — | none seen |
| 10 | Rower | — | none seen |
| 140 | Strength | `isStrengthWorkout` | 🧪 21 sessions |
| **129** | *(no label → "Workout type 129")* | — | 🧪 1 session (#17, 732 s, `data=1 pace=0 seg=0`, same day as pool swims #18/#19). **Unknown sport; not confirmed to be anything.** |
| *badminton* | **not defined** | — | ❌ no occurrence of "badminton" in `lib/`, `android/`, or any doc except the Programs requirements (R17) |

Caveats:
- 🟡 The labels are **non-authoritative**: the catalog notes FOS-UI vs Gadgetbridge enum conflicts (walk/run swap) and says to freeze only after N≥2 observations or a UI cross-check. Only Strength (140) and Pool (6) have an explicit freeze row (`docs/catalogs/gt5-a07-full-metrics.md`).
- 🟡 The Workouts tab only surfaces swim / run-walk / strength (`WorkoutSportTab`, `lib/features/workout_history/presentation/widgets/sport_tabs.dart:4`; filters at `workout_history_screen.dart:354-379`). Types like 129 appear in `loadLocal()` and in Home's *today* list but in **no** Workouts tab.
- 🧪 Multi-sport load is real in the data: **13 of 43** session-days in the log contain a swim plus another type; **9** contain swim + strength on the same local day.
- Implication for R17: "badminton" will arrive as an arbitrary numeric type the watch assigns. Programs cannot name-match it; it needs either an owner-confirmed type id or a generic "any non-swim session" rule.

### 5.1 Per-session load signals available for non-swim sports

| Signal | Field | Units | Notes |
| --- | --- | --- | --- |
| Watch training load | `WorkoutSummary.load` | int (watch scale, no unit doc) | Strength: promoted from leftovers if missing (`promoteStrengthScalarsFromLeftovers`, `lib/features/workout_history/domain/strength_session_metrics.dart:102`). Other types: Totals scalar only if sent. |
| Aerobic / anaerobic effect | `aerobicEffect`, `anaerobicEffect` | wire value = TE × 10 for run/swim/other (`_teFromTotalsWire`, ÷10 in UI); Home shows the **raw** value for strength labelled "Intensity" | Inconsistent scaling by sport in `buildHomeTodaySessionCard` (`home_repository_impl.dart:283`). |
| Recovery time | `recoveryTime` | **minutes** (`formatRecoveryMinutes`, `strength_session_metrics.dart:86`; run converts to `recoverySec = min*60`, `run_session_metrics.dart:95`) | Ready-made "watch says recovered at `endTime + recoveryTime*60`" — if present. Presence per sport unverified. |
| Duration / calories | `durationSec`, `calories` | s / kcal | Always available (Totals). Safe lowest-common-denominator soft-warn input. |
| Run extras | `RunSessionMetrics` (`lib/features/workout_history/domain/run_session_metrics.dart:10`) | zones, cadence, TE, load, recovery | Outdoor/Indoor run only. |
| Recent strength loads | `recentStrengthLoads` (`strength_session_metrics.dart:219`) | chronological ≤8 | The only existing load-history helper; strength-only. |

❌ **No aggregate exists**: no acute/chronic load, no weekly volume across sports, no "hours since last hard session". Home explicitly calls itself an "instrument only … not a planner" (`docs/brainstorms/2026-09-12-home-today-instrument-requirements.md:11`).

---

## 6. Recovery signals: sleep, HR, feel

### 6.1 Sleep (shipped on `main`)

Repository: `VitalsRepository` (`lib/features/vitals/domain/repositories/vitals_repository.dart`).

| Need | API | Model | Status |
| --- | --- | --- | --- |
| Sleep sessions (begin/end, stages) | `loadSleepSessions()` | `SleepSessionSummary` (`huawei_link.dart:864`): `beginUnix`, `endUnix`, `wireType`, `stages`, `durationSec`, `mergeKey = begin:end:wireType` | ✅ Display SoT = TruSleep file intervals gap-merged ≤180 s (`lib/features/vitals/domain/trusleep_sleep_sot.dart`). |
| Stage minutes | `loadSleepStages(session)` → `stageMinutesOf` (`lib/features/vitals/domain/sleep_analytics.dart:239`) | light / deep / REM / awake minutes | ✅ |
| TruSleep summary | `loadTruSleepSummary(session)` (`:36`) | `TruSleepSequenceSession` (`huawei_link.dart:1331`): `sleepScore`, `avgHrv`, `avgHeartRate`, `minHeartRate`, `maxHeartRate`, `avgBreathRate`, `avgOxygenSaturation`, `sleepEfficiency`, `sleepLatencySec`, `deepPart`, `bedTimeUnix`, `fallAsleepUnix`, `wakeupUnix`, `risingUnix`, `productStages` | ✅ Guards: `isScientific` (`score > 0`), `usableEfficiency` (0–100; naps emit 255), `usableDeepPart`, `usableLatencySec` (≤3 h). |
| 7-day trend band | `buildSleepTrendBand` (`sleep_analytics.dart:114`) over `recentOvernightSessions` (`:29`, midnight-crossing sessions only) | `SleepTrendBand`: mean and ½-SD for score and HRV | ✅ needs ≥2 points. A ready baseline-style comparison for sleep score / HRV. |
| "Today's" sleep | `todaysSleepSession` (`lib/features/vitals/presentation/widgets/sleep_formatters.dart:86`), `sleepCrossesLocalMidnight` (`:74`) | — | 🟡 Lives in a **presentation** file. |
| Sleep-window HR | `loadSleepHrWindow(begin,end)` (`vitals_repository.dart:27`), `windowSleepHrSamples`, `sleepHrStats` (`lib/features/vitals/domain/sleep_hr_window.dart`) | per-minute `DailyHrSample` | ✅ From daily interval HR, **not** overnight summary. |

Retention: activity Sync window is 14 days per pass (`HuaweiLink.activityWindowDays`, `huawei_link.dart:41`); persisted merges accumulate, but no documented retention cap or backfill beyond what was synced.

📄 **Doc drift to resolve before Programs cites "HRV is absent":** `docs/handoffs/2026-08-20-recovery-v1-timing-hooper-handoff.md` and catalog row S6 (`docs/catalogs/gt5-a07-full-metrics.md`) say overnight HRV/RR/SpO₂/avg-HR are companion-ABSENT; catalog row S4 and code (`sleep_detail_screen.dart` shows "Sleep HRV … Overnight average"; `TruSleepSequenceSession.avgHrv`) show them **present** via `capture:POC-2026-09-12-seq-dict`. Code is the truth.

### 6.2 Daily HR

| Item | API | Model | Notes |
| --- | --- | --- | --- |
| Per-day min/avg/max | `loadDailyHr()` (`vitals_repository.dart:20`) | `DailyHrDaySummary` (`huawei_link.dart:944`: `dayKey`, `minBpm`, `avgBpm`, `maxBpm`, `sampleCount`) | ✅ Interval-proxy HR (catalog S5: "diagnostic only"). |
| Per-minute series | `loadDailyHrSeries(dayKey)` | `DailyHrSample` (`:921`) | ✅ **Never merge workout-sample HR into this** (catalog rule). |
| Resting HR history | — | — | ❌ catalog S5 score 1, `unobserved`. A per-day **min** is not resting HR; Programs must not label it so. |
| Day energy / steps | `loadFitnessTotals()` (`:53`) | `FitnessTotalsDay` (`huawei_link.dart:983`) | 🟡 Under-counts vs watch Activity; Home adds session totals on top (`_homeDayTotal`). Its `exerciseDurationSec` is **not** exercise minutes. |

### 6.3 Subjective feel — what `main` has vs the Hooper-4 branch

| | `main` ✅ | `feat/hooper4-morning-wellness` 🌿 |
| --- | --- | --- |
| Model | `String` key ∈ `awful, meh, okay, good, great` (`_FeelOnWakeSurvey._options`, `lib/features/vitals/presentation/view/sleep_tab_screen.dart:~522`) | `MorningWellness` (`lib/features/vitals/domain/morning_wellness.dart` on branch): `sleepQuality`, `fatigue`, `soreness`, `stress`, each **1–7 with 1 = best / 7 = worst**, `answeredAt`, `schema = 2`; `isComplete` requires all four |
| API | `loadFeelOnWake(session)` → `String?` (`vitals_repository.dart:41`); `saveFeelOnWake` (`:44`, write-once) | `loadMorningWellness(session)` → `MorningWellness?`; `saveMorningWellness` (replaces the string API; legacy strings parse as *incomplete*) |
| Key | sleep `mergeKey` | same |
| Trigger | Overnight (midnight-crossing) session, once per key | Same; branch commit also fixed "today's hero, not only midnight-cross" (`254a719`) |
| Consumers today | Sleep tab, Home `sleepFeelCue` (`home_repository_impl.dart:119`) | Branch also rewrites Home/vitals tests |
| Merge state | on `main` | **Not in `main`**; 3 commits ahead of merge-base `3d213af`; worktree `.worktrees/feat/hooper4-morning-wellness` at `254a719`; remote `origin/feat/hooper4-morning-wellness` exists |
| Privacy | prefs only | `sentry_privacy_scrub` updated; `toString` redacted |

**Consequences for Programs**
- Do not write against `MorningWellness` until the branch merges; a Programs build on `main` today can only see the 5-level string.
- Hooper doc locks (`docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md` R7–R8; `2026-08-20…-handoff.md` "Product locks"): **no hard/easy/rest suggestions, no recovery score, never claim the watch measured soreness.** Programs R17 "soft-warn when recovery looks heavy" is adjacent to these locks (see G14).
- Polarity trap: Hooper is **1 = best**; the emoji set is ordinal good→great. Any shared "feel" abstraction needs an explicit mapping.

---

## 7. Programs-facing view: what can answer each requirement

| Req | Question | Data that exists today | What is missing |
| --- | --- | --- | --- |
| R4 | Estimate current continuous distance & sustainable pace from history | `loadAllCanonicalSwims()` (type 6, `poolLengthM`), `distanceM`, `durationSec`, moving pace, per-row pace/stroke | Continuous flag (G1); effort isolation inside a session (G3); thresholds (G7) |
| R5 | Guided baseline test → detect it after Sync | `startTime`/`endTime` window, `type == 6`, total distance/time, moving vs wall time | Identity link to the prescribed test (G4); time-bounded evaluation (G2) |
| R6 | Self-report last resort | — (no store) | Programs-owned prefs/store (G13) |
| R7 | Athlete-visible insufficiency criteria | Precedents: ≥2 paced rows (`analyzeSwimSession`), ≥4/≥6 rows confidence tiers, ≥2 sessions for trends, 10-session chip lookback | Chosen thresholds; "recent" window; minimum distance floor |
| R9 / R10 | Size sessions from baseline | Pace, SWOLF, strokes/25 m, pool length, avg session distance/time | Vocabulary + rules (research track #1) |
| R15–R16 | Efficiency / habit / volume scorecards | Pace decay, CV, SWOLF delta, chips, volume deltas (`buildSwimTrends`, `volumeVsPriorPct`), session counts/week from `loadLocal()` | Weekly aggregation; scorecard definitions |
| R17 | Soft-warn on other load / recovery | `loadLocal()` all types with `durationSec`, `calories`, optional `load`/`recoveryTime`; sleep summary + band; feel string | Load aggregate (G10); badminton type (G12); policy vs recovery locks (G14) |
| R19 | Chore done/skipped/adjusted | — | Programs store; sync-driven auto-complete (G4, G5) |
| R23 | Synced swim satisfies chore/proof when it matches intent | `CanonicalSwimSession` fields above | Match rules (G4–G8) |
| R24 | Reuse swim insight / metrics | `SwimSessionInsight`, `CanonicalSwimSession`, diagnosis ids, rec ids | Domain-level composer (G9); numeric KPIs (G6) |

---

## 8. Using the data for a baseline: what is derivable vs invented

**Derivable now (no new wire work):**

| Quantity | How | Honesty note |
| --- | --- | --- |
| Longest *total* pool distance in a session | `max(distanceM)` over type-6 sessions | Not continuous. |
| Moving swim time and rest time per session | `Σ lap.durationSec`; `durationSec − moving` | Rest is total only; guard `0 < moving ≤ duration` as the insight does. |
| Moving pace per session / per row | `p0.movingAvgPaceSecPer100m`; `lap.paceSecPer100m` | Floor-division ints; rows may be partial. |
| Efficiency | `avgSwolf`, per-row SWOLF, strokes/25 m | Per-row SWOLF is watch-provided. |
| Freestyle-only filter | rows with `style == 2` | `style` can be null; Medley/rest rows "may be unknown or Medley" (runbook). |
| Session cadence / weekly count | count of type-6 `startTime`s per local week | Needs Sync recency. |
| Longest *run of uninterrupted rows* | **not derivable** — no timestamps | See G1. |

**Cannot be derived without new capture or an athlete-confirm step:** continuous distance, CSS/threshold from separate T400/T200 efforts inside one workout, rest-interval prescriptions compliance, stroke-count-per-length *by length* if rows are intervals.

---

## 9. Observed data shape (🧪, `lib/sync_logs.txt`, untracked)

| Fact | Value |
| --- | --- |
| Workouts in log | 65 (#8–#72 with Count lines) |
| By type | 6: 29 · 140: 21 · 5: 6 · 1: 5 · 2: 2 · 8: 1 · 129: 1 |
| Pool swim wall duration | 809–5734 s, median 3298 s |
| Parsed lap rows per swim | 5–40, median 20 (32 sessions incl. 1 OW) |
| Style logged on every pool swim | Yes (`swim-style-outcome … status=styles_logged`); runbook verdict **Pass** 2026-08-14 (`docs/runbooks/2026-08-14-swim-stroke-style-capability-check.md`, sequence includes Free/Back/Breast mixes) |
| Native `hr_samples` on swims | `sampleCount=0` (e.g. #67); HR comes from peeled `0x05` pages (14 pages) |
| Multi-sport days | 13 / 43 session-days include a swim + another type; 9 swim + strength |
| Same-day multi-swim | e.g. 2026-08-01: #18 (5734 s) and #19 (809 s) |
| `unitType` | read, not stored |

No distance values appear in the log lines inspected, so "baseline ~1000 m continuous" from the brainstorm is **not verifiable from this artifact**; it must be checked against `workouts_json` on device.

---

## 10. Gap register for baseline + proof matching

Severity: **B** blocks a requirement as written · **H** high design risk · **M** medium.

| # | Gap | Sev | Affects | Evidence | Options (not decisions) |
| --- | --- | --- | --- | --- | --- |
| G1 | **No continuous-swim signal.** Rows have no timestamps/rest rows; only `durationSec − Σ lap.durationSec` (total rest). | **B** | R4, R12, F3 (1.1 km continuous proof) | §3.2 | Heuristic "total rest ≤ X" (X to be chosen and shown to athlete); require guided test shaped as a single non-stop effort in its **own workout**; honest manual confirm path. Close the open length-vs-interval probe first. |
| G2 | **No time-bounded-distance proof** (e.g. furthest in 12 min) — would need cumulative wall time per row. | **B** if used | F3 | rows lack offsets | Cumulative *moving* time is derivable but understates wall time; or restrict proofs to distance-for-time on a whole session. |
| G3 | **Cannot isolate the proof effort within a session** (warm-up/cool laps share one workout). | **B** | R5, R12 | rows positional only; `buildSwimIntervalSets` is a guess | Prescribe proof as a separate workout; or manual-confirm; or evaluate "session contains ≥D m with pace ≤ P" with explicit looseness. |
| G4 | **No workout ↔ prescription identity.** Watch workouts carry no program/plan id. | H | R19, R23 | `WorkoutSummary` fields | Match by local day + `type == 6` + intent bounds; require athlete confirm when ambiguous. Key on `(number, startTime)`. |
| G5 | **Same-day multiple swims / multiple candidates.** | H | R19, R23 | 🧪 #18/#19 | Define tie-breaks (largest distance, closest to intent, athlete picks). |
| G6 | **Two competing distance/pace truths** per session: Totals `distanceM` vs guarded lap-sum; session `avgPace` vs `movingAvgPace` vs insight mean-of-row-paces. | H | R23, R24 | `swim_session_insight.dart:390,410`; `swim_p0_metrics.dart:133` | Pick one authoritative pair for baseline and one for proofs; log which was used; flag disagreement beyond a tolerance. |
| G7 | **"Sufficient history" thresholds absent** (R7). Only analytic confidence tiers (≥2 / ≥4 / ≥6 rows) and 10-session chip lookback exist. | H | R4–R7 | §3.3 | Needs: recency window (history reach ≈ 3 months on this device), min session count, min distance/moving time, requirement for pool-length-known. |
| G8 | **Open water mixed into canonical/trends** and chips only cover same-pool-length type 6. | M | R4, R26 | `loadAllCanonicalSwims` includes type 8; `buildSwimTrends` unfiltered | Filter `type == 6` and known `poolLengthM` before baseline. |
| G9 | **Insight is built inside a widget.** No domain use-case composes diagnosis + history + HR lock + guarded laps; HR avg/max helper lives in presentation. | H | R24 | `swim_session_coaching_fold.dart:84-182` | Extract a pure/domain composer reused by detail and Programs (contract says reuse, not a parallel pipeline). |
| G10 | **Insight KPIs are partly strings** (`durationPrimaryLabel`, chip `deltaLabel`), pace is unweighted mean of rows. | M | R24 | `swim_session_insight.dart:80,385` | Read numeric fields from `CanonicalSwimSession`/laps; use insight for prose and ids only. |
| G11 | **No cross-sport load aggregate / "other-load" function.** | H | R17 | §5.1; grep of `lib/` | Start from per-session `durationSec` (always present) and optional `load`/`recoveryTime`; treat absence as unknown, not zero. |
| G12 | **Badminton (and type 129) unidentified.** No label, no helper. | H | R17 | §5 | Owner confirms which wire type badminton produces; until then rule on "any non-swim session". |
| G13 | **No Programs persistence** and no Forget semantics. No `Program`/plan/chore models, prefs keys, or DI exist (`grep -i program lib/` → none). | H | R3, R6, R19–R22 | `gate_a_prefs.dart`; repos expose `clearLocal()` | New prefs key(s)/store following the `GateAPrefs` + side-file pattern; define wipe-with-Forget vs survive; App Data export envelope (`lib/features/diagnostics/data/app_data_export_envelope.dart`) will need to know about it. |
| G14 | **Policy tension: soft-warn vs recovery/insight locks.** Locks: no hard/easy/rest coaching, no readiness score. | H | R17–R18 | Hooper R7–R8; handoff "Product locks"; insight contract | Phrase soft-warn as *factual* stacking of owned numbers ("strength 52 min today · recovery est. 16 h"), no score; get owner sign-off. |
| G15 | **Hooper-4 not merged**; branch rewrites the feel API. | M | R17 | §6.3 | Decide merge order; code to an abstraction (`Feel`) rather than either type. |
| G16 | **Load / TE / recovery presence on pool swims unverified.** | M | R17 | `docs/brainstorms/2026-09-12-home-today-instrument-requirements.md:157` | Inspect a few `workouts_json` pool rows on device; if null, soft-warn from other sports only. |
| G17 | **Yard pools undetectable** (`unitType` dropped; `poolLengthCmToMeters` guess). | M | R4 | `HuaweiWorkoutSync.kt:924` | Owner pool is metric 25 m; record as an assumption. |
| G18 | **Sync dependency / freshness.** Adherence only visible after Sync; one-shot auto-sync exists but not guaranteed. | M | R23 | `home_last_sync_at_ms`, `OneShotAutoSync` | Show "as of last sync"; avoid marking missed before a sync after the planned day. |
| G19 | **HR for proofs/baseline**: avg HR needs a locked stream; `hrCoverage` misleading. | M | R4, R16 | §3.5 | Only use HR when `lockInSessionHrPoints` returns ≥2 points; never from Totals alone (existing rule). |
| G20 | **Timezone / day boundary.** All times UTC unix; plans are by local day. | M | R19 | `_localDayKey` pattern | Compute local day with device tz at read time; store dates as local `yyyy-MM-dd` + tz-agnostic intent. |
| G21 | **Stroke filter reliability.** `style` per row is present in 🧪 data but nullable; Medley rows may be rest/transition. | M | R9, R23 | runbook notes | Allow "freestyle" intent to ignore null/medley rows explicitly and say so. |

---

## 11. Suggested consumption posture (inputs to planning, not decisions)

1. **Evidence projection, not a new pipeline.** A Programs-side *derived, non-persisted* read model per pool session (e.g. local date, `(number,startTime)`, `distanceM`, moving s, rest s, moving pace, row count, partial flag, freestyle share, guarded-lap count, optional locked-HR avg) built from `CanonicalSwimSession` + guarded laps. Insight prose/tip ids ride alongside. This respects "do not invent a parallel insight pipeline" while avoiding string KPIs.
2. **Extract the composer** from `swim_session_coaching_fold.dart` into domain so Detail and Programs share it (G9).
3. **Treat proofs as session-level or manual-confirm in v1.** Data cannot prove continuity inside a session (G1–G3); prescribing the proof as a standalone workout keeps whole-session totals meaningful.
4. **Soft-warn from always-present fields first:** other-sport `durationSec`/`calories`/start time + sleep duration; layer `load`/`recoveryTime`/sleep score/feel only when non-null; never fabricate zeros; no score.
5. **Version-proof the feel input** with a small adapter so Programs works whether `main` still has the emoji string or the Hooper branch has merged.
6. **Ask the owner for three facts** that unblock thresholds: (a) badminton/other sport wire type(s) from the watch, (b) a real recent `workouts_json` pool row (distance, `laps`, `poolLength`, whether `load/recoveryTime` exist), (c) result of a controlled continuous-swim probe (length vs interval semantics).

---

## 12. File index (all repo-relative)

Pool swim domain: `lib/features/workout_history/domain/{canonical_swim_session,swim_p0_metrics,swim_session_analytics,swim_trends_diagnosis,swim_recommendations,swim_invent_guard,swim_session_insight,swim_stroke_label,in_session_hr_lock,run_session_metrics,strength_session_metrics}.dart`

Pool swim data/presentation: `lib/features/workout_history/data/{canonical_swim_store,run_session_store}.dart`, `lib/features/workout_history/data/repositories/workout_history_repository_impl.dart`, `lib/features/workout_history/presentation/widgets/{swim_session_coaching_fold,swim_interval_sets,in_session_hr_curve_host,sport_tabs}.dart`, `lib/features/workout_history/presentation/view/{workout_history_formatters,workout_history_screen}.dart`

Wire/native: `lib/core/huawei/huawei_link.dart`, `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiWorkoutSync.kt`

Vitals: `lib/features/vitals/domain/{sleep_analytics,sleep_hr_window,trusleep_sleep_sot}.dart`, `lib/features/vitals/domain/repositories/vitals_repository.dart`, `lib/features/vitals/data/repositories/vitals_repository_impl.dart`, `lib/features/vitals/presentation/view/sleep_tab_screen.dart`, `lib/features/vitals/presentation/widgets/sleep_formatters.dart`

Home (existing soft-aggregation precedent): `lib/features/home/data/repositories/home_repository_impl.dart`, `lib/features/home/domain/home_precedence.dart`

Prefs keys: `lib/features/device_pairing/domain/gate_a_prefs.dart`

Docs: `docs/architecture/swim-session-insight-contract.md`, `docs/catalogs/gt5-a07-full-metrics.md`, `docs/runbooks/2026-08-14-swim-stroke-style-capability-check.md`, `docs/plans/2026-07-23-001-product-roadmap-swim-bible-v0.md`, `docs/plans/2026-10-09-001-feat-pool-swim-detail-redesign-plan.md`, `docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md`, `docs/brainstorms/2026-08-20-recovery-v1-timing-hooper-requirements.md`, `docs/handoffs/2026-08-20-recovery-v1-timing-hooper-handoff.md`, `docs/brainstorms/2026-09-12-home-today-instrument-requirements.md`

Unmerged: branch `feat/hooper4-morning-wellness` → `lib/features/vitals/domain/morning_wellness.dart` (not present on `main`).

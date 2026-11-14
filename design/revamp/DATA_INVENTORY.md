# Fitness OS Data Inventory
## Complete audit of Huawei Watch GT5 Pro data fields → source → UI placement

**Audit Date:** 2026-11-14  
**Purpose:** Map every field we collect from the watch to its source file and target screen in the design revamp.

---

## 1. SLEEP DATA

### Sleep Sessions (Message Path: 0x07:0x0C, 0x07:0x0D)
**Source:** `HuaweiFitnessDataSync.kt`, `huawei_link.dart` → `SleepSessionSummary`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `beginUnix` | int | `huawei_link.dart:872` | Sleep Detail |
| `endUnix` | int | `huawei_link.dart:873` | Sleep Detail |
| `wireType` | int? | `huawei_link.dart:874` | Sleep Detail (internal) |
| `stages[]` | SleepStageSummary[] | `huawei_link.dart:878` | Sleep Detail - Hypnogram |

### Sleep Stages (Per-stage blocks)
**Source:** `SleepStageSummary` in `huawei_link.dart:837-862`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `timestampUnix` | int | `huawei_link.dart:844` | Sleep Detail - Hypnogram |
| `durationMin` | int | `huawei_link.dart:845` | Sleep Detail - Stage Breakdown |
| `wireType` | int? | `huawei_link.dart:846` | Sleep Detail (Awake/REM/Light/Deep) |

### TruSleep SEQUENCE_DATA (FileDownload: sleep_state + SEQUENCE)
**Source:** `HuaweiSleepDetailsSequenceParser.kt`, `TruSleepSequenceSession` in `huawei_link.dart:1331-1444`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `beginUnix` | int | `huawei_link.dart:1333` | Sleep Detail |
| `endUnix` | int | `huawei_link.dart:1334` | Sleep Detail |
| `sleepScore` | int? | `huawei_link.dart:1335` | Sleep Detail - Hero Score |
| `avgHrv` | int? | `huawei_link.dart:1336` | Sleep Detail - HRV During Sleep |
| `avgHeartRate` | int? | `huawei_link.dart:1337` | Sleep Detail - Avg HR Overnight |
| `avgBreathRate` | int? | `huawei_link.dart:1338` | Sleep Detail - Breathing Quality |
| `avgOxygenSaturation` | int? | `huawei_link.dart:1339` | Sleep Detail - SpO₂ During Sleep |
| `sleepEfficiency` | int? | `huawei_link.dart:1340` | Sleep Detail - Efficiency % |
| `sleepLatencySec` | int? | `huawei_link.dart:1341` | Sleep Detail - Time to Fall Asleep |
| `deepPart` | int? | `huawei_link.dart:1342` | Sleep Detail - Deep Continuity Score |
| `bedTimeUnix` | int? | `huawei_link.dart:1343` | Sleep Detail - Went to Bed |
| `fallAsleepUnix` | int? | `huawei_link.dart:1344` | Sleep Detail - Fell Asleep |
| `wakeupUnix` | int? | `huawei_link.dart:1345` | Sleep Detail - Woke Up |
| `risingUnix` | int? | `huawei_link.dart:1346` | Sleep Detail - Got Out of Bed |
| `minHeartRate` | int? | `huawei_link.dart:1347` | Sleep Detail - Min HR Overnight |
| `maxHeartRate` | int? | `huawei_link.dart:1348` | Sleep Detail - Max HR Overnight |
| `productStages[]` | SleepStageSummary[] | `huawei_link.dart:1349` | Sleep Detail - Hypnogram (overlay) |

**UI Placement:**
- **Sleep Detail Screen**: Full hypnogram, stage breakdown (Awake/REM/Light/Deep durations), sleep score with contributing factors, HR/SpO₂/HRV/breathing overnight, efficiency %, latency, deep continuity, bed/asleep/wake/rising times
- **Today Screen**: Tonight's sleep card (score, duration, main stage breakdown)
- **Sleep History Screen**: 7-day & 30-day trend charts (score, duration, efficiency)

---

## 2. HEART RATE & HRV

### Continuous Daily HR Samples
**Source:** `HuaweiFitnessDataSync.kt`, `DailyHrSample` in `huawei_link.dart:921-942`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `timestampUnix` | int | `huawei_link.dart:923` | Heart Rate Detail - 24h Curve |
| `bpm` | int | `huawei_link.dart:924` | Heart Rate Detail - 24h Curve |

### Daily HR Summary
**Source:** `DailyHrDaySummary` in `huawei_link.dart:944-978`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `dayKey` | string | `huawei_link.dart:954` | Heart Rate Detail |
| `minBpm` | int | `huawei_link.dart:955` | Heart Rate Detail - Resting HR |
| `avgBpm` | int | `huawei_link.dart:956` | Heart Rate Detail - Avg HR |
| `maxBpm` | int | `huawei_link.dart:957` | Heart Rate Detail - Max HR |
| `sampleCount` | int | `huawei_link.dart:958` | Heart Rate Detail (internal) |

**UI Placement:**
- **Heart Rate & HRV/Stress Screen**: 24h HR curve, resting HR (current + 7/30-day trend), max/min, avg
- **Today Screen**: Current/recent resting HR tile
- **Workout Detail**: HR zones, min/max/avg during workout

---

## 3. ACTIVITY & FITNESS TOTALS

### FitnessTotals Day Rollup (0x07:0x03)
**Source:** `HuaweiFitnessDataSync.kt:260-289`, `FitnessTotalsDay` in `huawei_link.dart:983-1020`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `dayKey` | string | `huawei_link.dart:993` | Activity Screen |
| `dayStartUnix` | int | `huawei_link.dart:994` | Activity Screen |
| `calories` | int | `huawei_link.dart:995` | Activity Screen - Calories Burned |
| `steps` | int | `huawei_link.dart:996` | Activity Screen - Steps |
| `exerciseDurationSec` | int | `huawei_link.dart:997` | Today Screen (via workout sum) |

**Derived Metrics (from steps):**
- **Distance** (estimated from steps × stride length)

**UI Placement:**
- **Today Screen**: Steps ring, calories, active minutes (from workouts)
- **Activity Screen**: Steps chart (7/30-day trend), calories chart, distance estimate
- **Food Screen**: Calories out (for energy balance)

---

## 4. WORKOUTS

### Workout Summary (0x17:0x07 Count → 0x17:0x08 Totals)
**Source:** `HuaweiWorkoutSync.kt:193-311`, `WorkoutSummary` in `huawei_link.dart:1872-2088`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `number` | int | `huawei_link.dart:1920` | Workout List, Workout Detail |
| `startTime` | int | `huawei_link.dart:1921` | Workout List, Workout Detail |
| `endTime` | int | `huawei_link.dart:1922` | Workout List, Workout Detail |
| `durationSec` | int | `huawei_link.dart:1923` | Workout List, Workout Detail |
| `type` | int | `huawei_link.dart:1924` | Workout List (sport icon/name) |
| `calories` | int? | `huawei_link.dart:1925` | Workout Detail |
| `distanceM` | int? | `huawei_link.dart:1926` | Workout Detail, Workout List |
| `steps` | int? | `huawei_link.dart:1927` | Workout Detail (run/walk) |
| `hrMin` | int? | `huawei_link.dart:1933` | Workout Detail - HR Summary |
| `hrMax` | int? | `huawei_link.dart:1934` | Workout Detail - HR Summary |
| `hrPeak` | int? | `huawei_link.dart:1935` | Workout Detail - HR Zones |
| `swimType` | int? | `huawei_link.dart:1936` | Workout Detail (Pool/Open Water) |
| `strokes` | int? | `huawei_link.dart:1937` | Workout Detail - Swim Stats |
| `strokeRate` | int? | `huawei_link.dart:1938` | Workout Detail - Swim Stats |
| `avgSwolf` | int? | `huawei_link.dart:1939` | Workout Detail - Swim Stats |
| `poolLength` | int? | `huawei_link.dart:1943` | Workout Detail - Swim Stats |
| `laps` | int? | `huawei_link.dart:1944` | Workout Detail - Swim Stats |
| `load` | int? | `huawei_link.dart:1946` | Workout Detail - Training Load |
| `aerobicEffect` | int? | `huawei_link.dart:1947` | Workout Detail - Aerobic TE |
| `anaerobicEffect` | int? | `huawei_link.dart:1948` | Workout Detail - Anaerobic TE |
| `recoveryTime` | int? | `huawei_link.dart:1949` | Workout Detail - Recovery Time |
| `trainingPoints` | int? | `huawei_link.dart:1950` | Workout Detail (internal) |
| `segments[]` | WorkoutSegment[] | `huawei_link.dart:1968` | Workout Detail - Swim Lap List |

### Workout Segments (Swim Laps: 0x17:0x0E)
**Source:** `HuaweiWorkoutSync.kt:113-138`, `WorkoutSegment` in `huawei_link.dart:1819-1870`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `index` | int | `huawei_link.dart:1825` | Workout Detail - Lap # |
| `distanceM` | int? | `huawei_link.dart:1826` | Workout Detail - Lap Distance |
| `durationSec` | int? | `huawei_link.dart:1827` | Workout Detail - Lap Time |
| `swimType` | int? | `huawei_link.dart:1828` | Workout Detail - Lap Type |
| `style` | int? | `huawei_link.dart:1829` | Workout Detail - Swim Style |
| `strokes` | int? | `huawei_link.dart:1830` | Workout Detail - Strokes/Lap |
| `avgSwolf` | int? | `huawei_link.dart:1831` | Workout Detail - SWOLF/Lap |
| `paceSecPer100m` | int? | `huawei_link.dart:1832` | Workout Detail - Pace/Lap |

### Workout HR Samples (0x17:0x0A WorkoutData pages)
**Source:** `HuaweiWorkoutSync.kt:145-172`, side-files under `workouts/hr_samples/`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `timestamp` | int | `HuaweiWorkoutSync.kt:148` | Workout Detail - HR Curve |
| `intervalSec` | int | `HuaweiWorkoutSync.kt:149` | Workout Detail - HR Curve |
| `sampleCount` | int | `HuaweiWorkoutSync.kt:150` | Workout Detail - HR Curve |
| HR sample points | bytes | Side-files | Workout Detail - HR Zones Chart |

**Workout Types (type field):**
- **1**: Walk
- **2**: Outdoor Run
- **5**: Indoor Run
- **6**: Pool Swim
- **8**: Open Water Swim
- **129**: Badminton
- **140**: Strength Training
- *Others*: Cycle, Hike, Elliptical, Rowing, etc.

**UI Placement:**
- **Workout List Screen**: All sessions sorted by date, sport icon, duration, distance
- **Workout Detail Screen (Badminton)**: Duration, calories, HR zones, min/max/avg HR, training load, aerobic/anaerobic TE, recovery time
- **Workout Detail Screen (Swim)**: Duration, distance, strokes, stroke rate, SWOLF, pool length, laps, lap-by-lap breakdown, HR zones
- **Workout Detail Screen (Run)**: Duration, distance, pace, splits, HR zones, cadence (if available), training load, TE, recovery
- **Workout Detail Screen (Strength)**: Duration, training load, aerobic/anaerobic TE, recovery time
- **Today Screen**: Today's workouts summary tile
- **Recovery Screen**: Recent workout training load & cumulative recovery time

---

## 5. TRAINING LOAD & RECOVERY

### Session Recovery (computed from workout)
**Source:** `session_recovery.dart`, `overall_recovery_hours.dart`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `recoveryTime` | int? (hours) | Derived from `WorkoutSummary.recoveryTime` | Recovery / Readiness |
| `load` | int? | `WorkoutSummary.load` | Recovery / Readiness |
| `aerobicEffect` | int? | `WorkoutSummary.aerobicEffect` | Recovery / Readiness |
| `anaerobicEffect` | int? | `WorkoutSummary.anaerobicEffect` | Recovery / Readiness |

### Overall Recovery Hours (Fathom composition)
**Source:** `overall_recovery_hours.dart:42-100`
- Stacks session recovery times
- Applies 1:1 wall-clock decay
- Modifies with sleep & activity factors
- Caps at 96 hours

**UI Placement:**
- **Recovery / Readiness Screen**: Hero recovery timer (hours remaining), 7-day training load chart, recent sessions with individual recovery times, sleep & activity modifiers, readiness % or status
- **Today Screen**: Recovery time remaining tile

---

## 6. PROGRAMS (AGON)

### Chore Session (Prescribed Workouts)
**Source:** `chore_session.dart:77-207`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `id` | string | `chore_session.dart:96` | Programs Screen |
| `programId` | string | `chore_session.dart:97` | Programs Screen |
| `dayIso` | string | `chore_session.dart:98` | Programs Screen |
| `role` | ChoreRole | `chore_session.dart:99` | Programs Screen (Endurance/Quality/Technique/Recovery) |
| `state` | ChoreState | `chore_session.dart:100` | Programs Screen (Scheduled/Due/Done/Skipped) |
| `blocks[]` | ChoreBlock[] | `chore_session.dart:101` | Programs Session Detail |
| `targetDistanceM` | int | `chore_session.dart:102` | Programs Session Detail |
| `focusLine` | string? | `chore_session.dart:103` | Programs Session Detail |
| `matchedWorkoutNumber` | int? | `chore_session.dart:105` | Programs Screen (linked workout) |
| `judgedDistanceM` | int? | `chore_session.dart:107` | Programs Session Detail |
| `judgedDurationSec` | int? | `chore_session.dart:108` | Programs Session Detail |
| `completedAtMs` | int? | `chore_session.dart:109` | Programs Screen |

### Chore Block (Set in session)
**Source:** `chore_session.dart:36-74`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `part` | string | `chore_session.dart:48` | Programs Session Detail (WU/Main/CD) |
| `label` | string | `chore_session.dart:49` | Programs Session Detail |
| `distanceM` | int | `chore_session.dart:50` | Programs Session Detail |
| `restGuidanceSec` | int? | `chore_session.dart:51` | Programs Session Detail |
| `patternId` | string? | `chore_session.dart:52` | Programs Session Detail |
| `effortBand` | string? | `chore_session.dart:53` | Programs Session Detail (e.g. Zone 2, Threshold) |

**UI Placement:**
- **Programs Screen**: Weekly calendar view, chore list (due/scheduled/done), program progress, completion %
- **Programs Session Detail**: WU/Main/CD block breakdown, target distance, effort zones, rest intervals, match to actual workout

---

## 7. FOOD LOGGER

### Food Meal (Photo + Manual Entry)
**Source:** `food_meal.dart:4-84`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `id` | string | `food_meal.dart:16` | Food Screen |
| `dayKey` | string | `food_meal.dart:17` | Food Screen |
| `capturedAtMs` | int | `food_meal.dart:18` | Food Screen |
| `photoPath` | string | `food_meal.dart:19` | Food Screen - Meal Photo |
| `name` | string? | `food_meal.dart:20` | Food Screen - Meal Name |
| `note` | string? | `food_meal.dart:21` | Food Screen - Meal Note |
| `kcal` | double? | `food_meal.dart:22` | Food Screen - Manual Calories In |
| `slot` | string? | `food_meal.dart:23` | Food Screen (Breakfast/Lunch/Dinner/Snack) |

### Daily Food Totals (Computed)
**Source:** `daily_food_totals.dart`
- Sum of `kcal` from all meals on a given `dayKey`

**UI Placement:**
- **Food Screen**: Daily meal log with photos, manual calorie entry per meal, daily sum, energy balance (calories in - calories out from FitnessTotals), photo capture flow
- **Today Screen**: Food log tile (if meals exist today)

---

## 8. WEIGHT

**Source:** Not yet implemented in codebase (placeholder for future)

**Expected Fields:**
- `dayKey`: string (YYYY-MM-DD)
- `timestampMs`: int
- `weightKg`: double
- `bodyFatPercent`: double? (if scale supports)
- `muscleMassKg`: double? (if scale supports)

**UI Placement:**
- **Weight Screen**: Current weight, 7/30/90-day trend chart, manual entry form, optional body composition metrics
- **Today Screen**: Weight tile (if updated today)

---

## 9. DEVICE & SYNC STATUS

### Device Info
**Source:** `HuaweiSession.kt`, `huawei_link.dart` → `DiscoveredDevice`, `RememberedDevice`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| `mac` | string | `huawei_link.dart:801` | Device/Sync Screen |
| `name` | string | `huawei_link.dart:802` | Device/Sync Screen |
| `rssi` | int? | `huawei_link.dart:803` | Device/Sync Screen (signal) |

### Battery Level
**Source:** `HuaweiSession.kt:1304-1315` (CMD_BATTERY: 0x08)

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| Battery Level | int (0-100%) | `HuaweiSession.kt:1313` | Device/Sync Screen |

### Link State
**Source:** `huawei_link.dart:781-797`
- `disconnected`
- `permissionRequired`
- `scanning`
- `connecting`
- `authenticating`
- `authFailed`
- `reconnectFailed`
- `gateAIncomplete`
- `connected`

**UI Placement:**
- **Device/Sync Screen**: Watch name, battery level, connection status, signal strength, last sync time, sync-in-progress indicator
- **Settings Screen**: Forget device, re-pair
- **Today Screen**: Sync status banner (if offline or stale)

---

## 10. AUTO-TRACKING FEATURES

### Enable Status (TruSleep, Auto-HR, Auto-SpO₂)
**Source:** `HuaweiFitnessDataSync.kt:80-84`, `huawei_link.dart:1022-1070`

| Field | Type | Source File | UI Screen |
|-------|------|-------------|-----------|
| TruSleep Armed | bool | `HuaweiFitnessDataSync.kt:82` | Settings / Device Screen |
| Auto-HR Armed | bool | `HuaweiFitnessDataSync.kt:83` | Settings / Device Screen |
| Auto-SpO₂ Armed | bool | `HuaweiFitnessDataSync.kt:84` | Settings / Device Screen |

**UI Placement:**
- **Settings Screen**: Auto-tracking toggles status (armed/not armed)
- **Device/Sync Screen**: Feature arm status

---

## 11. PROFILE & USER SETTINGS

**Source:** User input, SharedPreferences, app state

**Expected Fields:**
- User name
- Profile photo (optional)
- Age / DOB
- Sex
- Height
- Goal steps/day
- Goal sleep hours/night
- Notification preferences
- Theme (Light/Dark/Auto)

**UI Placement:**
- **Profile Screen**: Name, photo, biometrics, goals
- **Settings Screen**: Notifications, theme, about, version, privacy, logout

---

## SUMMARY: DATA → SCREEN MAPPING

### Screens Requiring Full Design

1. **Splash** → No data (app logo + loading state)
2. **Onboarding Flow** → Permissions, BT scan (`DiscoveredDevice`), pairing, auth, first sync progress
3. **Today (Dashboard)** → Tonight's sleep card, steps/calories/active min rings, today's workouts, recovery time, food log, weight (if recent)
4. **Sleep Detail** → Full hypnogram, stage breakdown, score factors, HR/SpO₂/HRV overnight, efficiency, latency, deep continuity, 7/30-day trends, nap list
5. **Recovery / Readiness** → Hours remaining, 7-day load chart, recent sessions with recovery times, sleep/activity modifiers, readiness status
6. **Heart Rate & HRV/Stress** → 24h HR curve, resting HR (current + trend), max/min, HRV samples (if available)
7. **Activity** → Steps chart (7/30-day), calories chart, distance estimate
8. **Workouts List** → All sessions sorted by date, sport icon, duration, distance
9. **Workout Detail (Badminton)** → Duration, calories, HR zones, training load, TE, recovery
10. **Workout Detail (Swim)** → Duration, distance, strokes, SWOLF, laps, lap breakdown, HR zones
11. **Workout Detail (Run)** → Duration, distance, pace, splits, HR zones, training load, TE, recovery
12. **Workout Detail (Strength)** → Duration, training load, TE, recovery
13. **Programs (Agon)** → Weekly calendar, chore list (due/done/skipped), session detail with WU/Main/CD blocks
14. **Food Logger** → Daily meal log with photos, manual calorie entry, energy balance
15. **Weight** → Current weight, trend chart, manual entry
16. **Device/Sync** → Watch name, battery, connection status, last sync, feature arm status
17. **Settings** → Auto-tracking, notifications, theme, forget device
18. **Profile** → Name, photo, biometrics, goals

### States

- **Loading** → During data fetch, sync in progress
- **Empty** → No data yet (post-onboarding, no workouts, no sleep, no meals)
- **Error** → Sync failed, connection lost
- **Offline** → BT off, watch not paired
- **Syncing** → Progress indicator, cancellable

---

## UNPLACED / FUTURE DATA

**Data fields collected but not yet placed in UI:**
- `exerciseDurationSec` from FitnessTotals (wire field 0x07) — not proven to be workout minutes; currently using workout-sum for Today screen active minutes
- `trainingPoints` from workouts — internal Huawei metric, no clear athlete-facing meaning yet
- Advanced HRV/Stress samples — not yet synced via LPv2 (watch may support but not exposed in current stack)
- SpO₂ continuous samples (outside sleep) — watch supports but not yet requested in FitnessDataSync
- Run cadence — may be in WorkoutData sample pages but not yet parsed
- Run pace splits — may be in Pace blocks (0x17:0x0C) but not yet promoted to UI

**Planned but not yet collected:**
- Weight & body composition from external scale (Bluetooth pairing TBD)
- Menstrual cycle tracking (watch supports, not yet synced)
- Stress score (watch supports, not yet synced)

---

## NOTES

- All unix timestamps are in **seconds** (not milliseconds), local time zone from device
- `dayKey` format: `YYYY-MM-DD` in local calendar day
- Side-files for large payloads: sleep stages, workout HR samples, workout leftovers
- Sync windows: Sleep (14 days), Workouts (14 days), FitnessTotals (14 days), HR samples (varies)
- Naps vs overnight sleep: classified by duration, time-of-day, and `wireType`
- Pool swim vs open water: `swimType` field (6 = pool, 8 = open water)
- Badminton workout type: `129` (wire type)
- Training load, TE, recovery time: only present on workouts where watch computed them (typically cardio, not always strength)

---

**End of Data Inventory**

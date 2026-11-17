# Calorie Fix Investigation - Follow-up

**Date:** 2026-11-16  
**Branch:** `cursor/sync-webhook-calorie-fix-8ea0`

## Problem Restatement

Ground truth from Huawei Health (16 Nov):
- **Active calories:** 412 kcal
- **Resting calories:** 1575 kcal
- **Total:** ~1987 kcal

Fathom app shows **~750 kcal**, which matches neither value.

## Root Cause Analysis

### Where Does 750 Come From?

**File:** `lib/features/home/data/repositories/home_repository_impl.dart:160-163`

```dart
calories = _homeDayTotal(
  fitnessTotals: ft.calories,  // From wire tag 0x06
  workoutSum: workoutCalories,  // Sum of workout.calories
);
```

**The calculation:**
```dart
int _homeDayTotal({required int fitnessTotals, required int workoutSum}) {
  return fitnessTotals + workoutSum;
}
```

**So 750 = FitnessTotals.calories + sum(workout.calories)**

### Wire Protocol Field Analysis

#### Daily Fitness Totals (`0x07:0x03`)

**File:** `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiFitnessDataSync.kt:807`

Current parsed fields in slot `0x83`:
- **Tag `0x04`:** Day anchor (1=today, N=N-1 days ago)
- **Tag `0x05`:** Steps (u32)
- **Tag `0x06`:** Calories (u16) ← **Currently parsed, meaning UNKNOWN**
- **Tag `0x07`:** Exercise duration in seconds (u32) - confirmed NOT exercise minutes
- **Tag `0x08`:** Present, mostly zero, **MEANING UNKNOWN** ← **Candidate field**
- **Tag `0x0b`:** Present, value unknown, **MEANING UNKNOWN** ← **Candidate field**

**Wire spec:** `docs/wire-specs/huawei-br-gt5-fitness-data.md:152-154`
```
| `0x06` (in `0x83`) | 2 BE u16 | **Calories (kcal)** — day-reset watch **1**; swim-day FT **525** vs watch **528**
| `0x07` (in `0x83`) | 4 BE u32 | **Not exercise minutes** — wire **5064** ≠ watch **58m**
| `0x08` / `0x0b` (in `0x83`) | 2 / 4 | Present; mostly zero | Unknown |
```

**Historical cross-check (from wire spec):**
- Post-day-reset: watch 1 kcal, FT tag 0x06 = 1
- Swim day: watch 528 kcal, FT tag 0x06 = 525

**The 525 vs 528 discrepancy is tiny (3 kcal).** This suggests tag `0x06` roughly matches SOME watch value, but we don't know if that's active, resting, or total.

**Critical gap:** The wire spec doesn't document what the watch Activity UI actually showed for active vs total. "watch 528 kcal" could mean any of:
1. Active calories (Move section)
2. Total calories (including BMR)
3. Some other metric

#### Workout Totals (`0x17:0x08`)

**File:** `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiWorkoutSync.kt:853`

```kotlin
0x06 -> calories = u32(tlv.value)
```

Workout totals tag `0x06` is also "calories" (u32), also with unspecified semantics.

### Hypothesis: Tag `0x08` or `0x0b` Contains Active/Resting Split

Based on ground truth:
- Active: 412 kcal
- Resting: 1575 kcal
- Total: 1987 kcal

**If FT tag `0x06` = 525** (from historical wire spec example), that matches NONE of these.

**Candidate fields:**
- **Tag `0x08` (u16):** Could be active calories (412 would fit in u16)
- **Tag `0x0b` (u32):** Could be resting calories (1575 would fit, though u16 would also work)

**Alternative:** Tag `0x06` could be one component (active or resting), and tags `0x08`/`0x0b` could be the other component or total.

## Changes Made

### 1. Parse Unknown Tags `0x08` and `0x0b`

**File:** `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiFitnessDataSync.kt`

**Lines 788-794:** Extended `FitnessTotalsSlotLeaves` to capture tags `0x08` and `0x0b`:
```kotlin
private data class FitnessTotalsSlotLeaves(
    val slotTag: Int,
    val steps: Int,
    val calories: Int,
    val wire07: Int,
    val wire08: Int?,  // ← NEW: tag 0x08 u16
    val wire0b: Int?,  // ← NEW: tag 0x0b u32
)
```

**Lines 795-825:** Updated `parseFitnessTotalsSlotLeaves` to parse these tags:
```kotlin
0x08 -> if (child.value.size >= 2) wire08 = u16(child.value)
0x0B -> if (child.value.size >= 4) wire0b = u32(child.value).toInt()
```

**Lines 266-285:** Extended `FitnessTotalsDay` data class:
```kotlin
data class FitnessTotalsDay(
    val dayKey: String,
    val dayStartUnix: Long,
    val calories: Int,
    val steps: Int,
    val exerciseDurationSec: Int,
    val wire08: Int?,  // ← NEW
    val wire0b: Int?,  // ← NEW
)
```

**Lines 769-778:** Updated day construction to include new fields.

### 2. Add Sentry Debug Breadcrumb

**File:** `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiFitnessDataSync.kt:715-734`

Added Sentry breadcrumb to log today's raw calorie field values:
```kotlin
// Sentry debug breadcrumb: log today's calorie fields to match watch values
if (parsed.days.isNotEmpty()) {
    val today = parsed.days.firstOrNull()
    if (today != null) {
        io.sentry.Sentry.addBreadcrumb(
            io.sentry.Breadcrumb().apply {
                category = "fitness_totals"
                message = "FitnessTotals today: " +
                    "tag0x06=${today.calories} " +
                    "tag0x08=${today.wire08} " +
                    "tag0x0b=${today.wire0b} " +
                    "steps=${today.steps} " +
                    "dayKey=${today.dayKey}"
                level = io.sentry.SentryLevel.INFO
            }
        )
    }
}
```

**Purpose:** After next sync, Sentry will show these raw values, allowing us to match:
- Which field equals 412 (active)
- Which field equals 1575 (resting)
- Which field equals 1987 (total) or if total is derived

### 3. Update Dart Model

**File:** `lib/core/huawei/huawei_link.dart:1013-1056`

Extended `FitnessTotalsDay` to receive and store `wire08` and `wire0b`:
```dart
class FitnessTotalsDay {
  const FitnessTotalsDay({
    required this.dayKey,
    required this.dayStartUnix,
    required this.calories,
    required this.steps,
    required this.exerciseDurationSec,
    this.wire08,  // ← NEW
    this.wire0b,  // ← NEW
  });

  final int? wire08;
  final int? wire0b;

  factory FitnessTotalsDay.fromMap(Map<String, dynamic> map) {
    int? asIntOrNull(Object? v) => v == null ? null : (v as num).toInt();
    return FitnessTotalsDay(
      // ... existing fields ...
      wire08: asIntOrNull(map['wire08']),
      wire0b: asIntOrNull(map['wire0b']),
    );
  }

  Map<String, dynamic> toJson() => {
        // ... existing fields ...
        if (wire08 != null) 'wire08': wire08,
        if (wire0b != null) 'wire0b': wire0b,
      };
}
```

### 4. Add Debug UI - Home Screen

**File:** `lib/features/home/data/repositories/home_repository_impl.dart:175-186`

Added inline debug display in calories label:
```dart
if (everSynced && !chromeOnly) {
  // Debug: show raw wire values to identify active/resting calorie fields
  if (ft != null && (ft.wire08 != null || ft.wire0b != null)) {
    caloriesLabel = '${_formatInt(calories)} '
        '(FT:${ft.calories} w08:${ft.wire08 ?? 0} w0b:${ft.wire0b ?? 0} '
        'W:$workoutCalories)';
  } else {
    caloriesLabel = _formatInt(calories);
  }
  stepsLabel = _formatInt(steps);
```

**Display format:** `750 (FT:525 w08:412 w0b:1575 W:225)`
- `750` = displayed total (FT + workout sum)
- `FT:525` = tag 0x06 from fitness totals
- `w08:412` = tag 0x08 (candidate active)
- `w0b:1575` = tag 0x0b (candidate resting)
- `W:225` = workout calorie sum

**This will immediately reveal which fields match the ground truth values.**

### 5. Add Debug UI - Workout Detail

**File:** `lib/features/workout_history/presentation/view/workout_detail_screen.dart:471, 525`

Changed label from:
```dart
_Row('Calories', '${workout.calories} kcal'),
```

To:
```dart
_Row('Calories (wire tag 0x06)', '${workout.calories} kcal'),
```

**Purpose:** Clarify that this is the raw wire value from tag `0x06`, which may be total rather than active-only.

## Expected Outcome After Next Sync

### Sentry Breadcrumb

Will show:
```
FitnessTotals today: tag0x06=??? tag0x08=??? tag0x0b=??? steps=??? dayKey=2026-11-16
```

### Home Screen Display

Will show (example):
```
Calories: 750 (FT:525 w08:412 w0b:1575 W:225)
```

**If this matches:**
- `w08:412` = Active calories ✓
- `w0b:1575` = Resting calories ✓
- Then we've identified the correct fields!

### Workout Detail Screen

Will show:
```
Calories (wire tag 0x06): 412 kcal
```

**If workout tag 0x06 = 412**, that means workout totals return active calories only.

## Next Steps (After Data Confirmation)

### Step 1: Verify Fields in Sentry

After next sync, check Sentry breadcrumb to confirm:
- Does `tag0x08` = 412? (active)
- Does `tag0x0b` = 1575? (resting)
- Does `tag0x06` = 1987? (total) OR something else?

### Step 2: Rename Fields Properly

**If confirmed:**

```kotlin
// Android
data class FitnessTotalsDay(
    val dayKey: String,
    val dayStartUnix: Long,
    val totalCalories: Int,      // renamed from `calories`
    val activeCalories: Int,     // renamed from `wire08`
    val restingCalories: Int,    // renamed from `wire0b`
    val steps: Int,
    val exerciseDurationSec: Int,
)
```

```dart
// Dart
class FitnessTotalsDay {
  final int totalCalories;
  final int activeCalories;
  final int restingCalories;
  // ...
}
```

### Step 3: Update Home Display Logic

**File:** `lib/features/home/data/repositories/home_repository_impl.dart`

Replace the sum logic with proper active/resting breakdown:

```dart
final int activeCaloriesToday;
final int restingCaloriesToday;
final int totalCaloriesToday;

if (ft != null) {
  activeCaloriesToday = (ft.activeCalories ?? 0) + workoutCalories;
  restingCaloriesToday = ft.restingCalories ?? 0;
  totalCaloriesToday = activeCaloriesToday + restingCaloriesToday;
} else {
  activeCaloriesToday = workoutCalories;
  restingCaloriesToday = 0;
  totalCaloriesToday = workoutCalories;
}

caloriesLabel = '${_formatInt(activeCaloriesToday)} active · '
                '${_formatInt(restingCaloriesToday)} resting';
```

**Alternative (simpler):** Just show active prominently:
```dart
caloriesLabel = '${_formatInt(activeCaloriesToday)} active';
```

### Step 4: Update Workout Display

**If workout tag 0x06 is active-only (expected):**

Keep as-is, just change label back to:
```dart
_Row('Active Calories', '${workout.calories} kcal'),
```

**If workout tag 0x06 is total:**

Add estimation:
```dart
final activeCal = workout.calories;  // Assuming it's active
_Row('Active Calories', '$activeCal kcal'),
_Row('Total Calories', '${workout.calories} kcal (active + BMR during workout)'),
```

### Step 5: Update Wire Spec Documentation

**File:** `docs/wire-specs/huawei-br-gt5-fitness-data.md`

Update line 152-154 to:
```markdown
| `0x05` (in `0x83`) | 4 BE u32 | **Steps** | Locked |
| `0x06` (in `0x83`) | 2 BE u16 | **Total Calories (kcal)** — active + resting | Confirmed 2026-11-16 |
| `0x08` (in `0x83`) | 2 BE u16 | **Active Calories (kcal)** — Move/activity only | Confirmed 2026-11-16 |
| `0x0b` (in `0x83`) | 4 BE u32 | **Resting Calories (kcal)** — BMR/baseline | Confirmed 2026-11-16 |
| `0x07` (in `0x83`) | 4 BE u32 | **Not exercise minutes** | Rejected |
```

### Step 6: Update Backend Sync

**File:** `lib/core/backend/backend_sync_service.dart:140`

Change from:
```dart
'totalKcal': t.calories,
```

To:
```dart
'activeKcal': t.activeCalories,
'totalKcal': t.totalCalories,
```

**File:** `backend/functions/src/services/sync-service.ts`

The backend already computes `restingKcal = totalKcal - activeKcal` (line 167), so once we send both fields, it will work correctly.

### Step 7: Remove Debug UI

After confirmation, remove the inline debug text from:
- `lib/features/home/data/repositories/home_repository_impl.dart` (lines 176-181)
- Keep the Sentry breadcrumb for ongoing diagnostics

Change workout detail label back to just "Active Calories" or "Calories" as appropriate.

## Alternative Scenarios

### If Tag `0x08` is NOT 412

Then tag `0x0b` might be active, or there could be a different field structure. The Sentry breadcrumb will show the actual values, allowing us to determine the correct mapping.

### If Neither Tag Matches

Then active/resting might be derived (e.g., `total - workout = resting`), or there might be other tags we're not parsing yet. We'd need to log ALL unknown tags in the response.

### If Workout Totals Tag `0x06` ≠ 412

Then workout totals might return total calories (active + BMR during workout). In that case, we'd need to estimate active = total - (duration_sec / 60 * 1.2 kcal/min).

## Files Modified

1. `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiFitnessDataSync.kt`
   - Parse tags `0x08` and `0x0b`
   - Add Sentry breadcrumb for raw field logging

2. `lib/core/huawei/huawei_link.dart`
   - Extend `FitnessTotalsDay` with `wire08` and `wire0b`

3. `lib/features/home/data/repositories/home_repository_impl.dart`
   - Add inline debug display of raw calorie fields

4. `lib/features/workout_history/presentation/view/workout_detail_screen.dart`
   - Clarify workout calories label as "wire tag 0x06"

## Testing Plan

1. **Build and deploy** to test device
2. **Trigger a sync** (manually sync from device)
3. **Check Sentry** for `fitness_totals` breadcrumb with raw values
4. **Check Home screen** for inline debug display
5. **Compare against Huawei Health:**
   - Does `w08` = 412? (active)
   - Does `w0b` = 1575? (resting)
   - Does FT `tag0x06` = ? (unknown, but we'll find out)
6. **Check workout detail** for individual workout calories
7. **Implement proper field names** based on confirmed values
8. **Update UI** to show "Active · Resting" or just "Active" prominently
9. **Update wire spec docs** with confirmed field semantics

## Gadgetbridge Cross-Reference

We should also check Gadgetbridge's Huawei implementation to see if they document tags `0x08`/`0x0b`:
- Repository: https://codeberg.org/Freeyourgadget/Gadgetbridge
- Path: `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/devices/huawei/packets/FitnessData.java`

This could provide immediate confirmation without waiting for another sync.

## Summary

**Root cause of 750 kcal:** FitnessTotals.calories (tag `0x06`) + workout sum, where tag `0x06` semantics are unknown.

**Fix approach:**
1. ✅ Parse unknown tags `0x08` and `0x0b` (active/resting candidates)
2. ✅ Add Sentry breadcrumb to log raw values
3. ✅ Add debug UI to show raw values inline
4. ⏳ **Wait for next sync** to capture ground truth values
5. ⏳ Confirm field mappings (tag `0x08` = 412, tag `0x0b` = 1575)
6. ⏳ Rename fields properly (activeCalories, restingCalories, totalCalories)
7. ⏳ Update UI to show active/resting split correctly
8. ⏳ Update wire spec documentation

**Expected after next sync:** Home screen will show `750 (FT:??? w08:412 w0b:1575 W:???)`, immediately revealing which fields are which.

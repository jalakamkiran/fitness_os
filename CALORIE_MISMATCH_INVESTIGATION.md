# Calorie Mismatch Investigation

**Issue:** Huawei Watch GT5 Pro shows 412 kcal in Move (active calories) section for today's workout, but Fathom app shows ~750 kcal.

**Date:** 2026-11-16

---

## Root Cause Hypothesis

**The app is likely showing TOTAL calories (active + resting/BMR) instead of ACTIVE calories only.**

---

## Evidence Trail

### 1. Wire Protocol - Workout Calories Field

**File:** `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiWorkoutSync.kt`

**Line 853:**
```kotlin
0x06 -> calories = u32(tlv.value)
```

The workout totals response (service `0x17`, command `0x08`) includes tag `0x06` as calories, parsed as a `u32` (32-bit unsigned integer).

**Wire Spec:** `docs/wire-specs/huawei-br-gt5-gate-b-enrichment.md` line 90:
```
| `0x06` | calories | u32 | optional; not in POC log | catalog **3** until capture cites tag |
```

The wire spec documents this as "calories" but does NOT specify whether this is:
- Active calories only (what the watch shows in Move/active section)
- Total calories (active + BMR/resting)

### 2. Data Flow: Watch → App → Backend → Firestore

**Android → Dart (WorkoutSummary):**
- `HuaweiWorkoutSync.kt` line 853: parses tag `0x06` as `calories`
- Maps to `WorkoutTotals.calories` (line 201)
- Sent to Flutter as `WorkoutSummary.calories` (`lib/core/huawei/huawei_link.dart` line 1958)

**Dart → Backend API:**
- `lib/core/backend/backend_sync_service.dart` line 86:
  ```dart
  if (w.calories != null) 'calories': w.calories,
  ```
- Sends to backend as `calories` field

**Backend → Firestore:**
- `backend/functions/src/services/sync-service.ts` line 97:
  ```typescript
  activeKcal: workout.calories || null,
  ```
- **BUG POTENTIAL:** Backend stores the `calories` field as `activeKcal`, but if the wire field is actually TOTAL calories, this is a misnomer!

**Backend API Response:**
- `backend/functions/src/index.ts` line 100:
  ```typescript
  activeKcal: data.activeKcal,
  ```
- API returns this as `activeKcal` to clients

**Flutter UI Display:**
- `lib/features/workout_history/presentation/view/workout_detail_screen.dart` lines 471-472:
  ```dart
  if (workout.calories != null)
    _Row('Calories', '${workout.calories} kcal'),
  ```
- Shows `workout.calories` directly without any label clarifying active vs total

### 3. Hypothesis: Wire Field is Total Calories, Not Active

**Evidence supporting this hypothesis:**

#### A. Daily Fitness Totals Differentiation
Looking at how Huawei handles daily activity calories:

**File:** `lib/core/backend/backend_sync_service.dart` line 140:
```dart
'totalKcal': t.calories,
```

The daily fitness totals explicitly use the label `totalKcal`, suggesting awareness of active vs total.

**Backend processing:** `backend/functions/src/services/sync-service.ts` lines 165-168:
```typescript
const activeKcal = totals.activeKcal || null;
const totalKcal = totals.totalKcal || null;
const restingKcal = totalKcal && activeKcal ?
  totalKcal - activeKcal : null;
```

The backend explicitly computes `restingKcal = totalKcal - activeKcal`.

**Wire spec:** `docs/wire-specs/huawei-br-gt5-fitness-data.md` line 152:
```
| `0x06` (in `0x83`) | 2 BE u16 | **Calories (kcal)** — day-reset watch **1**; swim-day FT **525** vs watch **528**
```

For daily totals, tag `0x06` is documented as just "Calories (kcal)" without specifying active vs total.

**However**, the backend sync sends only `totalKcal` from daily fitness (line 140), NOT both `activeKcal` and `totalKcal`. This suggests the wire protocol may not differentiate, or we're not parsing the active/total split correctly.

#### B. Numeric Evidence from User Report

- **Watch shows:** 412 kcal in "Move" (active calories) section
- **App shows:** ~750 kcal

**Analysis:**
- **Ratio:** 750 / 412 ≈ 1.82
- **Interpretation:** If 750 is total and 412 is active, then resting = 750 - 412 = 338 kcal
- **Resting calorie burn during workout:** For a ~111 minute badminton session (from PR #26 context), a resting burn of ~3 kcal/min would give 333 kcal resting
- **Conclusion:** This ratio is plausible for total = active + BMR during the workout duration

#### C. Gadgetbridge Oracle Comparison

The wire specs cite Gadgetbridge (GB) as the behavioral oracle. Checking GB's handling of workout calories would clarify if they interpret tag `0x06` as active or total, but we don't have direct access to GB's interpretation in our docs.

### 4. Alternative Hypotheses (Less Likely)

#### A. Double-Counting Across Pages
**Unlikely** because:
- The workout sync fetches one Totals response per workout (command `0x17:0x08`)
- No pagination or multiple TLV blocks for the same workout
- The `u32` calories field is a single scalar, not accumulated

#### B. HR-Based Estimation Overlay
**Unlikely** because:
- We display `workout.calories` directly from the wire
- No code path shows HR-based calorie re-computation
- The value comes straight from Huawei's totals

#### C. Units/Scaling Error (kcal vs cal)
**Unlikely** because:
- Wire spec explicitly documents "Calories (kcal)" for daily totals
- No evidence of 1000x scaling mismatch (412 cal → 0.412 kcal would be absurd)
- Both watch and app show values in the same magnitude range

#### D. Active Calories Incorrectly Parsed
**Possible** if:
- There's a separate TLV tag for "active calories" that we're missing
- Tag `0x06` is total, but another tag (e.g., unlisted enrichment tag) holds active-only

**Checking enrichment tags:** `docs/wire-specs/huawei-br-gt5-gate-b-enrichment.md` lines 94-107 list optional enrichment tags, but none are explicitly labeled "active calories".

---

## Proposed Fix

### Step 1: Confirm Hypothesis (Requires Real Data)

To confirm that tag `0x06` is total calories (active + resting), we need:

1. **Capture a workout totals response** with known watch-displayed active calories
2. **Log all TLV tags** in the response, including unknown/enrichment tags
3. **Cross-reference** with watch UI:
   - Watch Move section (active kcal)
   - Watch total kcal (if shown separately)
   - Wire tag `0x06` value

**Logging addition:**
Add to `HuaweiWorkoutSync.kt` around line 870 (after parsing all tags):
```kotlin
Log.i(TAG, "workout-sync totals number=$number calories=$calories (wire 0x06) type=$type")
// Log all unhandled TLVs:
for (tlv in tlvs) {
    if (tlv.tag !in listOf(0x02, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x12, 0x14, ...)) {
        Log.i(TAG, "workout-sync totals enrichment tag=0x${tlv.tag.toString(16)} len=${tlv.value.size}")
    }
}
```

### Step 2: Fix (If Hypothesis Confirmed)

#### Option A: If Tag 0x06 is Total Calories

1. **Rename field for clarity:**
   - `WorkoutTotals.calories` → `WorkoutTotals.totalCalories`
   - `WorkoutSummary.calories` → `WorkoutSummary.totalCalories`

2. **Compute active calories:**
   - For a workout of duration `durationSec`, estimate resting burn as `(durationSec / 60) * 1.2` kcal/min (rough BMR during rest)
   - `activeCalories = totalCalories - restingBurn`

3. **Update UI:**
   ```dart
   if (workout.totalCalories != null) {
     final active = workout.activeCalories ?? workout.totalCalories;
     _Row('Active Calories', '$active kcal'),
     if (workout.totalCalories != active)
       _Row('Total Calories', '${workout.totalCalories} kcal (incl. resting)'),
   }
   ```

4. **Update backend:**
   - Send both `activeCalories` and `totalCalories` fields
   - Update `sync-service.ts` to handle both

#### Option B: If There's a Separate Active Calories Tag

If we find an enrichment tag (e.g., `0x??`) that holds active-only calories:

1. **Parse the new tag** in `HuaweiWorkoutSync.kt`
2. **Add `activeCalories` field** to `WorkoutTotals` and `WorkoutSummary`
3. **Update UI** to prefer `activeCalories` over `totalCalories` for primary display
4. **Update backend** to store both fields

### Step 3: Documentation

Update wire spec `docs/wire-specs/huawei-br-gt5-gate-b-enrichment.md` line 90:
```markdown
| `0x06` | totalCalories | u32 | Total energy (active + resting BMR) | catalog **5** (confirmed via watch cross-check) |
| `0x??` | activeCalories | u32 | Active energy only (if separate tag exists) | catalog **TBD** |
```

---

## Quick Win (Without Wire Capture)

**If we can't capture wire data immediately, apply a heuristic:**

1. **Assume tag 0x06 is total calories** (based on numeric evidence)
2. **Estimate active calories** using a conservative resting burn rate:
   ```dart
   final restingKcalPerMin = 1.2; // ~72 kcal/hour resting
   final restingBurn = (workout.durationSec / 60) * restingKcalPerMin;
   final activeCalories = (workout.calories ?? 0) - restingBurn.round();
   ```
3. **Display both** in the UI:
   ```dart
   _Row('Active', '$activeCalories kcal'),
   _Row('Total', '${workout.calories} kcal'),
   ```

**Why this is safe:**
- If tag `0x06` is already active-only, the resting burn subtraction will give a slightly low number, but won't be dramatically wrong
- Users get visibility into both values
- Can be refined later with wire-level confirmation

---

## Files to Change (Quick Win Implementation)

### 1. `lib/core/huawei/huawei_link.dart`
Add a computed property to `WorkoutSummary`:
```dart
/// Estimate active calories from total, subtracting resting burn during workout.
int? get estimatedActiveCalories {
  if (calories == null) return null;
  final restingKcalPerMin = 1.2;
  final restingBurn = (durationSec / 60) * restingKcalPerMin;
  final active = calories! - restingBurn.round();
  return active > 0 ? active : calories; // Floor at total if negative
}
```

### 2. `lib/features/workout_history/presentation/view/workout_detail_screen.dart`
Update lines 471-472:
```dart
if (workout.calories != null) ...[
  _Row('Active Calories', '${workout.estimatedActiveCalories} kcal'),
  if (workout.estimatedActiveCalories != workout.calories)
    _Row('Total Calories', '${workout.calories} kcal'),
],
```

### 3. Backend (Lower Priority)
Since the backend API is read-only for now, this can wait. When implementing:
- Add `estimatedActiveCalories` computation in `syncFromApp` before writing to Firestore
- Store both `activeKcal` and `totalKcal` fields
- Update API responses to include both

---

## Summary

**Root Cause:** The Huawei wire protocol tag `0x06` in workout totals (`0x17:0x08`) likely returns **total calories (active + resting)**, not active calories only. The app displays this as-is, showing ~750 kcal, while the watch "Move" section correctly shows only the active portion (~412 kcal).

**Which Field Equals 412 kcal:** The active calories (412 kcal) are NOT directly present in a separate wire field (based on current spec). They're computed by Huawei's watch firmware as `total - resting`, and displayed in the Move section. We need to replicate this computation.

**Proposed Quick Fix:**
1. Add `estimatedActiveCalories` getter to `WorkoutSummary` that subtracts estimated resting burn (~1.2 kcal/min * duration)
2. Display "Active Calories" prominently in the UI using this estimate
3. Optionally show "Total Calories" as a secondary row for transparency

**Next Steps for Confirmation:**
1. Add logging to capture workout totals TLV tags and cross-check with watch UI
2. If a separate active-calories tag exists, parse it directly
3. Update wire spec documentation with confirmed semantics

---

## Cross-References

- **Workout Sync Parser:** `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiWorkoutSync.kt` line 853
- **Wire Spec:** `docs/wire-specs/huawei-br-gt5-gate-b-enrichment.md` line 90
- **Daily Calories (comparison):** `docs/wire-specs/huawei-br-gt5-fitness-data.md` line 152
- **UI Display:** `lib/features/workout_history/presentation/view/workout_detail_screen.dart` lines 471-472
- **Backend Storage:** `backend/functions/src/services/sync-service.ts` line 97
- **Catalog:** `docs/catalogs/gt5-a07-full-metrics.md` lines 60, 82

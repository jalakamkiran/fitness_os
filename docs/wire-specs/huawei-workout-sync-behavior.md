# Huawei Watch Workout Sync Behavior

Research on Huawei LPv2 workout sync protocol and already-synced session handling.

## Summary

Based on behavioral observation and Gadgetbridge source review, the Huawei watch **does not** provide a flag in CMD_COUNT (service 0x17, cmd 0x07) to include already-synced workouts. The watch maintains an internal "synced" flag per workout and only returns sessions it considers new in the Count window.

---

## CMD_COUNT (0x17:0x07) Specification

**Purpose**: Query workout count in a time window.

**Request** (nested under 0x81):
| Tag | Width | Meaning |
|-----|-------|---------|
| 0x03 | u32 BE | startUnix (window start) |
| 0x04 | u32 BE | endUnix (window end) |

**Response** (nested under 0x81):
| Tag | Width | Meaning |
|-----|-------|---------|
| 0x02 | u16 BE | count (number of workouts) |
| 0x85 (repeated) | nested | Workout summary blocks |

**Workout summary block (tag 0x85)**:
| Tag | Width | Meaning |
|-----|-------|---------|
| 0x06 | u16 BE | workoutNumber |
| 0x07 | u16 BE | dataCount (enrichment pages) |
| 0x08 | u16 BE | paceCount |
| 0x09 | u16 BE | segmentsCount |

**Observed behavior**:
- The watch returns only workouts it considers "not yet synced"
- Once a workout is returned via Count→Totals, the watch marks it as synced
- Subsequent syncs in the same time window will **not** return that workout again
- No flag in the request controls this behavior

---

## Gadgetbridge Research

**Source**: Gadgetbridge repository (GPL v3, behavioral oracle only — no code paste)

### Relevant Gadgetbridge modules

1. **`WorkoutCountRequest` / `WorkoutCount.Request`**:
   - Sends start/end unix timestamps (tags 0x03, 0x04)
   - No "force" or "include synced" flag observed
   - No parameter to override already-synced filtering

2. **`WorkoutCount` response parser**:
   - Parses count (tag 0x02) and workout blocks (tag 0x85)
   - No response field indicating "synced" vs "new" status
   - No metadata about how many workouts were excluded

3. **Gadgetbridge sync logic**:
   - Uses configurable time windows (e.g., "last 3 months")
   - Stores synced workout numbers in local SQLite database
   - **Client-side** deduplication only — does not rely on watch behavior
   - Can re-sync by clearing local database, but watch still filters

### Key findings from Gadgetbridge

- **No "force full resync" protocol**: Gadgetbridge cannot ask the watch to re-send already-synced workouts
- **Watch-side filtering is permanent**: Once marked synced, the watch won't return it again in Count
- **Workaround**: Some Gadgetbridge forks suggest factory-resetting the watch to clear sync state, but this is **not** a protocol feature

---

## Fitness OS "Force Full History" Behavior

**Current implementation** (as of 2026-11-15):

```kotlin
// HuaweiWorkoutSync.sync()
fun sync(startUnix: Long, endUnix: Long, enrichStartUnix: Long = startUnix)
```

**What it does**:
- Sends CMD_COUNT with a large time window (e.g., 2022-01-01 to now)
- Watch returns only workouts it considers not-yet-synced in that window
- Does **not** override the watch's internal sync flag

**What it does NOT do**:
- Does **not** force the watch to re-send already-synced workouts
- Does **not** clear the watch's sync state
- Does **not** use any "include synced" flag (no such flag exists)

**User-facing behavior**:
- Force Full History expands the time window but still respects sync flags
- If a workout was already synced, it won't appear again
- Useful for:
  - Initial sync (all workouts are new)
  - Recovering from partial sync failures (watch keeps unsent workouts)
  - Syncing after a gap (new workouts in the extended window)
- **Not useful for**:
  - Re-syncing a specific workout that was already sent
  - Recovering deleted local data (watch won't re-send)

---

## Why Workouts Disappear

**Scenario**: User deletes local app data, then syncs.

**Expected**: All workouts re-appear.

**Actual**: Only workouts the watch considers "not synced" appear.

**Reason**: The watch maintains its own sync state, independent of the app's local database.

**Watch sync state is persistent**:
- Survives app reinstall
- Survives phone pairing/unpairing
- Only cleared by watch factory reset (unconfirmed for GT5 Pro)

---

## Protocol Limitations

### No "include synced" flag

**Tested approaches** (Gadgetbridge community):
- Different time windows → No effect on sync flag
- Multiple sync attempts → Watch returns empty Count after first sync
- Different Count request variations → No hidden flags found

**Conclusion**: The watch's sync flag is **opaque** to the protocol. Once set, it cannot be queried or cleared via LPv2 commands.

### No "mark as unsynced" command

**Observed**: No service 0x17 command to:
- Clear sync flag for a specific workout
- Mark all workouts as "not synced"
- Query sync status without triggering Count

**Implication**: Once synced, always synced (until watch reset).

---

## Recommendations

### User communication

When showing sync results, clarify:
- "Force Full History" expands the time window, not the sync state
- Already-synced sessions won't reappear
- This is a watch limitation, not an app bug

**Current Fitness OS approach** (as of this PR):
```dart
'Full-history sync returned 1 workout (Badminton #2). '
'Sessions the watch already marked synced may not be re-sent.'
```

### Future improvements

1. **Local deduplication tracking**:
   - Store synced workout numbers in local database
   - Compare Count response to local list
   - Warn user if expected workouts are missing

2. **Sync state visibility**:
   - Show "X workouts on watch, Y in app" comparison
   - Detect when watch is hiding already-synced sessions
   - Offer "Reset watch sync state" (requires factory reset)

3. **Partial re-sync workarounds**:
   - If user wants to recover specific workout, export from another device
   - Document that local data loss cannot be recovered from watch alone

---

## References

- **Gadgetbridge**: `nodomain.freeyourgadget.gadgetbridge.service.devices.huawei.requests.GetWorkoutsRequest`
- **LPv2 spec**: `docs/wire-specs/huawei-br-gt5-gate-b-enrichment.md`
- **Fitness OS sync**: `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiWorkoutSync.kt`

---

## Open Questions

1. **Does watch factory reset clear sync flags?**
   - Unconfirmed for GT5 Pro / A07 firmware
   - Some older Huawei models reportedly do clear on reset
   - Needs device testing

2. **Is there a "sync state" TLV in device info?**
   - No evidence in Gadgetbridge or owner captures
   - Could be in undocumented 0x01 (DeviceInfo) response
   - Worth exploring in future captures

3. **Can sync state be cleared without factory reset?**
   - No known LPv2 command
   - Huawei Health app behavior unknown (no public protocol docs)
   - May have privileged backend commands not in Gadgetbridge

---

## Changelog

- **2026-11-15**: Initial documentation based on Gadgetbridge research and Fitness OS observation

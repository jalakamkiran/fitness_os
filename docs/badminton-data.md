# Badminton & Racket Sport Data on Huawei GT5 Pro

This document summarizes the data available for badminton and other racket sports from the Huawei Watch GT5 Pro over LPv2, what Fitness OS currently parses, and what remains unverified.

## Workout Type Mapping

| Type Code | Sport | Status | Source |
|-----------|-------|--------|--------|
| 129 | Badminton | ✅ Verified | Owner device observation (workout #17, #125) |
| 130 | Table tennis | ⚠️ Inferred | Gadgetbridge behavioral oracle |
| 131 | Tennis | ⚠️ Inferred | Gadgetbridge behavioral oracle |
| 133 | Squash | ⚠️ Inferred | Gadgetbridge behavioral oracle |

**Verified**: Observed on GT5 Pro with real workout data.  
**Inferred**: Based on Gadgetbridge Huawei device support patterns; not yet confirmed by device capture.

## Badminton Workout #125 Example

```
Type: 129 (Badminton)
Start: 07:32 local
End: 08:37 local
Duration: 65 minutes (3900 sec)
Calories: 447 kcal
HR Range: 82-158 bpm
Training Load: 44
Training Effect: 2.3
```

## Available Data Fields

### 1. Always Present (Totals TLV)

These fields come from the workout Totals response (`0x17:0x08`) and are available for all badminton workouts:

| Field | TLV Tag | Status | Example |
|-------|---------|--------|---------|
| Workout number | `0x02` | ✅ Parsed | `125` |
| Start time (unix) | `0x04` | ✅ Parsed | `1730706720` |
| End time (unix) | `0x05` | ✅ Parsed | `1730710620` |
| Duration (sec) | `0x09`/`0x12` | ✅ Parsed | `3900` |
| Type code | `0x14` | ✅ Parsed | `129` |
| Calories (kcal) | `0x06` | ✅ Parsed | `447` (optional) |
| Steps | `0x08` | ✅ Parsed | Count (optional) |
| Distance (m) | `0x07` | ✅ Parsed | Meters (optional) |
| HR min (bpm) | `0x0c` (parsed) | ✅ Parsed | `82` |
| HR max (bpm) | `0x0c` (parsed) | ✅ Parsed | `158` |
| HR peak (bpm) | `0x0c` (parsed) | ⚠️ Optional | May be in TLV `0x0c` |
| Training load | `0x0d` | ✅ Parsed | `44` |
| Aerobic TE | `0x0e` | ✅ Parsed | `23` (wire) → `2.3` (UI) |
| Anaerobic TE | `0x20` | ✅ Parsed | `0-255` range |
| Recovery time (min) | `0x11` | ✅ Parsed | Minutes until recovered |

**Training Effect Note**: Wire value is `TE × 10`. So `aerobicEffect=23` displays as `2.3`.

### 2. Enrichment Data (Hints-Gated)

These require `dataCount > 0` or `paceCount > 0` from the Count response and are fetched during enrichment:

| Field | Command | Status | Notes |
|-------|---------|--------|-------|
| HR series (samples) | `0x17:0x0a` (WorkoutData) | ⚠️ TODO | Requires `dataCount > 0`; see §3 |
| Data pages | `0x17:0x0a` | ⚠️ TODO | Per-page metadata: timestamp, interval, sample count |
| Pace blocks | `0x17:0x0c` | ⚠️ TODO | Requires `paceCount > 0`; unusual for badminton |
| Segments | `0x17:0x0e` | ❌ N/A | Swim-specific; not expected for badminton |

**Current Sync Behavior**: Badminton workouts observed so far have `dataCount=1, paceCount=0, segmentsCount=0`. The enrichment phase is attempted but `dataCount=1` may be a placeholder rather than a real HR sample page.

### 3. Racket-Specific Metrics (Unverified)

Huawei's own Workout app and public documentation suggest the GT5 Pro *may* provide these fields for racket sports:

| Metric | Likely TLV | Status | Verification Needed |
|--------|------------|--------|---------------------|
| Swing count | Unknown | ❌ Unverified | Needs device capture with real swings |
| Forehand count | Unknown | ❌ Unverified | Needs device capture |
| Backhand count | Unknown | ❌ Unverified | Needs device capture |
| Rally count | Unknown | ❌ Unverified | Needs device capture |
| Max swing speed | Unknown | ❌ Unverified | Needs device capture |
| Active time | Unknown | ❌ Unverified | May be in leftover TLVs |
| Cadence | Unknown | ❌ Unverified | May be in leftover TLVs |

These metrics are **not confirmed** for the GT5 Pro. They may be:
- Firmware version dependent
- Only available on newer models
- Encoded in unmatched "leftover" TLVs that current parsing ignores

## What Fitness OS Currently Parses

### For All Badminton Workouts

✅ **Displayed on workout detail screen**:
- Workout type label: "Badminton #125"
- Start/end/duration
- Calories, distance, steps (when present)
- HR min/max
- Training load
- Aerobic/anaerobic training effect
- Recovery time

✅ **Observability** (Sentry breadcrumbs):
- Unknown workout type codes (when first encountered)
- Racket sport workout detection (type 129-133)
- Enrichment counts (data/pace/segments)
- TLV parse failures

### Not Yet Parsed

⚠️ **TODO** (requires device verification):
- HR sample series (WorkoutData pages)
- Swing/rally/speed metrics (if present in leftovers)
- Cadence/active time (if available)

❌ **Not Expected**:
- Pace blocks (unusual for non-cardio sports)
- Swim segments (swim-only)
- GPS track (indoor sport; GT5 Pro may not log GPS for badminton)

## Implementation Status

### ✅ Complete

1. **Workout type mapping**: Type 129 → "Badminton" label
2. **Icon display**: Tennis racket icon (`Icons.sports_tennis`) for racket sports
3. **Totals parsing**: All standard fields (duration, HR, load, TE, recovery)
4. **Graceful fallback**: Unknown types display as "Workout type N"
5. **Sentry breadcrumbs**: Observability for unknown types and parse failures

### ⚠️ TODO (Needs Device Capture)

1. **HR sample parsing**: WorkoutData pages (`0x17:0x0a`)
   - Current sync fetches if `dataCount > 0`
   - Parsing exists for swim/run but needs badminton verification
   - May require `bitmap` field interpretation (tag `0x08`)

2. **Racket-specific metrics**: Swing count, rally count, etc.
   - Add parsing when TLV tags are identified
   - Show on workout detail screen for type 129-133
   - Behind clear TODOs with documented verification status

3. **Leftover TLV exploration**:
   - Unknown tags ride "leftover" channel
   - Dump leftover tag IDs/lengths for analysis
   - Correlate with Huawei Workout app displayed metrics

### ❌ Out of Scope

- Set/rep structure (badminton has no concept of sets like strength)
- Video analysis (watch has no camera)
- Court position heatmap (no GPS on indoor GT5 Pro badminton)

## Verification Plan

To confirm which metrics the GT5 Pro actually sends:

1. **Record a controlled badminton session** with varied activity:
   - Multiple rallies with clear forehand/backhand
   - Varied swing speeds
   - At least 10 minutes duration

2. **Enable raw payload dumps** (owner consent):
   ```bash
   # .env
   SENTRY_DSN=https://your-dsn@sentry.io/project-id
   SENTRY_RAW_WORKOUT_DUMP=true
   ```

3. **Build and sync**:
   ```bash
   flutter build apk --dart-define-from-file=.env
   # Install and trigger workout sync
   ```

4. **Find raw dumps in Sentry**:
   - Go to Sentry project → Issues
   - Search: `message:badminton.raw_dump`
   - Download `badminton.raw_dump.totals` events
   - Download `badminton.raw_dump.data` events (if enrichment ran)
   - Check attachments for large payloads

5. **Analyze TLV hex**:
   - Examine `rawTotalsHex` field for full Totals payload
   - Check `unknownTlvs` for unrecognized tag IDs
   - Check `leftoverTlvs` for width-mismatched fields
   - Look for patterns in unknown tag ranges (0x40-0x7E)

6. **Compare with Huawei Workout app**:
   - What does the official app show for this workout?
   - Which metrics are displayed?
   - Correlate displayed values with hex dump

7. **Update parsing** when tags are confirmed:
   ```kotlin
   0x?? -> parseScalarU16(tlv)?.let { swingCount = it }
   0x?? -> parseScalarU16(tlv)?.let { forehandCount = it }
   // etc.
   ```

8. **Disable raw dumps** after reverse-engineering:
   ```bash
   # .env
   SENTRY_RAW_WORKOUT_DUMP=false
   ```

## Testing Without a Device

Since badminton-specific data cannot be fully verified without a GT5 Pro capture:

1. **Unit tests** use sample TLV payloads from known workouts
2. **Mock data** assumes standard Totals structure
3. **Parsing** is implemented behind `TODO` comments
4. **Documentation** clearly marks unverified fields

Example unit test structure:

```dart
test('badminton workout type 129 parsing', () {
  final totals = parseTotals(mockBadmintonTotalsFrame);
  expect(totals.type, 129);
  expect(totals.durationSec, 3900);
  expect(totals.hrMin, 82);
  expect(totals.hrMax, 158);
  expect(totals.load, 44);
  // TODO: Verify swing count when device capture available
  // expect(totals.swingCount, isNotNull);
});
```

## References

- **Verified data**: Owner workout #17 (732s) and #125 (3900s)
- **Type codes**: Gadgetbridge Huawei device support (behavioral oracle)
- **LPv2 wire spec**: `docs/wire-specs/huawei-br-gt5-gate-b-enrichment.md`
- **Totals TLV catalog**: `docs/catalogs/gt5-a07-full-metrics.md`
- **Privacy scrubbing**: No raw HR series or GPS in Sentry; only codes/counts

## Future Work

1. **Verify racket metrics** with real GT5 Pro badminton captures
2. **Add parsing** for confirmed TLV tags
3. **Display** racket-specific data on detail screen
4. **Unit tests** with real capture payloads
5. **Sentry breadcrumbs** for unusual payload structures

## Raw Payload Capture (Owner Consent)

For reverse-engineering unknown fields, enable `SENTRY_RAW_WORKOUT_DUMP=true`:

**What gets sent to Sentry**:
- Full TLV hex of workout totals for types 129-133
- Raw sample stream hex from WorkoutData enrichment
- Unknown/leftover TLV tags with full hex values
- Workout metadata (id, type, start/end, duration)

**Privacy**: MAC addresses redacted. Health data included by owner explicit consent for debugging only.

**Finding dumps**:
1. Sentry → Issues → Search: `message:badminton.raw_dump`
2. Three event types:
   - `badminton.raw_dump.totals` — Workout totals TLV hex
   - `badminton.raw_dump.data` — WorkoutData pages + sample stream
   - `badminton.raw_dump.pace` — Pace blocks (if present)
3. Download attachments for large payloads (>500KB)

**Example dump structure**:
```json
{
  "version": "1.0",
  "dumpType": "racket_workout_totals",
  "metadata": {
    "workoutNumber": 125,
    "typeCode": 129,
    "typeName": "Badminton",
    "startTime": 1730706720,
    "endTime": 1730710620,
    "durationSec": 3900,
    "service": "0x17",
    "command": "0x08"
  },
  "rawTotalsHex": "02007D04644D6E80...",
  "rawTotalsLength": 256,
  "unknownTlvs": [
    {"id": 60, "len": 4},
    {"id": 61, "len": 2}
  ],
  "leftoverTlvs": [
    {"tag": "0x66", "len": 16, "hex": "..."}
  ]
}
```

See `docs/sentry-setup.md` for complete configuration instructions.

## Changelog

- **2026-11-14**: Initial documentation
  - Type 129 confirmed as Badminton
  - Totals parsing complete
  - Racket-specific metrics marked as TODO pending verification
  - Raw payload dump feature added for reverse-engineering

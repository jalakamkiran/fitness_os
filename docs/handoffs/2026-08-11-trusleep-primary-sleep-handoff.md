# Handoff: TruSleep as sleep SoT (vs Health delta + drop continuous HR)

**Date:** 2026-08-11  
**Branch:** `feat/recovery-sleep-detail`  
**Prior chat:** Recovery / TruSleep FileDownload + Health timestamp investigation  
**Next intent:** Promote TruSleep file path as **primary sleep SoT**; remove **continuous heart rate** from the sleep/vitals path (confirm UI-only vs also stop auto-HR pull/arm on Sync).

Paste this doc into a new chat to continue.

---

## Goal / problem

Owner overnight in Huawei Health: **2026-08-11 ~03:29→08:10 IST (281m)**.

Fitness OS message-path sleep (`FitnessData` `0x0C`/`0x0D`) did **not** match Health. Next step was real TruSleep **FileDownload** (`0x2c`), not the empty consult probe.

---

## What shipped (keep)

### 1. Full FileDownload SM (`0x2c`)

- Init with filename + type + time window (`sleep_state.bin` / `sleep_data.bin`, types `0x0e`/`0x0f`)
- Flow: init → info → block collect (`0x05` raw, `noEncrypt` supported) → complete
- Persist under app-private `vitals/sleep_files/`; Forget wipes via `GateAPrefs.sleepFilesDir`
- Enrich carries refs + optional `stateIntervals` into Flutter

**Key files**

- `android/.../huawei/HuaweiFileDownload.kt`
- `android/.../huawei/HuaweiSession.kt` (wire + persist + watch zone)
- `android/.../huawei/HuaweiFitnessDataSync.kt` (non-blocking after messages)
- `android/.../huawei/HuaweiFraming.kt` / `HuaweiPacketCrypto.kt` (raw block body, decrypt)
- Flutter: `lib/core/huawei/huawei_link.dart` (`SleepEnrichOutcome`, `SleepStateInterval`, `WatchClockSnapshot`)
- Merge: `lib/features/vitals/data/repositories/vitals_repository_impl.dart` (`_mergeSleepEnrich`)
- Spec: `docs/wire-specs/huawei-br-gt5-sleep-files.md`
- Capture: `POC-2026-08-11-trusleep-fd` — state **528 B**, data **694564 B**

### 2. `sleep_state` parse

- 33 × 16-byte **LE** records: start/end unix + 8 B flags (flags unparsed)
- Aug 11 night **fragmented**:
  - `[30]` 03:59→07:07
  - `[31]` 07:09→08:22
  - `[32]` 08:23→08:40
- Merge gap ≤3m → **03:59→08:40 (281m)** — **same duration as Health**, **~30m later** on the clock

### 3. Timezone / clock

- Watch face matches phone IST; not “stuck on +5:00”
- Zone is companion→watch (`1:0x05` set-time + `1:0x32` timezone-id)
- Persist pushed zone (`WatchZone`); format sleep logs with it; re-push on activity Sync
- Latest evidence (`docs/sleep_logs.txt`): **Asia/Kolkata UTC+05:30**, watch echo `t=2:051e`, **`skewSec=0`**
- **Conclusion:** Health gap is **not** companion TZ/clock skew

**Side bug (still open):** activity-sync may skip `timezone-id` when `supportsCommand` map is empty (`supported-commands services=0`); post-bind still sends `0x32` via `activeIds.contains(0x32)` (conflates service id vs DeviceConfig cmd — fragile).

### 4. Sentry observe (temporary)

On each successful vitals Sync merge, Flutter reports privacy-safe compare fields:

- Module: `lib/core/observability/trusleep_timestamp_observe.dart`
- Call site: `vitals_repository_impl.dart` after `_mergeContainers`
- Native adds `watchClock` on activity result (`zoneId`, `offsetSec`, `offsetLabel`, `skewSec`, …)
- Sentry: breadcrumb `trusleep.observe` + grouped Issue fingerprint `['trusleep','timestamp-observe']`, tag `feature=trusleep_observe`, context `trusleep_observe`
- Payload: zone/skew, file interval count, latest + gap-merged begin/end/dur, message-path overnight, `delta_start_min` / `delta_end_min`, file lens, compact `tails` string — **no PPG / sleep_data / stages**
- Tests: `test/core/observability/trusleep_timestamp_observe_test.dart`

**Plan:** compare ~5–6 Sync sessions in that Issue, then delete Issue + remove observe code.

Privacy scrub note: `SentryPrivacyScrub` drops list keys containing `sleep` — observe uses scalar keys + `tails` string only.

---

## Current product wiring (before next cut)

| Path | Role today |
|------|------------|
| Message-path `0x0C`/`0x0D` | **SoT for UI sleep** (prefs + stage side-files) |
| FileDownload enrich | Best-effort; must not wipe message-path |
| Daily / continuous HR | Still part of activity Sync + sleep-detail continuous-HR mode |

Force Sync still re-arms TruSleep soft-enable (`skipTruSleepSoft: false`); auto-HR soft may skip when already armed.

---

## Open conclusions

1. TruSleep **file path works**; message-path alone is not Health-faithful for the observed night.
2. Prefer **recent overnight + merge near-adjacent fragments** (gap ≤3m), not global `longest=` across all history.
3. **~30m vs Health** unexplained after zone/clock verification — likely Health boundary/merge vs TruSleep segments; use Sentry multi-session deltas before locking UI math.
4. `sleep_data.bin` (~678 KiB) is transferred but **not** used for product UI yet (privacy-gated; stages/SpO2/etc. TBD).

---

## Next work (requested)

1. **TruSleep as primary sleep SoT** — drive overnight (and naps if justified) from file `stateIntervals` / future `sleep_data` parse; demote or drop message-path for display.
2. **Remove continuous heart rate** — confirm scope in implementation chat:
   - **A:** sleep-detail continuous-HR UI mode only (`sleep_mode_continuous_hr`), or
   - **B:** also stop pulling/merging `daily_hr` and/or soft-enabling auto-HR on activity Sync.

Suggested implementation order after Sentry samples (or in parallel if owner is ready):

1. Decide merge rule (file fragments → one overnight session) and how message-path stages interact (keep stages from `0x0D` until `sleep_data` parse exists?).
2. Flip repository SoT + tests (`vitals_repository_test.dart`, sleep UI).
3. Strip continuous-HR per agreed scope; Forget/wipe paths stay consistent.
4. After 5–6 Syncs: remove `TruSleepTimestampObserve` + native `watchClock` if unused elsewhere.

---

## Useful references

| Doc / artifact | Why |
|----------------|-----|
| `docs/wire-specs/huawei-br-gt5-sleep-files.md` | FileDownload SM + capture sizes |
| `docs/sleep_logs.txt` | Latest owner Sync / zone / skew evidence |
| `docs/plans/2026-07-18-004-feat-vitals-sleep-hr-tab-plan.md` | Original Vitals plan (message SoT; FileDownload deferred) |
| `docs/plans/2026-08-09-002-feat-recovery-sleep-detail-plan.md` | Recovery sleep detail |
| `docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md` | Stages + HR requirements |
| `docs/catalogs/gt5-a07-full-metrics.md` | Metrics catalog updates |
| Agent transcript | `f81acc48-d75c-4b98-ada1-737fe7629829` (Recovery sleep detail / TruSleep) |

---

## Prompt starter for new chat

```text
Read docs/handoffs/2026-08-11-trusleep-primary-sleep-handoff.md.

Continue from there: plan/implement TruSleep FileDownload (sleep_state intervals,
gap-merge ≤3m) as the primary sleep SoT, and remove continuous heart rate
(confirm: sleep-detail UI only vs also daily_hr / auto-HR on Sync). Keep
Sentry trusleep.observe until we have ~5–6 Sync samples, then strip it.
```

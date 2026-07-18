---
title: "feat: Vitals one-tap auto-tracking enable"
type: feat
status: completed
date: 2026-07-19
origin: docs/brainstorms/2026-07-19-vitals-auto-tracking-enable-requirements.md
deepened: 2026-07-19
---

# feat: Vitals one-tap auto-tracking enable

## Summary

Add a dedicated **Enable auto-tracking** path (native channel + Vitals CTA) that arms TruSleep (`0x07:0x16`), auto-HR (`0x07:0x17`), and auto-SpO2 (`0x07:0x24`) under the shared Sync single-flight lock with FeatureUpload hard-off, returns honest per-feature outcomes, and persists last-run status — without SpO2 charts. Sync’s Gate-A-only button disable stays unchanged this cut; Enable is the only CTA tightened to session-ready.

---

## Problem Frame

Soft Sync enables already request TruSleep/auto-HR but collapse outcomes into `enableSkipped`, never attempt SpO2, and are easy to miss. Owners need an explicit arm ritual with honest results and wear→Sync guidance. (see origin: `docs/brainstorms/2026-07-19-vitals-auto-tracking-enable-requirements.md`)

---

## Requirements

**Control and placement**
- R1. Enable CTA above Sync on Vitals; last-run panel under Enable (not a metric dashboard)
- R2. Enable visible when paired; **disabled** until Gate A **and** sessionReady (Enable-only UI tighten). Sync button disable stays Gate-A-only + mutual busy this cut (origin delta — see Key Decisions)
- R3. One tap attempts fixed set: TruSleep, auto-HR, auto-SpO2

**Honesty and outcomes**
- R4. Per-feature outcomes: `armed` | `skipped` | `failed` | `timed_out`; overall all/partial/none
- R5. No matrix metrics claimed; SpO2 `armed` = command-ack + “not shown in app yet”
- R6. Shared `HuaweiSyncLock` with `syncActivity` / `syncWorkouts`; busy reject immediately; FeatureUpload hard-off for entire Enable CS
- R7. Partial success OK. Mid-batch: (a) per-cmd timeout while session up → that feature `timed_out`, **continue** remaining cmds; (b) disconnect → in-flight `timed_out`, not-yet-sent `failed`, **stop**. Persist partial when Enable ends
- R13. While enabling: Enable in-progress + disabled; Sync busy/disabled; leave-tab does not cancel
- R14. After success/partial: wear several hours → Sync next-step; no immediate series claim; fresh HR may not backfill
- R15. Busy / not-ready / Enable error leave Vitals sleep/HR stores untouched
- R16. Empty HR copy: last Enable auto-HR outcome wins over Sync `enableSkipped` when any Enable run exists; never-run → prompt Enable. Sync enable messaging prefers Enable SoT when present
- R17. Re-tap always allowed when ready; idle copy reflects last run; no live “already on” detection

**Enable set**
- R8. Fixed set exactly TruSleep / auto-HR / auto-SpO2. Mandatory attempt = evaluate each cmd (send, or cap-skip as `skipped` without send). Planning verifies payloads — not membership
- R9. Sync soft-enable fallback only when that feature’s last Enable outcome is **not** `armed`; never soft SpO2; never write Enable prefs. Pairing-scoped = prefs cleared on Forget/re-pair
- R10. Arm-only — no SpO2/stress persist or charts

**Safety and privacy**
- R11. **Radio bar (native):** Enable and Sync both require encrypted session (`not_ready` otherwise). **UI bar (this cut):** Enable also requires sessionReady disable; Sync CTA does not. Forget blocked for whole Enable CS including persist; Forget clears + verifies last-enable key absent
- R12. Logs/channel/experiments: cmd id + mapped outcome + optional short result code only — never frame hex, TLV dumps, or series
- R18. Persist last-run across restarts until newer run or Forget; claims “last enable result,” not live watch state

**Origin actors:** A1 Owner, A2 Watch GT5-A07, A3 Companion session  
**Origin flows:** F1 One-tap arm, F2 Not ready/busy, F3 Wear then Sync, F4 Re-arm  
**Origin acceptance examples:** AE1–AE8

---

## Scope Boundaries

### Deferred for later

- SpO2 (and other) product charts after Sync
- Re-arm on reconnect if the watch drops enables
- FeatureUpload health-package negotiation (unless U1 discovers it is required to arm the three must enables)
- Skin temp / other FitnessData enables on this CTA
- Tightening Sync’s session-ready disable to match Enable

### Outside this product's identity

- Derivation / analytics platform over vitals streams
- Medical claims for arrhythmia / pulse-wave detection

### Deferred to Follow-Up Work

- Catalog score promotions after wear+Sync capture budgets
- Extending Sync soft-enable to SpO2
- Wire-spec promotion for `0x17`/`0x24` ACK shapes after capture (tag+len / result codes only)

---

## Context & Research

### Relevant Code and Patterns

- Vitals UI/bloc/repo: `lib/features/vitals/presentation/view/vitals_screen.dart`, `.../bloc/`, `.../data/repositories/vitals_repository_impl.dart`
- Channel sole owner: `lib/core/huawei/huawei_link.dart`, `huawei_bt_channel.dart`
- Native: `HuaweiBtPlugin.kt`, `HuaweiSession.kt` (`productSyncActive`), `HuaweiSyncLock.kt`, `HuaweiFitnessDataSync.kt` (soft `requestEnable`: any frame→Ok, null→Skipped — do not reuse for Enable honesty)
- Forget: `vitals_di.dart` wipe extras; `device_pairing_repository_impl.dart` verify sleep/HR keys today — extend for last-enable
- Prefs: `lib/features/device_pairing/domain/gate_a_prefs.dart`
- Wire-spec: `docs/wire-specs/huawei-br-gt5-fitness-data.md` — TruSleep enable ACK `t=7f` RESULT_OK (`100000`)
- Prior plan: `docs/plans/2026-07-18-004-feat-vitals-sleep-hr-tab-plan.md`

### Institutional Learnings

- `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md` — BT connected ≠ encrypted session / Gate A
- FeatureUpload hard-off during product Sync CS only
- Fresh auto-HR may not backfill; empty HR after arm ≠ enable failure

### External References

- None — local patterns + owned wire-spec sufficient

---

## Key Technical Decisions

- **Dedicated channel method** `enableAutoTracking`: plugin `tryAcquire` → `sessionIo` → `HuaweiSession.enableAutoTracking()` → `release`
- **Session owns FeatureUpload hard-off:** `productSyncActive = true` before first enable exchange, cleared in `finally` after last outcome — FitnessDataSync does not own the flag
- **`armed` definition (strict):** response contains TLV tag `0x7f` whose BE int equals `RESULT_OK` (`100000`). Else: `0x7f` with other code → `failed`; any other non-null frame without parseable RESULT_OK → `failed` (under-claim); null → `timed_out`; cap-absent → `skipped` (no send). **No “or equivalent” / any-frame Ok.** Unknown `0x17`/`0x24` shapes stay `failed` until wire-spec capture
- **Caps:** If known unsupported, pre-send `skipped` counts as the mandatory attempt for that feature
- **FeatureUpload packages:** Non-blocking assumption — not required for must-set; escalate only on systematic package-gated failure
- **Enable SoT prefs schema (allowlist):** `{ completedAt?, overall, features: [{ id, outcome }] }` only. Forbidden: series, samples, frame hex, MAC, Sync payloads. Unknown bulky fields → corrupt → fail-closed (no last-run)
- **Channel return shape:** `{ overall, features: [{ id|cmd, outcome, resultCode? }] }` only — no frames/hex/tlv/sleep/HR/SpO2 samples
- **Mid-batch / process death:** Timeout-while-up continues; disconnect stops with remainder `failed`. Persist partial on native return. Process kill mid-Enable keeps prior SoT
- **Forget CS:** Repository holds `isSyncOrMergeInFlight` (or equivalent) from before channel call through persist/`finally` — same shape as Sync merge window. Persist only if Gate A still passed and device remembered; late result after Forget must not recreate key. Forget verify fails if last-enable key remains
- **Soft-enable gate:** `skipTruSleepSoft` / `skipAutoHrSoft` true **iff** that feature’s last Enable outcome is exactly `armed`; default false; never soft SpO2; Sync never writes Enable prefs
- **Empty HR / Sync enable copy:** When Enable SoT exists for auto-HR (or TruSleep for enable messaging), prefer Enable per-feature outcomes over Sync `enableSkipped`
- **UI:** Compact text list under Enable; SpO2 armed → “not shown in app yet”; no metric cards
- **Readiness asymmetry (origin delta):** Native radio bar identical (encrypted session). UI: Enable requires `sessionReady`; Sync CTA stays Gate-A-only disable. `sessionReady` = link states Sync already uses for radio (`connected` / `gateAIncomplete` class) — **never** RFCOMM/BT-up alone. Channel `not_ready` is belt-and-suspenders when UI disable is wrong

---

## Open Questions

### Resolved During Planning

- Mid-batch: persist partial; timeout continues; disconnect stops
- Session-ready disable: **Enable only**; Sync left as-is
- FeatureUpload packages: non-blocking assumption
- Soft-enable: skip only when last outcome is `armed` (not “any SoT”)
- Empty sleep copy: unchanged this cut
- `armed` matcher: strict RESULT_OK only

### Deferred to Implementation

- Exact non-`7f` shapes for `0x17`/`0x24` if observed — stay `failed` + capture tag+len/result code only for wire-spec
- Concrete Flutter `sessionReady` wiring to existing link events (no new transport)

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```mermaid
sequenceDiagram
  participant UI as Vitals UI
  participant Repo as VitalsRepository
  participant Link as HuaweiLink
  participant Native as HuaweiBtPlugin
  participant Sess as HuaweiSession
  participant Sync as HuaweiFitnessDataSync

  UI->>Repo: enableAutoTracking()
  Repo->>Repo: Gate A + sessionReady? set in-flight
  alt not ready
    Repo-->>UI: not_ready (no frames)
  else ready
    Repo->>Link: enableAutoTracking()
    Link->>Native: tryAcquire HuaweiSyncLock
    alt busy
      Native-->>UI: busy
    else acquired
      Native->>Sess: enableAutoTracking()
      Sess->>Sess: productSyncActive=true
      Sess->>Sync: enable 0x16, 0x17, 0x24
      Sync-->>Sess: per-feature outcomes
      Sess->>Sess: productSyncActive=false
      Native->>Native: release lock
      Native-->>Repo: overall + features
      Repo->>Repo: persist if still paired; clear in-flight
      Repo-->>UI: last-run + wear copy
    end
  end
```

---

## Implementation Units

### U1. Native `enableAutoTracking` with honest outcomes

**Goal:** Channel method that arms the fixed three enables under shared Sync lock + Session FeatureUpload hard-off and returns distinct per-feature outcomes.

**Requirements:** R3, R4, R5, R6, R7, R8, R10, R12

**Dependencies:** None

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiFitnessDataSync.kt`
- Modify: `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiSession.kt`
- Modify: `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiBtPlugin.kt`
- Test: `android/app/src/test/java/com/example/fitness_os/huawei/HuaweiFitnessDataSyncTest.kt` (extend or sibling)
- Test: `android/app/src/test/java/com/example/fitness_os/huawei/HuaweiSyncLockTest.kt` (overlap if needed)

**Approach:**
- `HuaweiSession.enableAutoTracking()` sets `productSyncActive` for the whole batch; plugin only lock + `sessionIo`
- Attempt `0x16`, `0x17`, `0x24` with TLV `0x01=0x01` unless cap-skip
- Strict RESULT_OK → `armed`; log allowlist: cmd + outcome + short result code — forbid frame hex / TLV dumps
- Return map: overall + features only
- Timeout-while-up: continue; disconnect: stop with remainder `failed`
- Leave Sync soft `requestEnable` unchanged for U2 gating

**Execution note:** Start with failing unit tests for RESULT_OK vs any-frame and timeout→`timed_out` (not Skipped).

**Patterns to follow:**
- `HuaweiBtPlugin` `syncActivity` lock/finally
- `HuaweiFitnessDataSyncTest` `t=7f` RESULT_OK fixtures
- `HuaweiSession.syncActivity` `productSyncActive` try/finally

**Test scenarios:**
- Happy path: three RESULT_OK → all `armed`
- Edge: any non-null non-RESULT_OK frame → `failed` (not armed)
- Edge: cmd-2 timeout, session up → cmd-2 `timed_out`, cmd-3 still attempted
- Edge: disconnect after cmd-1 → cmd-1 truth, remainder `failed`/`timed_out`, batch stops
- Error: NACK → `failed`; overall partial when others armed
- Edge: cap-absent → `skipped` without send
- Integration: lock busy → no frames; not connected / no session key → `not_ready`
- Integration: FeatureUpload `0x28` ignored while batch active
- Covers AE1 / AE4 / AE7 (native)

**Verification:**
- Enable never returns sleep/HR merges or raw frames; busy/not_ready leave radio idle; logs stay on allowlist

---

### U2. Flutter link, persist last-run, soft-enable gate, Forget wipe

**Goal:** Expose Enable through `HuaweiLink`, persist allowlisted Enable SoT across the full Forget-safe CS, gate Sync soft-enables, clear+verify on Forget.

**Requirements:** R2, R6, R9, R11, R12, R15, R16, R18

**Dependencies:** U1

**Files:**
- Modify: `lib/core/huawei/huawei_bt_channel.dart`
- Modify: `lib/core/huawei/huawei_link.dart`
- Modify: `lib/features/device_pairing/domain/gate_a_prefs.dart`
- Modify: `lib/features/vitals/domain/repositories/vitals_repository.dart`
- Modify: `lib/features/vitals/data/repositories/vitals_repository_impl.dart`
- Modify: `android/.../HuaweiFitnessDataSync.kt` / plugin `syncActivity` args for `skipTruSleepSoft` / `skipAutoHrSoft`
- Modify: `lib/features/device_pairing/data/repositories/device_pairing_repository_impl.dart` (Forget verify key)
- Test: `test/features/vitals/vitals_repository_test.dart`
- Test: `test/core/huawei/huawei_link_sync_lock_test.dart`

**Approach:**
- Link mirrors `_syncInFlight` for Enable; repo holds Forget-block from before call through persist `finally`
- Persist allowlisted JSON only; strip unknown bulky keys; corrupt → fail-closed
- Soft-skip flags only when outcome is `armed`; Sync never writes Enable prefs
- Empty HR + Sync enable copy prefer Enable SoT when present
- Forget: `clearLocal` removes key; verify fails if residue; late success after Forget does not recreate key

**Patterns to follow:**
- `syncFromWatch` + `_mergeInFlight` Forget window
- Sleep/HR JSON fail-closed decode

**Test scenarios:**
- Happy path: enable → prefs round-trip; reload SoT
- Edge: partial persist → reload partial overall
- Error: not ready → no channel call
- Integration: Enable↔Sync↔workouts busy; Forget blocked during persist window
- Integration: soft-skip only when armed; prefs unchanged after Sync
- Integration: Enable auto-HR `armed` + Sync `enableSkipped=true` → wear/emission empty HR copy
- Integration: Enable auto-HR `failed` + soft any-frame Ok → UI still reflects Enable failure (not Sync enableSkipped)
- Integration: Forget clears + verify; late inject success → key absent
- Covers AE2 / AE3 / AE5 / AE8 (repo)

**Verification:**
- Enable SoT survives restart; Sync cannot clobber; Forget wipe+verify includes last-enable

---

### U3. Vitals UI + bloc — Enable CTA, last-run panel, busy/in-progress

**Goal:** Ship the owner-facing Enable control and honesty surface on Vitals.

**Requirements:** R1, R2, R5, R13, R14, R17

**Dependencies:** U2

**Files:**
- Modify: `lib/features/vitals/presentation/bloc/vitals_bloc.dart`
- Modify: `lib/features/vitals/presentation/bloc/vitals_event.dart`
- Modify: `lib/features/vitals/presentation/bloc/vitals_state.dart`
- Modify: `lib/features/vitals/presentation/view/vitals_screen.dart`
- Test: `test/features/vitals/presentation/vitals_bloc_test.dart`

**Approach:**
- Enable above Sync; compact overall + three feature rows; SpO2 “not shown” note; wear→Sync copy
- Disable Enable: `!gateAPassed || !sessionReady || enabling || syncing`
- Disable Sync: `!gateAPassed || syncing || enabling` (mutual busy; **no** sessionReady this cut)
- Re-tap replaces last-run; leave-tab no cancel; reload SoT on return
- No matrix rows; no SpO2 charts

**Patterns to follow:**
- Existing Sync CTA + status strip in `vitals_screen.dart`

**Test scenarios:**
- Happy path: success → last-run + wear copy; lists unchanged
- Edge: enabling → both CTAs disabled; Sync → wait-for-enable busy (AE6)
- Edge: re-arm replaces last-run
- Error: Enable disabled when !sessionReady (AE2)
- Covers AE1 / AE4 / AE6 (presentation)

**Verification:**
- Hierarchy Enable → last-run → Sync → lists; no dashboard cards

---

## System-Wide Impact

- **Interaction graph:** `HuaweiSyncLock` + `productSyncActive` expand to Enable; `syncActivity` gains soft-skip flags; Forget verify keys expand
- **Error propagation:** Native busy/not_ready/error → link → repo → bloc; Enable must not clear vitals stores
- **State lifecycle risks:** Partial overwrite; process-death keeps prior SoT; late persist after Forget no-op; Forget-block spans persist
- **API surface parity:** Android method channel only
- **Integration coverage:** Busy matrix; soft-enable gate + copy precedence; Forget during Enable/persist
- **Unchanged invariants:** Workout payloads; sleep/HR merge; Sync Gate-A-only disable; no SpO2 persist; catalog scores unchanged by Enable alone

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `0x17`/`0x24` ACK ≠ TruSleep `7f` | Strict RESULT_OK → under-claim `failed` until capture (tag+len / result code only) |
| Soft Sync still collapses `enableSkipped` | Skip flags + Enable SoT wins for empty HR and enable messaging |
| Owner expects SpO2 in UI | “Not shown in app yet” on SpO2 armed row |
| FeatureUpload package gating | Non-blocking assumption; escalate only if systematic |
| Stale `armed` after watch drops enables | Accepted this cut; reconnect re-arm deferred; owner can re-tap Enable |
| Debug hex-logging during ACK discovery | U1 log/channel allowlist; wire-spec privacy rule for probes |

---

## Documentation / Operational Notes

- Enable ACK captures for wire-spec: cmd id + result code / tag+len histogram only — never full series (binding: fitness-data wire-spec privacy line)
- Owner probe after ship: Enable → wear ≥4h → Sync; presence rates only

---

## Sources & References

- Origin: `docs/brainstorms/2026-07-19-vitals-auto-tracking-enable-requirements.md`
- `docs/wire-specs/huawei-br-gt5-fitness-data.md`
- `docs/plans/2026-07-18-004-feat-vitals-sleep-hr-tab-plan.md`
- `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md`
- `docs/catalogs/gt5-a07-full-metrics.md`

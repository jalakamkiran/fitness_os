# Handoff: TruSleep file SoT shipped — stage attach thin on detail

**Date:** 2026-08-12  
**Branch:** `feat/recovery-sleep-detail` (local **ahead 7** of `origin/feat/recovery-sleep-detail`; not pushed)  
**HEAD:** `5e124ce` — `fix(vitals): decouple file-SoT flip from cursor; stop sleep_state hex`  
**Plan (completed):** `docs/plans/2026-08-11-001-feat-trusleep-primary-sleep-sot-plan.md`  
**Prior handoff:** `docs/handoffs/2026-08-11-trusleep-primary-sleep-handoff.md`  
**Prior chat:** `/ce-work` implement TruSleep primary sleep SoT plan

Paste this doc into a new chat to continue.

---

## Goal / where we are

TruSleep `sleep_state` intervals are now the **primary sleep display SoT** (gap-merge ≤3m). Continuous HR is stripped from Sync + sleep detail. Owner device test confirms **timing looks right**; sleep **detail stage charts look empty / tiny** — next chat should diagnose message-path stage attach onto file windows (not invent TruSleep stages from `sleep_data`).

---

## What shipped (keep)

Commits on this branch (after `7decdb0`):

| Commit | Summary |
|--------|---------|
| `b1b7667` | Domain `TruSleepSleepSot` gap-merge builder + observe share |
| `584b70b` | Native: enrich when messages empty; `sleep_state` only; strip Sync HR |
| `4e27faa` | Repo SoT flip, activity cursor, stop HR merge, observe displayed |
| `476bd70` | UI: remove continuous-HR mode + Sync-as-HR-refill copy |
| `0be9f59` | Live FileDownload session wiring + wire-spec SoT note |
| `e7014ea` | Plan status → completed + prior handoff committed |
| `5e124ce` | Review fixes: flip marker ≠ cursor; feel migrate scope; no sleep_state hex |

### Product behavior

- **Display begin/end:** gap-merged `stateIntervals` (≤180s), upsert into prefs; retain prior nights outside pull span.
- **Messages after flip:** never own begin/end. Flip marker = `GateAPrefs.fileSleepSotActive` (set on any file upsert, including `partialBatch`). Cursor advances **only** on `status==ok` + file upsert.
- **Stages:** message-path stages attach onto file windows with **30m** buffer (`stageAttachBufferSec`); no invent from `sleep_state` flags.
- **Activity cursor:** `last_activity_sync_cursor` + `activity_sync_impl_version`; overlap **6h**; wide = `activityWindowDays` (14) until cursor sticks / on impl bump. Distinct from workout `lastSyncCursor`.
- **HR:** Sync never soft-arms auto-HR or pulls `daily_hr`; one-shot clear HR residue on activity impl bump. Enable may still arm auto-HR. Sleep detail has **no** Continuous HR mode.
- **FileDownload this cut:** `sleep_state.bin` only (skip `sleep_data.bin` ~678 KiB until parse cut).
- **Observe:** keep `TruSleepTimestampObserve` — logs **displayed** timings + message deltas; strip after ~5–6 Sync samples later.
- **Forget:** clears sleep prefs, feel, side dirs, activity cursor, impl version, `fileSleepSotActive`; verify includes those keys.

### Key files

| Area | Path |
|------|------|
| Domain SoT | `lib/features/vitals/domain/trusleep_sleep_sot.dart` |
| Merge / cursor / attach | `lib/features/vitals/data/repositories/vitals_repository_impl.dart` |
| Prefs | `lib/features/device_pairing/domain/gate_a_prefs.dart` (`lastActivitySyncCursor`, `activitySyncImplVersion`, `fileSleepSotActive`) |
| Observe | `lib/core/observability/trusleep_timestamp_observe.dart` |
| Native Sync / FD | `android/.../HuaweiFitnessDataSync.kt`, `HuaweiFileDownload.kt`, `HuaweiSession.kt` |
| Sleep detail UI | `lib/features/vitals/presentation/view/sleep_detail_screen.dart` |
| Wire-spec | `docs/wire-specs/huawei-br-gt5-sleep-files.md` |
| Tests | `test/features/vitals/vitals_repository_test.dart`, `test/features/vitals/domain/trusleep_sleep_sot_test.dart`, `android/.../HuaweiFitnessDataSyncTest.kt`, `HuaweiFileDownloadTest.kt` |

### Implementation decisions (were “Deferred to Implementation”)

| Item | Choice |
|------|--------|
| Stage-overlap buffer | **30 minutes** |
| Activity `cursorOverlapSec` | **6 hours** (not workout 86400) |
| File session `wireType` | **null** → `mergeKey` ends with `:` |
| FD init window | Activity Sync `[start,end]` (not message `min(begin)`) |

---

## Owner device test (2026-08-12)

**Observed good**

- Sleep detail timing e.g. **03:38 → 08:51 · 5h 13m** — owner said timing is fine (file SoT working).

**Observed bad / confusing**

- Stage structure hypnogram largely blank (legend only).
- Stage mix: **Light 2m · 100%** only under a ~5h session.
- Footer still: `provisional stage mapping · message path SoT`.

**How to read it**

- Continuous HR chart **intentionally removed** (in-scope strip).
- Hypnogram + stage mix are **still in product** — they render **attached message-path stages**, not TruSleep `sleep_data`.
- Nearly empty stages ⇒ attach found almost nothing usable for that file window (or messages were sparse), **not** “charts deferred by plan.”
- Rich TruSleep-owned stages / SpO2 / Quality / `sleep_data` parse = **follow-up**, out of this plan’s scope boundaries.

---

## Next intent (suggested)

1. **Diagnose thin stage attach** for the tested night  
   - Compare message-path session/stages vs file window in Sync logs / prefs / `vitals/sleep_stages/` side-files.  
   - Check whether 30m buffer is insufficient, stages filtered by window intersection, or messages simply thin after SoT flip.  
   - Fix attach/honesty UI if hypnogram should show empty-state copy instead of a blank bar + 2m mix.

2. **Optional residual hardening** (from review; not blocking SoT timing)  
   - P2: `HuaweiSession.onRawBytes` still `Log.i` full RFCOMM hex (FD traffic).  
   - P2: Unconditional sleep-stage `raw05` hex dump on Sync.  
   - P2: Sentry scrub does not cover `contexts` (observe payloads are allowlisted scalars today).

3. **After ~5–6 Sync samples** in Sentry Issue `trusleep` / `timestamp-observe`  
   - Strip observe + unused `watchClock` if unused elsewhere.

4. **Later cut:** `sleep_data.bin` parse → TruSleep-owned stages; resume downloading `sleep_data`; retire message-path stages.

5. **Ship process:** branch is **not pushed**; no PR yet. Unrelated dirty tree: catalog/experiment docs, onboarding, swim brainstorm, owner-private capture logs, scripts — do not bundle into SoT PR unless intentional.

---

## Open conclusions (carry forward)

1. File-interval SoT matches Health **duration** intent; ~30m Health clock delta may still appear — do not “fix” via TZ; use observe samples.
2. Message-path stages are transitional honesty until `sleep_data` parse.
3. Activity cursor must not advance on totals-only / messages-only / empty / error / partial (even if file SoT upserted on partial — flip marker still set).
4. Privacy: never log/commit PPG / `sleep_data` bodies; `sleep_state` full-body hex was removed in `5e124ce`.

---

## Useful references

| Doc / artifact | Why |
|----------------|-----|
| `docs/plans/2026-08-11-001-feat-trusleep-primary-sleep-sot-plan.md` | Completed plan (R1–R13, U1–U5) |
| `docs/handoffs/2026-08-11-trusleep-primary-sleep-handoff.md` | Pre-implement investigation |
| `docs/wire-specs/huawei-br-gt5-sleep-files.md` | FD SM + SoT note |
| Owner-private Sync logcat (off-repo) | Zone / skew evidence |
| Agent transcript (this session) | Implement + review fixes + device feedback |

---

## Prompt starter for new chat

```text
Read docs/handoffs/2026-08-12-trusleep-file-sot-shipped-stages-handoff.md.

Continue on feat/recovery-sleep-detail (ahead of origin; HEAD 5e124ce).
Timing SoT works on device; sleep detail only shows ~2m Light stages under a
~5h file window. Diagnose message-path stage attach onto file windows and fix
honesty/empty UI if needed. Do not parse sleep_data or restore continuous HR.
Push/PR only if I ask.
```

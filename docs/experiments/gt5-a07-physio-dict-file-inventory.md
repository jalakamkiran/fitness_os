# GT5-A07 physio dict / file inventory (U1)

**Date:** 2026-08-14  
**Branch / worktree:** `feat/gt5-physio-dict-file-capture`  
**Plan:** `docs/plans/2026-08-13-001-feat-gt5-physio-dict-file-capture-plan.md`  
**Device:** Huawei Watch GT 5-A07 (VLI-B19) — caps dump still owner-pending  
**Clean-room:** GB / Huawhoop = behavioral names only (no AGPL paste)

---

## Companion FileDownload status (live code)

| Item | State |
|------|--------|
| Service | New-sync `0x2c` (`HuaweiFileDownload.SVC_NEW`); legacy `0x0a` soft-absent |
| Product Sync | Downloads **`sleep_state.bin` only** (`TYPE_SLEEP_STATE=0x0e`) via `downloadSleepFiles` |
| `sleep_data.bin` | Constants exist (`FILE_SLEEP_DATA`, `TYPE_SLEEP_DATA=0x0f`); **not** in product Sync specs |
| Soft-skip | `liveDownloadEnabled=false` → `skipped` / `pending_capture` |
| Session wiring | `HuaweiSession.fitnessDataSync()` sets `liveDownloadEnabled=true` + persist + block await |
| Enrich fail-closed | `HuaweiFitnessDataSync.attemptSleepFileDownload` never clears message-path sleep on miss |
| Init present (prior) | `POC-2026-08-11-trusleep-fd`: state=528 B, data=694564 B (~678 KiB) — data transfer still skipped in product |

---

## Dict / sequence client status

| Item | State |
|------|--------|
| In-repo `SLEEP_DETAILS` / sequence download client | **None** |
| DataSync `0x37` cmd `0x04` (“dict”) | **Excluded** — FeatureManager config plane, not sleep-sequence payloads |
| FeatureUpload `0x28` | Gate A finalize / device feature files; **hard-off** during product Sync (`productSyncActive`) |
| Huawhoop Band 10 lead (behavioral only) | Route name `sequence_data/SLEEP_DETAILS` with summary keys `avgHrv`, `avgHeartRate`, `avgBreathRate`, `avgOxygenSaturation` — **not** GT5 proof |

---

## Caps dump (file / dict-like)

| Probe | Status | Notes |
|-------|--------|-------|
| FitnessData caps `0x07` cmds incl. TruSleep / enable | **Pending** (probe-matrix Activity/vitals) | Tag presence only when run |
| `truSleepNewSync` | Assumed true on GT5-A07 from live `0x2c` sleep_state path | Confirm on next caps dump |
| Explicit “dict/sequence” capability bit | **Unknown** — no owned GT5 frame naming a sequence service | Do not invent from DataSync config |

Documented blocked until owner caps dump: treat file/dict capability as **not yet confirmed beyond TruSleep FD**.

---

## Probe candidates (max 3) — invent-then-capture

Survivors after excluding DataSync config-dict and Band-10-only assumptions that lack a named GT5 transport invent:

| # | Candidate id | Concrete route / attempt | Transport | Out-of-band post-Sync feasible? | One-shot rule |
|---|--------------|--------------------------|-----------|----------------------------------|---------------|
| 1 | `cand-fd-seq-path` | FileDownload `0x2c` init UTF-8 name `sequence_data/SLEEP_DETAILS`; filetype probe `0x00` then soft-absent on size 0 / timeout | `FD-0x2c-pull` | **Yes** — same SM as sleep_state; diagnostic entry under SyncLock | One clean attempt |
| 2 | `cand-fd-sleep-details` | FileDownload `0x2c` init UTF-8 name `SLEEP_DETAILS` (basename); same filetype probe | `FD-0x2c-pull` | **Yes** | One clean attempt |
| 3 | `cand-fu-sequence-listen` | Controlled FeatureUpload `0x28` **listen** window after Sync idle for sequence / `SLEEP_DETAILS`-class push (id + len + redacted keys only) | `FU-0x28-receive` | **Yes** — listen-only; must **not** poison product Sync; do not treat hard-off as blocking receive inventory | One clean listen window |

**Not candidates (U3 / U6 planes):**

- `sleep_data.bin` (`TYPE_SLEEP_DATA=0x0f`) — TruSleep file observe (U3), not dict/sequence
- FitnessData `0x0B` daily_hr / SpO₂ — path-2 contingency (U6)

**ABSENT-dict-route:** **Not minted in U1.** Named FD invents + FU listen survive inventory. Mint `ABSENT-dict-route` only after all three one-shots fail (or caps explicitly block FD invents) during U2.

---

## Out-of-band feasibility call

Post-Sync diagnostic SM is the default (plan lock):

1. `tryAcquire` `HuaweiSyncLock`
2. Set `productSyncActive` for FeatureUpload hard-off on **phone-initiated** pulls
3. Run FD invents (candidates 1–2) and optional FU listen (candidate 3)
4. Return privacy-safe maps (route + len + redacted key / tag histogram) — **never** feed Flutter SoT merge
5. Debug/release-gated MethodChannel (`probePhysioCapture` or equivalent); default off

In-band composition into product Sync’s `0x2c` init window is **not** required unless a live night proves invents only succeed mid-Sync (U1 does not falsify OOB).

---

## Working availability matrix scaffold (pre-capture)

| Metric | Class | Pipe | Status |
|--------|-------|------|--------|
| Overnight HRV | overnight-summary | dict candidates → sleep_data → path-2 | unmet — diagnostic ready; live night pending |
| Overnight sleep HR | overnight-summary | same | unmet — diagnostic ready; live night pending |
| Overnight RR | overnight-summary | same | unmet — diagnostic ready; live night pending |
| Overnight sleep SpO₂ | overnight-summary | same | unmet — diagnostic ready; live night pending |

### Implementation note (2026-08-14)

Native/debug surface landed: `HuaweiPhysioCaptureProbe` + Session/MethodChannel `probePhysioCapture` (debug-only). Synthetic unit tests cover AE1 privacy + AE3 fail-closed shapes. Terminal `capture:` / `ABSENT-…` still requires owner GT5-A07 night(s) + Health booleans (U4) before U5.

---

## Related

- Probe matrix: `docs/experiments/gt5-a07-full-metrics-probe-matrix.md`
- Sleep files wire-spec: `docs/wire-specs/huawei-br-gt5-sleep-files.md`
- Research: `docs/learnings/2026-08-13-gt5-overnight-physio-capture-research.md`

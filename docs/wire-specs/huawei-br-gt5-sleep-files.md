# Huawei BR / LPv2 wire-spec — GT5-A07 TruSleep FileDownload

**Status: PRE-PROMOTION (transfer observed; parsers privacy-gated)**

Companion activity Sync runs a **non-blocking** FileDownload after message-path
sleep (`HuaweiFileDownload`). Service `0x2c` (new-sync) downloads
**`sleep_state.bin` only** this cut (skips unused `sleep_data.bin` until stage
parse). Failures never wipe prior sleep.

**Display SoT:** TruSleep `sleep_state` intervals (gap-merge ≤3m) are the
primary sleep begin/end for UI. Message-path `0x0C`/`0x0D` is stages/compare
only after the first file-SoT upsert. Continuous / daily HR is not pulled on Sync.

**Capture:** `POC-2026-08-11-trusleep-fd` (owner GT5-A07, TruSleep ON)

| File | Init fileId | Size (bytes) | Observation |
|------|-------------|--------------|-------------|
| `sleep_state.bin` | 14 | **528** | present |
| `sleep_data.bin` | 15 | **694564** | present (~678 KiB) |

Privacy: log id + length + sleep_state unix interval ranges only — never PPG/ACC
payloads in-repo. Blobs may live under app-private `vitals/sleep_files/` only.

---

## Observed consult (wrong init — historical)

Owner Sync previously sent cmd `0x01` with **filename only** (`sleep_state` /
`sleep_data`, no filetype, no window). Device replied size `0`. Cite:
`docs/sleep_logs.txt` (`svc=0x2c cmd=0x1`).

---

## Transfer SM (new-sync `0x2c`) — promoted shapes

Clean-room from public LPv2 / community packet layouts (not AGPL paste).
Init sizes above promote the request/ack tags.

| Step | CC | Direction | TLVs / body | Status |
|------|-----|-----------|-------------|--------|
| Init | `0x01` | phone→watch | `0x01` name UTF-8 (`sleep_state.bin` / `sleep_data.bin`); `0x02` type (`0x0e` state / `0x0f` data); `0x05` startUnix u32 BE; `0x06` endUnix u32 BE | **observed** |
| Init ack | `0x01` | watch→phone | `0x01` name; `0x02` type; `0x03` fileId u8; `0x04` size u32 BE | **observed** (`POC-2026-08-11-trusleep-fd`) |
| Info | `0x03` | phone→watch | `0x01` fileId; empty `0x02`–`0x05` | behavioral |
| Info ack | `0x03` | watch→phone | `0x01` fileId; `0x02` timeout; `0x03` burstSize; `0x04` maxBlockSize; `0x05` noEncrypt | behavioral |
| Block req | `0x04` | phone→watch | `0x01` fileId; `0x02` offset; `0x03` size — plaintext if noEncrypt | behavioral |
| Block push | `0x05` | watch→phone | **raw**: fileId u8 + offset u32 BE + unk u8 + data; may wrap 7C/7D/7E | behavioral |
| Complete | `0x06` | phone→watch | `0x01` fileId; `0x02` = `0x01` | behavioral |

Size `0` on init → send complete, treat file empty (enrich absent if both empty).

Legacy service `0x0a` list/params path: **not implemented** this cut (GT5-A07 uses `0x2c`).

---

## sleep_state.bin layout — **observed** (`POC-2026-08-11-trusleep-fd`)

Fixed **16-byte LE** records (528 B ⇒ **33** intervals). Capture hex logged on device
(privacy-ok — begin/end only; no PPG).

| Offset | Width | Field | Observation |
|--------|-------|-------|-------------|
| 0 | u32 LE | startUnix | **present** |
| 4 | u32 LE | endUnix | **present** |
| 8–15 | 8 B | flags/score (unparsed) | Structured (`00 00 tt nn ff 01 00 qq`); not stage codes |

### Owner Health cross-check (2026-08-11 IST)

| Source | Window | Duration |
|--------|--------|----------|
| Huawei Health | 03:29→08:10 | **281m** |
| File intervals [30][31][32] | 03:59→07:07, 07:09→08:22, 08:23→08:40 | fragmented |
| Merge gap ≤3 min | **03:59→08:40** | **281m** (same span length; ~30m clock shift vs Health) |

Product note: do **not** use global `longest=` for “last night” (that picked Aug 1 423m). Prefer
recent calendar-night + merge near-adjacent fragments. Stages still live in message-path /
`sleep_data` — state file is begin/end segments only.

---

## Probe / enrich outcome

| Outcome | Channel `sleepEnrich` | UI toggle |
|---------|----------------------|-----------|
| `skipped` / `absent` | empty list | hidden |
| `present` | per-session `{present:true, refs:[{id,len}], stateIntervals?}` | shown when side-file ref set |

---

## Remaining promotion

- Cite block/info/complete on-device frames in a follow-up capture note when transfer completes end-to-end.
- Catalog S4 file rows: bump observation to `present` with this capture id; keep score **3** until sleep_state intervals are Health-matched and product-consumed.

---

## Related

- Catalog S4: `docs/catalogs/gt5-a07-full-metrics.md`
- FitnessData messages: `docs/wire-specs/huawei-br-gt5-fitness-data.md`
- Gate A base: `docs/wire-specs/huawei-br-gt5-gate-a.md`
- Plan: `docs/plans/2026-08-09-002-feat-recovery-sleep-detail-plan.md`

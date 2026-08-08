# GT5-A07 full metrics probe matrix (U2)

**Device:** Huawei Watch GT 5-A07 (VLI-B19)  
**Phone:** Pixel 8a  
**Date opened:** 2026-07-18  
**Catalog:** `docs/catalogs/gt5-a07-full-metrics.md`  
**Plan:** `docs/plans/2026-07-18-003-feat-gt5-full-metrics-catalog-plan.md`  
**Execution posture:** Characterization-first — record what Sync emits; do not invent fields.

**Session mode (this cut):** Scaffolded from Gate A/B POC. Live Outdoor Run / Pool / vitals / sleep seeds are **owner-pending**. Opportunistic Indoor Run / Open water are **explicit deferrals**.

**Privacy:** Log tag ids + lengths + presence rates only. No lat/lon, raw tracks, full series, or sleep blobs in-repo.

**Gates:** All Sync / FileDownload behind durable `gate_a_passed` + encrypted `session_ready`.

---

## Heuristics (operational)

1. Serialize **activity Sync** and **workout Sync** (never concurrent).
2. Stuck → disconnect/reconnect; do not delete device.
3. SpO2/HR empty: caps show enable support + wear ≥4h → reboot once → re-sync; max **2** enable→wear→sync cycles before `absent-in-observed-sessions` and score ≤2.
4. Sleep: prefer night 2 after pair; max **2** full nights (TruSleep ON) before scoring messages/files absent.
5. Short workouts may not persist — seed ≥2 min.
6. Incomplete opportunistic set is OK; must-seeds recorded as attempted or pending.

**Probe matrix complete (this cut)** = all attempted seeds recorded + explicit deferrals for unattempted opportunistic modes + pending owners for remaining must-seeds.

---

## Capture index

| Id | Date | What | Redaction |
|----|------|------|-----------|
| `POC-2026-07-18-strength-totals` | 2026-07-18 | Workout Sync Count→Totals: `count=1`, `number=2`, `type=140`, `duration=112s` | No GPS/HR series |
| `POC-2026-07-18-gate-a-battery` | 2026-07-18 | Post-bind `0x01:0x08` → log `battery ok level=<u8>` (tag `0x01`) | Level integer only |
| `ABSENT-*` | — | Reserved for documented-absence after attempt budget | — |

Firmware string: **fill on next probe** (blank in `gate-a-interrupt-matrix.md`).

---

## Workouts

Serialize after any activity Sync. Per row: `mode | priority | duration | type | dataCount | paceCount | segmentsCount | tags[] | probes | gpsFile | observation`.

| mode | priority | duration | type | dataCount | paceCount | segmentsCount | tags[] (id+len only) | probes | gpsFile | observation | status |
|------|----------|----------|------|-----------|-----------|---------------|----------------------|--------|---------|-------------|--------|
| Strength | Must | ~112s | **140** | not logged | not logged | not logged | list tags only (`0x02`,`0x04`,`0x05`,`0x12`,`0x14`) | Totals list only; Data/Pace/Swim **not** force-probed | n/a | `present` (list scalars) | **Done** — `POC-2026-07-18-strength-totals` |
| Outdoor Run | Must | — | — | — | — | — | — | Totals tag dump; Data/Pace if counts>0; GPS file observe | — | `unobserved` | **Pending owner** |
| Pool swim | Must | — | — | — | — | — | — | Totals `0x15`–`0x1a`; `0x0e` if segmentsCount>0 | — | `unobserved` | **Pending owner** |
| Indoor Run | Opportunistic | — | — | — | — | — | — | only if outdoor type/GPS conflict | — | `unobserved` | **Deferred** |
| Open water | Opportunistic | — | — | — | — | — | — | only if pool type/GPS conflict | — | `unobserved` | **Deferred** |

### Strength type freeze

| Field | Value | N | Rule |
|-------|-------|--:|------|
| type (`0x14`) | 140 | 1 | Provisional — need N≥2 **or** watch activity-list UI cross-check |
| firmware | _(fill)_ | — | Re-freeze on firmware change |

### Owner checklist — must-seed Outdoor Run

- [ ] ≥2 min Outdoor Run with GPS lock note (yes/no only)
- [ ] Sync after serialize idle; record type / hints / tag dump (id+len)
- [ ] If dataCount>0 → Data probe (presence only)
- [ ] If paceCount>0 → Pace cmd probe (presence only)
- [ ] GPS file observe (filename pattern / present|absent — no track commit)
- [ ] Update catalog scores + observation; provisional type freeze

### Owner checklist — must-seed Pool swim

- [ ] ≥2–3 min Pool, ≥2–4 laps
- [ ] Sync; type freeze; tags `0x15`–`0x1a` presence
- [ ] If segmentsCount>0 → Swim `0x0e` probe (segment count only)
- [ ] Update catalog; do **not** treat Pace `0x0c` as lap source

---

## Activity / vitals

| Step | Status | Notes |
|------|--------|-------|
| Dump caps: `0x07` cmds `0x0A/0B/0C/0D/0x16/0x17/0x23/0x24/0x2a`, expand temp `0x1d`, `truSleepNewSync` | **Pending** | Tag presence only |
| Enable auto-HR + auto-SpO2; wear ≥4h; activity Sync only | **Pending** | |
| If SpO2/HR empty → reboot → re-sync (budget ≤2) | **Pending** | Then `absent-in-observed-sessions` + score ≤2 |
| Presence rates + unknownTV histogram (tag+len) | **Pending** | |
| FitnessTotals day rollup `0x07:0x03` | **Partial — map started** | `capture:owner-2026-08-07-post-day-reset`: hist + decrypt; watch today 1 kcal / 27 steps → nested `0x83` leaves `0x05`=steps, `0x06`=calories; `0x07` duration/distance TBD; day-anchor TBD. See wire-spec FitnessTotals section |

Battery (session UX): **Done** — `POC-2026-07-18-gate-a-battery`.

---

## Sleep

| Step | Status | Notes |
|------|--------|-------|
| TruSleep ON → night 1 sync messages + files | **Pending** | Night 1 may miss |
| Night 2 preferred before absent | **Pending** | Max 2 nights |
| Optional TruSleep OFF night if no stages | **Pending** | |
| FileDownload sleep_state / sleep_data | **Deferred** until `present` | U6 follow-on |

---

## Kill / continue (recorded)

| Condition | Decision |
|-----------|----------|
| Strength list proven; Data/Pace/Swim/GPS not probed | **Totals-only** for workout follow-on until Outdoor/Pool + hint probes |
| Outdoor / Pool not yet attempted | Catalog honesty SoT proceeds; sport wire-spec sections stay pre-promotion / stub |
| No sleep file after budget | TruSleep FileDownload deferred (U6) — budget not started |
| No step HR after attempt budget | daily HR ≤2 + `absent-in-observed-sessions` — budget not started |
| Indoor / OW skipped for calendar | **Not a plan failure** — explicit deferral |
| Must-seeds incomplete | Freeze what was observed (Strength); pending modes stay `unobserved` |

---

## Rescoring log

| When | Change |
|------|--------|
| 2026-07-18 | Initial scaffold: Strength list **5**/`present`; battery **5**/`present`; Running/Swim/Sleep/vitals mostly `unobserved`; IMU **0** |
| _(next)_ | After Outdoor / Pool / vitals / sleep owner sessions |

---

## Related

- Catalog: `docs/catalogs/gt5-a07-full-metrics.md`
- POC learning: `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md`
- Feasibility: `docs/experiments/gt5-a07-companion-feasibility.md`

# GT5-A07 full metrics catalog (companion emission honesty)

**Device:** Huawei Watch GT 5-A07 (HarmonyOS / VLI-B19)  
**Phone:** Pixel 8a  
**Date:** 2026-07-18  
**Plan:** `docs/plans/2026-07-18-003-feat-gt5-full-metrics-catalog-plan.md`  
**Role:** Companion GO / PIVOT / STOP honesty inventory — **not** a derivation source of truth.

Supersedes workout-only inventory intent from `docs/plans/2026-07-18-002-feat-gt5-workout-data-catalog-plan.md`.

**Evidence session cut:** Includes Gate A/B POC (`capture:POC-2026-07-18-strength-totals`, Gate A battery) plus overnight physio diagnostic `capture:POC-2026-08-16-physio-probe`. Must-seed Outdoor Run / Pool swim remain **pending owner** — see `docs/experiments/gt5-a07-full-metrics-probe-matrix.md`.

---

## Dual-axis legend

| Score | Label | Meaning |
|------:|-------|---------|
| **5** | Proven | Fitness OS Sync observed a real value for that mode/surface |
| **4** | Wire-spec | Owned FOS wire-spec documents SS/CC/tag (cites capture or documented-absence id) |
| **3** | Oracle | GB Huawei implements the surface (family-level) |
| **2** | Claimed | Public matrix / docs claim present; device-dependent — **not** “we looked and missed it” |
| **1** | Unknown | No clear path or conflicting docs |
| **0** | Unavailable | No companion path (e.g. high-rate gyro) |

| Observation | Meaning |
|-------------|---------|
| `unobserved` | No qualifying probe attempt yet |
| `present` | Value/file/tag seen in a qualifying attempt |
| `absent-in-observed-sessions` | Qualifying attempts completed; surface not seen (score stays on claim/oracle axis) |

**Privacy (R2a):** Catalog / experiments record tag presence, lengths, and scores only. Never commit lat/lon, raw GPS tracks, full HR/SpO2 series, or sleep PPG/ACC blobs.

**At-rest (R2b):** Owner-device plaintext accepted this cut; `allowBackup=false`; encrypt-at-rest is follow-up.

---

## Type ID conflict notes (provisional)

FOS UI map and GB enum are **non-authoritative**. Freeze from on-device Totals `0x14` after N≥2 consistent observations (or 1 + watch activity-list UI cross-check). Record firmware beside IDs; re-freeze on firmware change.

| Mode | Seed | GB enum | FOS UI | On-device freeze |
|------|------|--------:|-------:|-----------------|
| Outdoor Run | Must | 1 | 2 | **pending** (`unobserved`) |
| Indoor Run | Opportunistic | 5 | 5 | deferred / `unobserved` |
| Strength | Must | — | — | **140** (N=1 Gate B; UI cross-check pending for N≥2 rule) |
| Pool swim | Must | 6 | 6 | **6** (N=1 owner 25m pool 2026-07-23; type=`0x14` + poolLength cm + laps) |
| Open water | Opportunistic | 8 | 8 | deferred / `unobserved` (was wrongly shown for type 6 before freeze) |

Firmware string for freeze table: **not recorded in Gate A interrupt matrix** — fill on next probe (`docs/experiments/gate-a-interrupt-matrix.md`).

---

## S1 — Running (Outdoor + Indoor)

| Field | Surface | Outdoor score | Outdoor obs | Indoor score | Indoor obs | Notes |
|-------|---------|--------------:|-------------|-------------:|------------|-------|
| type (`0x14`) | Totals | **1** | `unobserved` | **1** | `unobserved` | Must-seed Outdoor pending |
| number, start, end, duration | Totals | **3** | `unobserved` | **3** | `unobserved` | Strength path ≠ mode proof |
| calories, distance, steps | Totals | **3** | `unobserved` | **3** | `unobserved` | |
| elev / altitude tags | Totals | **3** | `unobserved` | **3** | `unobserved` | Indoor unlikely |
| run pace zones `0x50`–`0x5a` | Totals | **3** | `unobserved` | **3** | `unobserved` | |
| HR peaks / load / recovery | Totals | **3** | `unobserved` | **3** | `unobserved` | Peaks tag ≠ Pace cmd |
| Data samples HR/speed/cadence/form | `0x17:0x0a` | **3** | `unobserved` | **3** | `unobserved` | if dataCount>0 |
| Pace blocks | Pace cmd `0x17:0x0c` | **3** | `unobserved` | **3** | `unobserved` | if paceCount>0 |
| GPS track | FileDownload | **2** | `unobserved` | **2** | `unobserved` | Expect outdoor observe / indoor absent |
| High-rate IMU | — | **0** | n/a | **0** | n/a | R11 — no companion path |

**Opportunistic Indoor Run:** deferred until Outdoor type collides or GPS/elev needs contrast. Not a plan failure.

---

## S2 — Strength

| Field | Surface | Score | Observation | Notes |
|-------|---------|------:|-------------|-------|
| type=`140` | Totals `0x14` | **5** | `present` | `capture:POC-2026-07-18-strength-totals` — workout `#2`, ~112s |
| number, start, end, duration | Totals | **5** | `present` | Same capture; wire-spec `huawei-br-gt5-gate-a.md` + enrichment |
| calories, distance, steps | Totals | **3** | `unobserved` | Optional tags in Gate A list contract; values not in POC log — no score **4** until tag dump cites capture |
| HR peaks (TLV `0x0c` under Totals) | Totals | **3** | `unobserved` | Tag dump pending |
| load / recovery HR (`0x66`) | Totals | **2** | `unobserved` | Notes: oracle up to 3 |
| Data HR series | `0x17:0x0a` | **3** | `unobserved` | Force-probe if dataCount>0 — not done this cut |
| Pace cmd / Swim / GPS / set-rep | — | **0**–**2** | `unobserved` | Expect absent; set-rep **0** |

---

## S3 — Swimming (Pool + Open water)

| Field | Surface | Pool score | Pool obs | OW score | OW obs | Notes |
|-------|---------|-----------:|----------|---------:|--------|-------|
| type (`0x14`) | Totals | **1** | `unobserved` | **1** | `unobserved` | Must-seed Pool pending |
| swimType, strokes, strokeRate, avgSwolf | Totals | **3** | `unobserved` | **3** | `unobserved` | tags `0x15`–`0x1a` family |
| poolLength (cm), laps | Totals | **3** | `unobserved` | **3** | `unobserved` | OW unlikely |
| Swim segments | `0x17:0x0e` | **3** | `unobserved` | **3** | `unobserved` | Lap surface = **`0x0e`**, not Pace cmd |
| Pace cmd `0x17:0x0c` as lap source | — | **1** | `unobserved` | **1** | `unobserved` | Wrong surface for swim laps |
| Data HR/swolf/strokeRate | `0x17:0x0a` | **2** | `unobserved` | **2** | `unobserved` | Notes: up to 3 if oracle |
| GPS | File | **2** | `unobserved` | **2** | `unobserved` | Pool unlikely; OW observe |

**Opportunistic Open water:** deferred until Pool type collides or GPS needs OW observe.

---

## S4 — Sleep / TruSleep

| Field | Surface | Score | Observation | Notes |
|-------|---------|------:|-------------|-------|
| begin/end (messages `0x07:0x0C`/`0x0D`) | FitnessData | **3** | `unobserved` | Night budget not started |
| begin/end (`sleep_state.bin`) | FileDownload | **3** | `present` (`POC-2026-08-11-trusleep-fd`, 528 B) | Intervals parse pending Health match |
| stages light/deep (TruSleep off) | `0x0D` | **2** | `unobserved` | |
| stages REM+ (HarmonyOS 5 claim) | contested | **2** | `unobserved` | |
| ACC ~1/min activity bytes | `sleep_data.bin` TAG_ACC | **3** | `present` (file sizes observed; tags unparsed) | **Not** high-rate IMU; `POC-2026-08-11-trusleep-fd` 694564 B init; `POC-2026-08-16-physio-probe` transfer 68172 B |
| PPG compressed | `sleep_data.bin` TAG_PPG | **3** | `present` (file sizes observed; tags unparsed) | Overnight-summary **keys empty** on 2026-08-16 observe |
| Overnight HRV / sleep HR / RR / sleep SpO₂ | dict / `SLEEP_DETAILS` / `sleep_data` keys | **2** | `absent-in-observed-sessions` | `ABSENT-overnight-summary` `ABSENT-companion` `capture:POC-2026-08-16-physio-probe`. Watch Sleep health tiles **present** (Health app not opened). Do not promote companion summaries |
| Sleep score | watch Sleep tile | **2** | watch-ui `present` | Companion dict/sleep_data keys empty — not a companion SoT |
| High-rate IMU/PPG dump | — | **0** | n/a | R11 |

Enable: `0x07:0x16`. File svc: `0x2c` if `truSleepNewSync` else `0x0a`.

---

## S5 — Heart rate

| Stream | Codes | Score | Observation | Store (follow-on) |
|--------|-------|------:|-------------|-------------------|
| Daily interval HR | `0x07:0x0B` bitmap `0x40`; enable `0x07:0x17` | **2** | `present` (`interval-proxy`, diagnostic only) | `capture:POC-2026-08-16-physio-probe` — counts only; product Sync still skips `0x0B`; not overnight-summary |
| Workout peaks | Totals TLV `0x0c` under `0x17:0x08` | **3** | `unobserved` | workout (Strength tag dump pending) |
| Recovery HR blob | Totals TLV `0x66` | **2** | `unobserved` | workout |
| Workout samples | Data bit0 | **3** | `unobserved` | workout samples |
| Resting HR history | cap `0x07:0x23` only in GB | **1** | `unobserved` | none until frames |
| Live overlay / realtime | GATT / `0x17:0x17` | **0** | n/a | out of scope as history |

**Never merge** workout sample HR into daily minute HR (different clocks/density).

SpO2 shares step containers (bitmap2 `0x01`); enable `0x07:0x24`.

---

## S6 — Other metrics (must / should / defer)

| Metric | Surface | Score | Observation | Scope | Outcome served |
|--------|---------|------:|-------------|-------|----------------|
| Steps / cal / dist interval | `0x07:0x0B` | **3** | `unobserved` | **Must** | Companion daily activity honesty |
| SpO2 interval | same + enable `0x24` | **3** | `unobserved` | **Must** | GO evidence vs matrix overclaim |
| Fitness totals day | `0x07:0x03` | **2** | `unobserved` | **Must** | Day rollup path exists or absent |
| Battery | `0x01:0x08` | **5** | `present` | **Must** | Gate A post-bind + reconnect; `capture:POC-2026-07-18-gate-a-battery` — level tag `0x01` |
| Skin temperature | enable `0x2a` + P2P | **3** | `unobserved` | **Should** | Catalog only; no fetch this plan |
| VO₂-like (maxMET `0x10`) | Workout Totals | **2** | `unobserved` | **Should** | Catalog only |
| Stress / emotions / PAI | matrix only | **0** | `unobserved` | **Defer** | Avoid false companion claims |
| Overnight HRV / RR / sleep SpO₂ | dict + `sleep_data` keys | **2** | `absent-in-observed-sessions` | **Must (physio POC)** | `ABSENT-overnight-summary`; watch UI present. See S4 |
| Raw high-rate IMU | — | **0** | n/a | Catalog only | Explicit non-goal |
| Step unknownTVs | unmapped bits | **1** | `unobserved` | Probe | Future contract discovery |

Battery was inventoried as wire-spec **4** before POC level parse; on-device log `post-bind: battery ok level=…` elevates list scalar to **5**. Async battery updates remain oracle/claim until separately captured.

---

## IMU honesty (R11)

| Claim | Score | Observation |
|-------|------:|-------------|
| High-rate raw accelerometer / gyroscope via companion | **0** | n/a |
| TruSleep ACC ~1/min activity bytes | **3** | `unobserved` (family oracle) |

---

## Kill / continue (this cut)

| Signal | Status |
|--------|--------|
| Strength Totals list | **Continue** — proven; enrichment tag dump still open |
| Outdoor Run / Pool must-seeds | **Pending** — do not block catalog honesty SoT; block sport-specific wire-spec promotion |
| Workout Data / Pace / Swim / GPS | **Totals-only follow-on** until hints + seeds observe non-zero counts / files |
| Daily HR / SpO2 | Interval HR **diagnostic present** (`interval-proxy`); product Sync still skips daily_hr; SpO2 interval companion still unobserved |
| Sleep files | `sleep_state` product SoT; `sleep_data` diagnostic file-present without overnight-summary keys |
| Indoor / Open water | **Explicit deferral** (opportunistic) — not a plan failure |
| Overnight HRV / RR / sleep HR / sleep SpO₂ companion summaries | **ABSENT-overnight-summary** after dict + sleep_data + path-2; watch UI present; Health not opened |

---

## Related docs

| Doc | Role |
|-----|------|
| `docs/experiments/gt5-a07-full-metrics-probe-matrix.md` | Probe checklist + session log |
| `docs/wire-specs/huawei-br-gt5-gate-a.md` | Gate A + Gate B list Totals |
| `docs/wire-specs/huawei-br-gt5-gate-b-enrichment.md` | Workout enrichment envelopes |
| `docs/wire-specs/huawei-br-gt5-fitness-data.md` | FitnessData family (pre-promotion) |
| `docs/wire-specs/huawei-br-gt5-sleep-files.md` | Sleep FileDownload (`POC-2026-08-11-trusleep-fd`) |
| `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md` | POC proof |

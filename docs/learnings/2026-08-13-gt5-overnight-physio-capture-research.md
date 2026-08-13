# Research digest: GT5 overnight physio capture (dict / file path)

**Date:** 2026-08-13  
**Status:** Research complete enough to plan a **bounded capture POC** — not product UI  
**Handoff for planning/implementation:** `docs/handoffs/2026-08-13-gt5-physio-dict-file-capture-handoff.md`  
**Parallel track (do not mix):** Hooper-4 feel upgrade — `docs/handoffs/2026-08-13-hooper4-feel-upgrade-handoff.md`  
**External PRD (product north star, not this POC’s acceptance):** owner Downloads `Fathom_GT5_Recovery_Analytics_PRD.md` (not in repo)

---

## 1. Why this research happened

After TruSleep file SoT for sleep **timing**, the next recovery bet needs overnight physiology:

| Signal | Role in recovery science |
|--------|---------------------------|
| Overnight / sleep HR → RHR trend | Autonomic + Polar-style ANS charge input |
| HRV (prefer LnRMSSD / nightly avg) | Personal-baseline recovery; 7-day roll + ~28-day band |
| Respiratory rate (RR) | Secondary ANS / anomaly (Polar weights it least) |
| SpO₂ | Anomaly / respiratory layer — **not** day-to-day recovery score driver |

Product direction locked in brainstorm (separate from this POC):

- Personal baseline + deviation + explainability (no opaque “Recovery 73” early)
- P4 morning state later = **state + contributors only** (no hard/easy coaching until training-load parallel work)
- Subjective Hooper-4 (sleep quality, fatigue, soreness, stress) runs **in parallel** — watch cannot supply DOMS
- Baseline can show **early** at ~7 nights; mature ~28 — not a silent 28-day wait

---

## 2. Scientific minimum (context for what we must eventually capture)

Evidence-backed day-to-day battery is **mixed**:

1. **Subjective Hooper quartet** — often more sensitive than biomarkers (Saw et al. BJSM 2016)
2. **Sleep quantity + regularity** — already largely from TruSleep timing SoT
3. **Overnight HR + HRV vs personal baseline** — 7-day roll, SWC ≈ 0.5× individual SD; Polar uses ~first 4h after sleep onset for ANS charge
4. **Coarse training context** — later (P5); not this POC

SpO₂ / breathing-events / deep-REM % are **not** required to claim a scientific go/no-go minimum; they are anomaly or trend layers.

Key refs (non-exhaustive):

- Saw et al. — subjective vs objective athlete monitoring ([PubMed](https://pubmed.ncbi.nlm.nih.gov/26423706/), [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC4789708/))
- Hooper & Mackinnon wellness index — sleep quality, stress, fatigue, DOMS
- Polar Nightly Recharge white paper — 28-day baseline; HR + RMSSD + breathing in early sleep window
- HRV-guided training metas — rolling averages + individual SWC; nocturnal HRV usable
- Wearable staging caveats — stages = trends, not clinical SoT

---

## 3. In-repo GT5-A07 reality (verified constraints)

| Area | State |
|------|--------|
| Sleep timing SoT | TruSleep `sleep_state.bin` gap-merge; shipped on `feat/recovery-sleep-detail` |
| `sleep_data.bin` | **Present** on device (~694564 B / ~678 KiB); **not downloaded in current cut**; parse deferred |
| Message-path stages | Transitional attach onto file windows; often thin — not TruSleep-owned stages |
| Continuous / daily HR on Sync | Recently **stripped** from sleep detail / Sync auto-pull on SoT branch — may need re-arm for physio probes |
| Auto SpO₂ enable | Arm path exists; series largely **unobserved** |
| Stress / HRV / sleep RR / emotions / PAI | Catalog **score 0** / `unobserved` / **Defer** until capture |
| `SLEEP_DETAILS` extras | Explicitly out of product until GT5-A07 capture (`docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md` R9) |

Primary docs:

- `docs/catalogs/gt5-a07-full-metrics.md`
- `docs/wire-specs/huawei-br-gt5-fitness-data.md`
- `docs/wire-specs/huawei-br-gt5-sleep-files.md`
- `docs/experiments/gt5-a07-full-metrics-probe-matrix.md`
- `docs/handoffs/2026-08-12-trusleep-file-sot-shipped-stages-handoff.md`
- `docs/learnings/2026-07-22-community-prior-art.md` (older; workout/framing focused)

---

## 4. Community prior art (what others did)

### 4.1 Why “nobody did GT5 recovery” — and who did it elsewhere

Recovery analytics **do** exist on WHOOP / Oura / Polar / Garmin (first-party) and on better-documented open protocols. Huawei GT5 is underserved because: closed LPv2 + HiChain, split data pipes (messages vs FileDownload vs dict), and open-source energy skewed to bands / Fit / older GT. A **local explainable recovery companion without Health** is the rare gap — not the idea of recovery scores.

### 4.2 Gadgetbridge (behavioral oracle only — no AGPL paste)

- Feature matrix: HR, resting HR, SpO₂, stress, HRV listed as **supported on some Huawei devices** ([docs](https://gadgetbridge.org/basics/topics/huawei-honor/))
- Sleep breathing awareness: **configure / no sync** in public docs
- SpO₂ tip: enable auto-measure then often need **watch reboot** if series empty ([specifics](https://gadgetbridge.org/internals/topics/huawei-honor-specifics/))
- TruSleep stages: newer HarmonyOS 5+ paths improving; historically begin/end-only in older docs
- **Does not prove GT5-A07 HRV/RR** — treat as checklist for probes

### 4.3 Huawhoop — closest recovery prior art ([GitHub](https://github.com/Kuberwastaken/Huawhoop))

- Device: **Huawei Band 10** (not GT5)
- Overnight HRV SoT: dictionary file `sequence_data/SLEEP_DETAILS` during full sync
- Reported fields: `avgHrv`, HRV baselines, sleep score, SpO₂ summary, breath rate, avg heart rate, stages
- Secondary: live ~62s RRI window for stress calibration / experimental live HRV — **not** overnight SoT
- Sample preview shape (sanitized):

```json
{
  "route": "sequence_data/SLEEP_DETAILS",
  "summary": {
    "avgHrv": 64,
    "avgHeartRate": 58,
    "avgOxygenSaturation": 98,
    "avgBreathRate": 14,
    "sleepScore": 86,
    "sleepEfficiency": 94
  }
}
```

**Implication:** Path 1 for Fathom should prioritize finding the GT5 equivalent of this sleep-sequence / dictionary download — **re-prove on GT5-A07**; Band 10 success is a lead, not a transfer.

### 4.4 Other

| Project | Role |
|---------|------|
| Easterhegg / huawei-lpv2 / psolyca | LPv2 framing & Health RE bibliography |
| huawei-health-mcp | **Cloud** Health Kit — wrong architecture for Fathom companion |
| Official Huawei Health / Kit | Documents post-sync models; not LPv2 wire |

---

## 5. Two capture paths (decision locked)

| Path | Mechanism | Likely yields | Decision |
|------|-----------|---------------|----------|
| **1. Dict / file** | `SLEEP_DETAILS` / sequence dict and/or TruSleep `sleep_data.bin` | **HRV, RR, sleep SpO₂, sleep HR summaries** (if GT5 emits) | **Do this first** |
| **2. FitnessData intervals** | Enable auto-HR + auto-SpO₂ → `0x0B` Sync | Interval HR (± SpO₂); weak for RMSSD alone | Parallel/later if path 1 thin |
| Live RRI | Active measurement window | Stress enable / experimental HRV | Optional later; not morning SoT |

Further desk research has diminishing returns without on-device capture.

---

## 6. POC success definition (for planning)

**In scope**

- Availability matrix per metric: present / absent / partial / unit / timestamp semantics / source pipe
- Privacy-safe fixtures (tag+len, redacted field maps — **never** commit PPG/ACC bodies or full SpO₂/HR series to git)
- Wire-spec / catalog / probe-matrix updates with `capture:…` or `ABSENT-…`
- Clear answer: can Fathom ground overnight HRV / RR / sleep SpO₂ / sleep HR on GT5-A07 via dict/file?

**Out of scope**

- Recovery UI, baselines UI, P4 composite, charts productization
- Hooper-4 implementation (parallel agent)
- Training-load engine / intensity coaching
- Inventing TruSleep stages from `sleep_state` flags
- AGPL paste from Gadgetbridge

**Exit criterion:** every target metric has a documented source field (or honest ABSENT) for GT5-A07 — matching recovery PRD Phase 0 spirit.

---

## 7. Suggested probe order (planning input)

1. Inventory FileDownload / dict / sequence capabilities already in companion + GB behavioral names (no paste)
2. Attempt sleep-sequence / `SLEEP_DETAILS` (or GT5 equivalent) download in a Sync or diagnostic probe
3. If dict thin/absent: resume `sleep_data.bin` download (currently skipped) + header/structure observe (privacy-gated)
4. Cross-check Health UI for same night (HRV / RR / SpO₂ / sleep HR) — presence only
5. Promote catalog rows; write ABSENT where empty after budget
6. Only then: optional path-2 interval HR/SpO₂ enable→wear→sync (+ reboot for SpO₂)

---

## 8. Branch / codebase notes for the next agent

- TruSleep FileDownload + sleep SoT work lives primarily on **`feat/recovery-sleep-detail`**
- Current companion skips downloading `sleep_data.bin` until parse cut (`docs/wire-specs/huawei-br-gt5-sleep-files.md`)
- Continuous HR was removed from sleep detail on that line — do not silently reintroduce product HR charts in this POC; diagnostic capture is fine if gated
- Privacy rules in catalog R2a remain binding

---

## 9. Next step

→ Another agent: `/ce-plan` (or equivalent) from  
`docs/handoffs/2026-08-13-gt5-physio-dict-file-capture-handoff.md`  
using this digest as research SoT.

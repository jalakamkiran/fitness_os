# Handoff: GT5 overnight physio capture — dict / file path POC

**Date:** 2026-08-13  
**Status:** Ready to **plan** (then probe) — research digested; Band 10 lead ≠ GT5 proof  
**Research SoT:** `docs/learnings/2026-08-13-gt5-overnight-physio-capture-research.md`  
**Branch likely:** `feat/recovery-sleep-detail` (TruSleep FileDownload + sleep SoT)  
**Parallel (do not bundle):** Hooper-4 feel — `docs/handoffs/2026-08-13-hooper4-feel-upgrade-handoff.md`

Paste this doc + the research digest into a new chat. Prefer **`/ce-plan`** first, then implement/probe. Do not ship recovery charts in this cut.

---

## Goal / done means

Prove whether GT5-A07 can supply overnight recovery physiology via **dictionary / TruSleep file** paths:

| Metric | Target from community lead |
|--------|----------------------------|
| HRV | e.g. `avgHrv` (nightly summary) |
| Sleep / overnight HR | e.g. `avgHeartRate` |
| Respiratory rate | e.g. `avgBreathRate` |
| SpO₂ (sleep summary) | e.g. `avgOxygenSaturation` |

**Done** = GT5-A07 **availability matrix** + privacy-safe fixtures + catalog/wire-spec/probe-matrix updates (`capture:…` or `ABSENT-…`). Not a recovery product UI.

---

## Why this path first

- [Huawhoop](https://github.com/Kuberwastaken/Huawhoop) (Band 10) got overnight HRV/RR/SpO₂/sleep HR from `sequence_data/SLEEP_DETAILS` during full sync — closest prior art to Fathom’s recovery needs  
- Fathom already observed **`sleep_data.bin` present (~678 KiB)** but currently **skips download** until parse  
- FitnessData interval HR/SpO₂ (path 2) is secondary — good for series, weak alone for RMSSD  
- Desk research is past the point of diminishing returns without capture  

Full context: research digest §4–§7.

---

## Product / process locks

| Lock | Rule |
|------|------|
| Scope | Capture / availability POC only |
| Path order | Dict / `SLEEP_DETAILS`-class first; then `sleep_data.bin`; path-2 intervals only if needed |
| Honesty | No product claims for HRV/RR/SpO₂ until capture promotes catalog |
| Privacy | Never commit PPG/ACC blobs, full HR/SpO₂ series, or sleep_data bodies to git — tag+len + redacted field maps only |
| AGPL | Gadgetbridge = behavioral oracle only — **no paste** |
| Device | Re-prove on **GT5-A07**; Band 10 sample JSON is a lead only |
| UI | No P4 recovery state, no baseline charts, no intensity coaching in this cut |
| Parallel | Hooper-4 and training-load stay other agents |

---

## Starting points in-repo

| Artifact | Why |
|----------|-----|
| `docs/learnings/2026-08-13-gt5-overnight-physio-capture-research.md` | Full research + science + community |
| `docs/wire-specs/huawei-br-gt5-sleep-files.md` | FileDownload SM; sleep_state live; sleep_data skipped |
| `docs/wire-specs/huawei-br-gt5-fitness-data.md` | `0x0B` HR/SpO₂; stress/HRV deferred |
| `docs/catalogs/gt5-a07-full-metrics.md` | Scores: HR/SpO₂ unobserved; HRV/RR **0** |
| `docs/experiments/gt5-a07-full-metrics-probe-matrix.md` | Probe budget patterns (incl. SpO₂ reboot tip) |
| `docs/handoffs/2026-08-12-trusleep-file-sot-shipped-stages-handoff.md` | Current sleep SoT; stages thin; sleep_data follow-up |
| `android/.../HuaweiFileDownload.kt` (on recovery branch) | Live FD collaborator |
| Huawhoop sample | `latest_sleep_sequence_preview.json` field names for comparison |

---

## Suggested plan shape (for `/ce-plan`)

Keep units small and exit-gated:

1. **U1 — Inventory**  
   Map companion FileDownload + any dict/sequence hooks; list GB behavioral command/file names (names only). Confirm GT5 caps for file/dict services.

2. **U2 — Dict / SLEEP_DETAILS probe**  
   Attempt sleep-sequence dictionary download (Huawhoop-equivalent route). Log route + size + redacted key inventory. Fixture if present.

3. **U3 — `sleep_data.bin` observe**  
   If dict missing/thin: re-enable download of `sleep_data` (currently skipped); observe structure enough to know if summaries/HRV-like fields exist — **no full-body commit**.

4. **U4 — Health cross-check**  
   Same night: which of HRV / RR / SpO₂ / sleep HR appear in Huawei Health UI (presence notes only).

5. **U5 — Catalog + wire-spec promotion**  
   Promote or `ABSENT-…` each metric; update probe matrix.

6. **U6 — Optional path 2** (only if U2–U3 fail for HRV/RR)  
   Auto-HR + auto-SpO₂ enable → wear → Sync; reboot once for SpO₂ empty (GB tip); window overnight if series land.

---

## Acceptance examples (POC)

- AE1. Given Sync/diagnostic probe, when dict or sleep_data is present, logs/fixtures record **route + length + field keys** without payload bodies in git  
- AE2. Given no HRV after budgeted probes, catalog row is **ABSENT / score ≤2** — not left as silent matrix overclaim  
- AE3. FileDownload failure does not wipe TruSleep sleep_state SoT  
- AE4. Plan does not accept recovery UI or “avgHrv chart” as exit  

---

## Risks

| Risk | Mitigation |
|------|------------|
| Band 10 dict route absent on GT5 | Fall through to sleep_data; then path 2; document ABSENT |
| sleep_data is PPG/ACC only, no summaries | Privacy-gate hard; do not invent BPM/HRV from PPG in this POC |
| Re-enabling sleep_data download hurts Sync time/battery | Non-blocking; optional diagnostic flag; size known ~678 KiB |
| Continuous HR stripped on SoT branch | Do not conflate product UI restore with capture; gate diagnostics |
| AGPL contamination | Behavioral notes + clean-room from captures only |

---

## Suggested agent prompt

```text
Read docs/handoffs/2026-08-13-gt5-physio-dict-file-capture-handoff.md
and docs/learnings/2026-08-13-gt5-overnight-physio-capture-research.md.

Run /ce-plan for a bounded GT5-A07 overnight physio capture POC:
dict/SLEEP_DETAILS-class first, then sleep_data.bin observe, then optional
FitnessData HR/SpO2. Exit = availability matrix + privacy-safe fixtures +
catalog/wire-spec updates. No recovery UI, no AGPL paste, no bundling
Hooper-4. Work from feat/recovery-sleep-detail unless plan says otherwise.
```

---

## Related (not this cut)

- Hooper-4 morning wellness: `docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md`  
- Recovery sleep IA (older): `docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md`  
- Community framing prior art: `docs/learnings/2026-07-22-community-prior-art.md`  
- External recovery PRD: Fathom GT5 Athlete Recovery Analytics (owner Downloads; Phase 0 = data audit — this POC)

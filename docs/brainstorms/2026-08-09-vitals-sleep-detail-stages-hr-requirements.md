---
date: 2026-08-09
topic: vitals-sleep-detail-stages-hr
status: ready-for-plan
visual: docs/brainstorms/Sleep metrics.excalidraw
---

# Recovery Sleep — detail, dual HR modes, IA rename

## Summary

Rename the bottom **Vitals** tab to **Recovery** with **Vitals | Sleep** subtabs. Ship Sleep detail from message-path stages plus **windowed continuous HR**, then a **non-blocking TruSleep FileDownload attempt** after sync. Show a TruSleep ↔ continuous-HR toggle only when TruSleep enrich is present. Feel-on-wake survey and month history are in product scope; Quality score and advanced metrics stay locked until captured.

---

## Problem Frame

Vitals already lists sleep sessions (begin/end) from FitnessData `0x0C`/`0x0D`, but stages are discarded before Flutter and there is no session detail. Huawei Health shows overnight HR and richer sleep UI. Continuous HR (`0x0B` bitmap `0x40`) windowed to the session is the honest BPM series; TruSleep FileDownload PPG is denser sensor tape for later analysis — not a free accuracy upgrade until present and owned. Owner Excalidraw (`docs/brainstorms/Sleep metrics.excalidraw`) defines sync → enrich → display-both and Recovery IA; groundedness review locked three honesty guards (order, conditional toggle, Quality/advanced deferred).

---

## Actors

- A1. Owner-athlete: Arms TruSleep/auto-HR, Syncs, reviews Sleep under Recovery
- A2. GT5-A07: Emits sleep messages, optional FileDownload files, continuous HR when armed
- A3. Companion Sync: Single-flight activity Sync; FileDownload exclusive sub-phase after messages

---

## Key Flows

- F1. Activity Sync sleep path
  - **Trigger:** Owner Sync (or auto-sync) when Gate A + session ready
  - **Steps:** sleep messages → persist sessions+stages → step/HR containers → fitness totals → **non-blocking** TruSleep FileDownload attempt if caps allow → idle
  - **Outcome:** Sessions mergeable; HR series available when `0x40` present; FileDownload present|absent recorded honestly
  - **Covered by:** R6–R8, R11–R12

- F2. Post-sync session enrich + display
  - **Trigger:** Sync finished with new/updated sleep sessions
  - **Steps:** Loop sessions → window continuous HR to `[begin,end]` → attach FileDownload refs if present → update today’s Sleep card / detail
  - **Outcome:** Detail can show structure + HR; TruSleep mode available only when enrich landed
  - **Covered by:** R1–R4, R13–R14

- F3. Feel-on-wake survey
  - **Trigger:** First display of a newly synced overnight session without prior survey for that session key
  - **Steps:** Show five-emoji “How do you feel waking up?” → persist once → never re-prompt for that session
  - **Outcome:** Subjective label stored for future recovery analysis
  - **Covered by:** R15

---

## Requirements

**IA**
- R5. Home remains graph-free (brand IA)
- R16. Rename bottom tab **Vitals → Recovery**; Recovery hosts **Vitals | Sleep** top subtabs. Existing Enable/Sync/whole-day HR stay under Vitals subtab. Sleep owns list/detail/history/survey. Food and other Recovery children are out of this cut
- R17. Visual flow SoT: `docs/brainstorms/Sleep metrics.excalidraw` (includes Locked decisions callouts)

**Sleep detail product**
- R1. Sleep list opens a **session detail** for overnight or nap
- R2. Detail shows stage structure from persisted message-path stages when type mapping is honest — **both** hypnogram-style timeline and stage mix (duration/%) when stages exist
- R3. Detail shows **overnight HR** by windowing continuous daily HR to `[begin, end]` (min/avg/max + line when samples exist)
- R4. Absent stages or HR → honest empty copy; never invent REM/deep/BPM
- R13. Prefer **display both** when available: structure + continuous HR on detail; do not force a single exclusive mode
- R14. Optional toggle **TruSleep enrich view ↔ continuous HR** only when TruSleep FileDownload (or other owned TruSleep enrich) is **present** for that session; otherwise no toggle / continuous-HR-only

**Honesty / sync order (locked)**
- R6. Message-path FitnessData stages remain ship SoT for structure
- R11. Sync order (hard): **(1)** sleep messages + persist stages **(2)** window continuous HR when samples exist **(3)** TruSleep FileDownload attempt — **non-blocking**; message+HR UI must not wait on files
- R7. Continuous HR needs auto-HR armed + wear + Sync; first-night miss and empty HR are guided failure modes
- R8. FileDownload is **probe + local side-file/ref** this cut: record present/absent + tag+len; promote wire-spec only with `capture:…` or `ABSENT-…`. No PPG→BPM product claim; no PPG “gallery” until decode owned
- R12. Quality score on today’s card is **deferred** until an owned score source exists; show date, duration/sleep time, and stage/HR honesty instead. “Advanced sleep metrics (unlock soon)” stays locked UI chrome only — no fake metrics
- R9. Sleep breathing / RR / dict `SLEEP_DETAILS` extras out of product until GT5-A07 capture
- R10. Privacy: never commit PPG/ACC blobs or full series to repo logs; presence/tag+len only in experiments

**Survey + history**
- R15. Feel-on-wake five-emoji survey once per newly synced session (skip if already answered for that session key); stored locally for future recovery metrics
- R18. Historic sleep: month window default, prev/next month arrows, scrollable session cards (same card shape as today); charts deferred

---

## Acceptance Examples

- AE1. **Covers R11, R8.** Given FileDownload times out, when Sync finishes, sessions+stages+windowed HR still display; FileDownload marked absent/failed without wiping sleep
- AE2. **Covers R14.** Given no TruSleep file for a session, detail shows continuous HR / stages only — no TruSleep↔HR toggle
- AE3. **Covers R14, R13.** Given FileDownload present for a session, detail can show both and may expose the toggle
- AE4. **Covers R15.** Given first open of a new overnight session, survey shows once; reopening does not re-prompt
- AE5. **Covers R16.** Recovery tab shows Vitals | Sleep; Enable/Sync/HR remain under Vitals; Sleep hosts list/detail

---

## Success Criteria

- Owner opens Recovery → Sleep, sees today’s session, detail with stages + windowed HR when emitted
- FileDownload attempt never blocks message+HR ship path; night probe can promote or ABSENT catalog rows
- Toggle only appears when TruSleep enrich exists
- Downstream plan does not invent Quality score, breathing charts, or PPG→BPM as v1 acceptance

---

## Scope Boundaries

- No on-phone re-staging / open TruSleep algorithm
- No PPG→BPM derivation as product SoT
- No stress / HRV / emotions / PAI / sleep RR product claims until capture
- No Home sleep graphs
- No Food under Recovery this cut
- Nap vs overnight labeling remains display-only per existing rules
- Custom calendar picker deferred (month arrows only)

---

## Key Decisions

- **Sync order:** messages → window continuous HR → non-blocking FileDownload (locked)
- **Sleep HR SoT for BPM:** window continuous HR (locked)
- **Toggle:** conditional on TruSleep enrich present (locked)
- **Charts v1:** hypnogram + stage mix + windowed HR line/stats (locked; resolves prior R2 open question)
- **IA:** Vitals → Recovery with Vitals | Sleep (locked Excalidraw delta vs prior Home|Vitals|Workouts shell — Sleep moves under Recovery)
- **Quality / advanced metrics:** deferred / locked chrome (locked)
- **Tonight:** owner wears TruSleep + auto-HR; tomorrow evening analyze FileDownload vs Health (execution experiment, not plan blocker)

---

## Dependencies / Assumptions

- Stage TLV observed (`POC-2026-07-18-activity-sync-sleep`); type→light/deep/REM mapping still needs lock vs watch/Health during implement/probe
- Prior sleep POC had no `0x40` HR — overnight HR depends on enable → wear → Sync
- Brand IA Home|Vitals|Workouts updated by R16 for bottom label only; Home body rules unchanged
- Visual: `docs/brainstorms/Sleep metrics.excalidraw`

---

## Outstanding Questions

### Resolve Before Planning

_(none — chart set, order, toggle, IA rename locked 2026-08-09)_

### Deferred to Planning / Implementation

- [Affects R2][Needs research] GT5-A07 stage `wireType` → light / deep / REM / awake mapping
- [Affects R3][Technical] Persist stages + optional FileDownload refs (prefs vs side-files)
- [Affects R8][Needs research] Night budget FileDownload present vs absent
- [Affects R16][Technical] Shell NavigationBar label + nested TabBar under Recovery without breaking routes

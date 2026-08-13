---
date: 2026-08-14
topic: swim-stroke-style-capability
status: ready-for-plan
---

# Swim stroke style capability — log-first verify

## Summary

Prove that GT5 pool-swim segments carry per-lap stroke style by force-syncing an existing workout and logging style per lap for comparison against the owner’s remembered set. Style UI and per-stroke improvement stay deferred until that check passes.

---

## Problem Frame

Mixed pool sessions currently surface as session-level **Medley**. The owner swam freestyle, backstroke, and breaststroke in one workout and needs lap-level stroke identity before any per-stroke improvement product makes sense. The wire path and parsers already model per-lap `style`; the gap is an honest capability proof on real GT5-A07 data, not a premature UI.

Community companions (Gadgetbridge) treat swim style as a **per-segment** field alongside distance, duration, strokes, SWOLF, and pace. Huawei documents auto stroke identification on select models and recommends one stroke per lap for accuracy.

It is late evening; waiting for tomorrow’s swim would block the check. Force-sync of an existing Medley (or latest pool) workout is the way to attempt segment re-fetch tonight.

---

## Actors

- A1. Owner-athlete: Knows approximate stroke order for the mixed set; judges log correctness against memory
- A2. GT5-A07: May still hold segment pages for a recent pool workout; may drop them after retention limits
- A3. Fathom workout sync: Force-syncs, parses segments, emits per-lap style logs

---

## Key Flows

- F1. Tonight capability check
  - **Trigger:** Owner starts force workout sync for an existing Medley / latest pool swim
  - **Actors:** A1, A2, A3
  - **Steps:** Force-sync → segments fetch when available → log each lap’s style code and label with workout and lap index → owner compares sequence to memory
  - **Outcome:** Pass (styles present and match memory), fail (mismatch), or blocked (no segments / watch no longer has the workout)
  - **Covered by:** R1, R2, R3, R4

---

## Requirements

**Capability proof**
- R1. Force-sync must be usable tonight so the check is not blocked on tomorrow’s swim.
- R2. When swim segments are present after sync, each lap must be logged with workout identity, lap index, style code, and human-readable stroke label (using the existing stroke map where known).
- R3. Logs must be readable enough for the owner to compare lap order to their remembered set without opening Style UI.
- R4. If force-sync yields no segments (watch dropped the workout, enrichment empty, or timeout), the outcome must be clearly **blocked / empty**, not a silent false pass.

**Truth check**
- R5. “Getting it right” for this slice means the logged style sequence approximately matches the owner’s memory of the set (not a Huawei Health UI parity requirement for v1).

**Handoff after pass**
- R6. Only after a pass (or an explicit owner decision to proceed despite partial data) may follow-on work add Style to Intervals UI. That UI is out of scope for this requirements doc’s delivery.

---

## Acceptance Examples

- AE1. **Covers R2, R3, R5.** Given a mixed Medley workout that re-fetches segments with free / back / breast by lap, when sync completes, logs show those styles in lap order and the owner can confirm against memory.
- AE2. **Covers R4.** Given force-sync where `segmentsCount` is zero or segment fetch returns empty, when sync completes, logs state that no lap styles were available (blocked), not a success claim.
- AE3. **Covers R1.** Given it is overnight before the next swim, when the owner force-syncs, the check can run without waiting for a new pool session.

---

## Success Criteria

- Owner can run force-sync tonight and see either a per-lap style sequence or a clear empty/blocked result.
- A downstream implementer knows: log-first capability is in; Style UI and stroke-type trends are explicitly deferred.
- Pass/fail of the memory check is recorded as the gate before any Style UI work.

---

## Scope Boundaries

- In scope: force-sync path for existing swim workout(s); per-lap style logging; memory-based truth check
- Deferred: Style column / stroke labels in Intervals UI
- Deferred: Per-stroke improvement, trends, or coaching across sessions
- Deferred: Huawei Health lap-label parity as a hard acceptance bar
- Out of scope: Inventing stroke styles when the watch sends none; claiming live underwater stroke correction

---

## Key Decisions

- **Log-first, UI later:** Avoid shipping Style UI on unproven codes.
- **Force-sync tonight:** Unblocks the check without waiting for morning swim.
- **Memory as truth:** Owner’s approximate set plan is the v1 correctness bar.
- **Session Medley stays valid:** Session-level Medley for mixed workouts is expected aggregate behavior; the capability is per-lap style, not replacing the session label.

---

## Dependencies / Assumptions

- Per-lap style is carried on swim segment enrichment (community: style as first column of the swim pace/segment table; Fathom already models lap `style`).
- Force-sync only succeeds if the watch still retains that workout’s segment data.
- Existing Medley workout may currently lack visible intervals in the app; empty segments after force-sync is a possible blocked outcome, not an implementation failure by itself.
- Stroke label map already used in product (Breaststroke / Freestyle / Butterfly / Backstroke / Medley) is the starting vocabulary for logs; unknown codes should still log the raw value.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Technical] How force-sync is exposed in the companion today (button vs reconnect+sync) and whether a one-workout re-enrichment path already exists.
- [Affects R2][Technical] Best log surface for owner inspection tonight (device logs vs in-app debug) without shipping Style UI.
- [Affects R4][Needs research] Whether GT5 still holds segment pages for the specific Medley workout after hours/days.

---
date: 2026-08-09
topic: swim-hypoxic-breath-spo2-awareness
status: seed-continue-in-new-chat
origin_chat: sleep brainstorm pivoted 2026-08-09
---

# Swim hypoxic awareness — breath quality + SpO2 (seed)

## Summary

Explore a Fathom swim innovation: detect when a swimmer’s **breathing load** and/or **body oxygen** is stressed (e.g. long breath-holds, hypoxic sets, or staying under too long) using whatever GT5 can honestly emit — without claiming live underwater SpO2 if the wrist cannot support it. This doc is a **seed for continued brainstorming**; primary scenario and v1 mechanism are not locked yet.

---

## Problem Frame

Pool and open-water athletes often train with intentional breath-holds or push depth/time underwater. Coaches and athletes care whether oxygen stress is rising, but consumer watches rarely give an honest “breath quality / O₂ under load” signal in water. Fathom already owns swim session depth (laps, SWOLF, Bible analytics). The owner idea: if detailed **breath** and **SpO2** were available, Fathom could flag sets where oxygen content is dropping — a distinctive companion insight, not another pace chart.

Reality check from early research: wrist optical SpO2/PPG is unreliable in water (motion, fluid film, perfusion). Huawei SpO2 guidance assumes dry, still measurement. Sleep-derived respiration (TruSleep) is overnight/on-land, not a swim breath-cycle meter. So the innovation may need a **reframed sensor story** (wall/rest SpO2, inferred breath-hold load from stroke/lap structure, etc.) rather than live underwater oximetry on GT5-A07.

---

## Actors

- A1. Owner-athlete (swim-first): Trains pool and/or open water; wants hypoxic / breath-hold feedback
- A2. GT5-A07: May emit workout samples, daily SpO2 intervals, and (unproven) richer vitals — water optical limits apply
- A3. Fathom swim detail / analytics: Surface for any honest hypoxic signal tied to a session or set

---

## Working product bets (not locked)

Candidate mechanisms discussed so far — **pick one primary scenario before planning**:

| ID | Scenario | Mechanism sketch | Honest feasibility on GT5 wrist |
|----|----------|------------------|----------------------------------|
| B1 | Pool hypoxic training | Long breath-holds / hypoxic sets; depth secondary | SpO2 in-stroke unlikely; infer from set structure ± rest SpO2 |
| B2 | Open water / depth | Too deep or too long without air | Needs depth/time; GT5 is not a dive computer |
| B3 | Post-set recovery | SpO2/HR at the wall as oxygen-stress proxy | More plausible if auto-SpO2 samples exist around session |
| B4 | Analytics-only | Infer breath-hold load from stroke/lap timing (no SpO2) | Highest ship odds; no new sensor path |

**Rejected as v1 default unless proven:** live continuous SpO2 while swimming as SoT for “O₂ dropping underwater.”

---

## Requirements (provisional — tighten after scenario lock)

**Honesty**
- R1. Do not claim live underwater SpO2 or TruSleep-style breath cycles during swim unless GT5-A07 capture proves usable samples in that context
- R2. Any hypoxic / breath UI must degrade to honest absent/low-confidence when samples are missing or water-degraded
- R3. Catalog / wire honesty remains SoT: SpO2 is daily-interval enable `0x24` + step-container bitmap path today; swim-workout SpO2 is unverified

**Product direction (once scenario chosen)**
- R4. Tie the insight to an existing swim session (or explicit set breakdown), not a standalone medical SpO2 dashboard
- R5. Prefer athlete-actionable copy (“this set looked hypoxic / recovery SpO2 stayed low”) over clinical apnea diagnosis
- R6. Stay swim-first and brand-consistent: calm instrument, not alarm-theater drowning product (unless owner later repositions)

**Research gates before build**
- R7. Owner probe: does Health or companion sync show SpO2 samples during/after a pool set on GT5-A07?
- R8. Owner probe: any breath/respiration fields on swim workout payloads, or only land/sleep surfaces?
- R9. If in-water SpO2 fails, document `absent-in-observed-sessions` and pivot to B3 or B4 without expanding scope to new hardware

---

## Acceptance Examples

- AE1. **Covers R1, R2.** Given a pool swim with no SpO2 samples in range, when session detail opens, Fathom shows no oxygen-drop claim and explains data absent — not a fabricated desaturation chart.
- AE2. **Covers R4, R5.** Given rest-interval SpO2 (or inferred breath-hold load) captured for a set, when analytics render, the insight is attached to that set/session with confidence language.

---

## Success Criteria

- A clear primary scenario (B1–B4) and one v1 mechanism locked before `/ce-plan`
- Feasibility gated by capture, not marketing
- Downstream agents do not invent underwater SpO2 charts for GT5 without evidence

---

## Scope Boundaries

### Deferred for later

- TruSleep overnight breath RR as a recovery adjunct to swim load
- Dive-computer depth/pressure integrations
- Medical apnea / drowning-detection product positioning

### Outside this product's identity (unless owner unlocks)

- Replacing Huawei Health sleep breathing awareness
- Clinical pulse-oximetry or regulated safety device claims
- Building custom underwater oximeter hardware

---

## Key Decisions

- Sleep brainstorm parked separately: stages + windowed continuous HR for Vitals detail (`docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md`)
- This topic is **swim innovation**, not sleep FileDownload PPG
- Live in-water wrist SpO2 is **skeptical default** pending capture

---

## Dependencies / Assumptions

- Fathom swim Bible / canonical swim session already exists as the natural attachment point
- Auto-SpO2 enable path exists in Vitals Enable set; series not shown in app yet
- Unverified until probe: whether any SpO2 samples land near swim workouts on GT5-A07
- Research refs (external): wrist swim HR/SpO2 accuracy literature; Huawei SpO2 “dry/still” guidance; pool-safety oximeter research (purpose-built bands)

---

## Outstanding Questions

### Resolve Before Planning

- [Affects R4–R6][User decision] **Primary scenario:** B1 pool hypoxic, B2 OW/depth, B3 post-set recovery SpO2, or B4 analytics-only breath-hold load?
- [Affects R5][User decision] Is the job **training insight** (hypoxic sets) or **safety warning** (dangerously long underwater) — different product identity?
- [Affects R1][User decision] Smallest valuable v1 if SpO2 never works in water: wall recovery only, stroke-inferred load only, or park the idea?

### Deferred to Planning

- [Affects R3, R7][Needs research] GT5-A07 SpO2 emission during/after pool swim (presence, density, trust vs Health)
- [Affects R8][Needs research] Workout payload fields for breath / SpO2 vs daily vitals only
- [Affects R4][Technical] Where the insight lives in IA (swim detail card vs set table vs post-swim summary)

---

## How to resume (next chat)

1. Open a **new chat**
2. Run `/ce-brainstorm` with: continue from `docs/brainstorms/2026-08-09-swim-hypoxic-breath-spo2-awareness-requirements.md`
3. Resolve the three **Resolve Before Planning** questions first (scenario → job-to-be-done → smallest v1)
4. Then synthesize approaches and update this file to `status: ready-for-plan` (or park)

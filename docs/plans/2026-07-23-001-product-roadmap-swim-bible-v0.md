---
title: Product roadmap — Swim analytics → Bible v0
status: active
horizon: 5 weeks (2026-07-23 → 2026-08-27)
owner_mode: auto-drive (owner = probes + gates only)
---

# Fitness OS product roadmap (Swim Bible v0)

**North star:** A local-first mobile app for detailed swimming analytics that improves athletic performance. Nothing more.

**Locked bets**

- Direct Huawei GT5 LPv2 companion only (**Health Kit / Health Service Kit dropped**)
- Bible pipeline: Evidence → Diagnosis → Recommendation → LLM Coach (LLM explains only)
- Owner bandwidth low → agents auto-drive; owner does swim probes + PASS/FAIL only

**Interactive view:** Cursor canvas `fitness-os-swim-roadmap.canvas.tsx`  
**Tracking:** `docs/status/AUTO_DRIVE.md` + Notion Dig-deeper STATUS  
**Product Head thread:** https://chatgpt.com/g/g-p-6a60ffa173a4819192ab40fb9bce162a-huawei-watch/c/6a6103d3-51e0-83e9-8a49-a2f99c62a496

## Where we are

| Milestone | Status |
|-----------|--------|
| Gate A pair / reconnect (no Health runtime) | Done |
| Gate B Count → Totals history | Done |
| Dig-deeper enrichment fetch `0x0e → 0x0a → 0x0c` + lap UI | Done |
| Daily HR series + vitals sparkline | Done |
| Health Kit path | Explicitly dropped |
| W0 25m pool probe | **PASS** (2026-07-23) |
| W1 Canonical swim + P0 metrics | **Done** (2026-07-23) |
| W2 Session analytics UI | **Done** (2026-07-23) |
| W3 Trends + diagnosis v0 | **Done** (2026-07-23) |
| W4 Recommendations + coach shell | **Done** (2026-07-24) — Gemini API |
| W5 Harden + Bible v0 freeze | **Next** |

## Week plan

### W0 — Probe gate (Jul 23–24)

**Outcome:** Decide if enrichment justifies Bible analytics.

**Status:** **PASS** (owner 25m pool #11, 2026-07-23). Totals match watch; segments usable; type 6 = pool; pool length cm→m. Length row count PARTIAL vs reported laps (honest flag in W1).

### W1 — Canonical swim + P0 metrics (Jul 24–30) — **closed early 2026-07-23**

**Outcome:** Segments/samples are first-class; P0 metrics computable.

**Done when**

- Canonical swim session persisted (laps + optional HR samples)
- P0: avg pace, lap pace/splits, strokes, SWOLF, stroke rate (derived OK)
- In-workout HR if samples exist; else explicit PARTIAL flag
- Fixture tests; no AGPL paste

**Shipped:** `CanonicalSwimSession` side-files, `computeSwimP0`, detail **P0 metrics** block, unit fixtures from #11 shape.

### W2 — Session analytics UI (Jul 31 – Aug 6) — **closed early 2026-07-23**

**Outcome:** Post-swim screen answers where pace/efficiency broke.

**Done when**

- Lap decay / consistency
- SWOLF + stroke efficiency per lap
- HR zones/drift if samples (hidden otherwise)
- Confidence High/Med/Low on claims

**Shipped:** `analyzeSwimSession` (interval-first), detail **Session analytics** card with confidence chips + per-interval SWOLF/str/25m; HR physiology omitted without sample stream. Length-vs-interval still pending owner controlled probe.

### W3 — Trends + diagnosis v0 (Aug 7–13) — **closed early 2026-07-23**

**Outcome:** Multi-session trends + deterministic diagnoses.

**Done when**

- Pace / SWOLF / volume trends
- Training-load lite
- Diagnosis v0: pacing, fatigue onset, efficiency (Evidence → Diagnosis)
- Each diagnosis cites metric IDs + confidence

**Shipped:** `buildSwimTrends` / `diagnoseSwimSessions`; workouts **Swim trends** strip; detail **Diagnoses** (session + across-sessions) with metric citations. #11-shaped fixtures fire fatigue_onset + pacing_uneven.

### W4 — Recommendations + coach shell (Aug 14–20) — **closed early 2026-07-24**

**Outcome:** Deterministic recs + LLM that only explains/prioritizes.

**Done when**

- Rec set from diagnosis (allow-listed drills/targets)
- LLM coach shell: explain/prioritize; never invent metrics/drills
- Traceability visible: claim → metric → field → sync surface

**Shipped:** `recommendationsForReport` catalog; `GeminiCoachClient` (gemini-2.0-flash); Coach settings API key screen; detail **Recommendations + coach** with invent-guard on `orderedRecIds`.

### W5 — Harden + Bible v0 freeze (Aug 21–27)

**Outcome:** Weekly loop with low owner attention; freeze v0.

**Done when**

- Reconnect + Sync reliable for weekly use
- One-tap path: Sync → analytics → coach
- Bible v0 acceptance checklist signed
- AUTO_DRIVE defaults for ongoing small fixes

**Owner:** up to two weekly swims; sign Bible v0 yes/no  
**Auto-drive:** reliability, docs freeze, status automation

## Kill switch (after W0)

| Verdict | Meaning | Action |
|---------|---------|--------|
| **PASS** | Laps + strokes/SWOLF + usable timestamps; HR ideal | Run W1–W5 |
| **PARTIAL** | Laps/SWOLF/strokes without HR timeline | Continue with physiology demoted |
| **FAIL** | Totals-only; no laps | **STOP** Bible engines; keep companion; reassess |

## Non-goals (5 weeks)

Health Kit / HMS approval, iOS, GPS productization, run/gym depth, App Store polish, cloud backend, IMU fantasy classifiers.

## Auto-drive contract

Agents ship without waiting when: code + tests + docs stay inside this roadmap, no new product bets, no Health Kit, no iOS.

**Must wait for owner:** swim probes, PASS/PARTIAL/FAIL, usefulness checks, Bible v0 sign-off.

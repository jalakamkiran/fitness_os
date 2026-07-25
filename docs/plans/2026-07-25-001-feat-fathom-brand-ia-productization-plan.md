---
title: "feat: Fathom brand + companion IA productization"
type: feat
status: active
date: 2026-07-25
origin: docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md
---

# feat: Fathom brand + companion IA productization

## Summary

Productize the GT5 companion as **Fathom**: rename user-visible chrome, adopt the locked 3-tab IA (Home | Vitals | Workouts), implement one-shot auto-sync on open/resume, reshape Home into a calm “now” surface, and carry wordmark-led brand + splash motif without shipping always-on FGS sync.

Origin: `docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md`

---

## Problem Frame

Swim Bible analytics and Qwen3 reasoner already work, but the app still presents as “Fitness OS” with a 2-tab shell (Home=pairing, Vitals) and Workouts as a pushed route. Sync is manual-only. Design prototypes under `docs/design/home-prototype/` already show the target IA; Flutter has not caught up.

---

## Requirements Trace

- R1–R3 Brand rename + wordmark/splash split
- R4–R6 Home now-state only
- R7–R9 Workouts sport tabs + swim detail / on-demand reasoner
- R10–R11 One-shot auto-sync; no sticky FGS
- R12–R13 Charts/DS direction (prototype → Flutter follow-through)

---

## Scope Boundaries

### In scope
- User-visible rename to Fathom (Android label, iOS display name, in-app chrome, prototypes)
- Shell: 3 bottom tabs Home | Vitals | Workouts
- Home “now” composition (connection health, vitals snapshot, one swim takeaway, today’s totals)
- One-shot auto-sync on open / resume / session-ready
- Splash brand moment hook (assets may be placeholder until final art)
- Align swim detail reasoner CTA with “on click” (already largely present)

### Deferred
- Sticky always-on FGS / tray sync
- Activity calendar + advanced coach charts (scatter / race overlay) — post-MVP after locked P0 stack
- Run / Strength sport content beyond empty tab scaffolding
- Replacing pairing flows — move pairing into settings / first-run, keep Home calm

### Design package — LOCKED (owner 2026-07-25)
Canonical HTML under `docs/design/` is signed off. Flutter implements against locks; do not reopen without owner unlock.
- Brand/logo/splash: `logo.html`, `assets/discobolus.png`
- Tokens + nav + Home never-list: `design-system.html`, `tokens.css`
- Home + six states: `home-prototype/`, `home-states.html`
- Swim analytics: `swim-analytics.html` (Product Head APPROVED WITH CHANGES — applied)

### Outside identity
- Health Kit reintroduction
- Cloud coach / Gemini as primary reasoner

---

## Key Decisions

1. **Home is not pairing.** Pairing stays reachable (settings / empty-state CTA) but is not the Home tab body. (see origin R4–R5)
2. **Workouts becomes a root tab**, not an AppBar push from Home.
3. **Auto-sync is one-shot**, shared with existing `HuaweiSyncLock` single-flight — never a second sync plane.
4. **Brand assets:** everyday icon/wordmark-led; Discobolus figure splash-only / T in wordmark.
5. **Charts:** locked swim session stack in `swim-analytics.html`; Home stays chart-free.
6. **Branding is a design token system**, not string find-replace — typography, colours, icons, splash, a11y labels, empty states (Design Head must-fix).
7. **Home builds against the final sync lifecycle** — U4 is a dependency for a trustworthy U3, not a retrofit (Design Head).

### Frozen navigation contract (Design Head)

| Tab | Owns |
|---|---|
| Home | Current status + today’s summary |
| Vitals | Physiological trends |
| Workouts | Session history and analysis |

### Home state precedence (must define before U3 build)

Deterministic hierarchy — every state has explicit UI behaviour:

1. Not paired
2. Paired, never synced
3. Sync in progress
4. Sync failed
5. Data available
6. No swim data yet

---

## Implementation Units

### U1. Rename user-visible brand to Fathom (design-token pass)
**Goal:** Owner sees Fathom, not Fitness OS, across chrome **and** brand tokens (not string-only replace).
**Files:** `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `lib/app/app.dart`, pairing/home copy sites, theme/token surfaces, a11y labels, empty states, `docs/design/home-prototype/*.html`
**Tests:** `test/` widget/smoke for app title / shell labels if present; manual launcher check
**Scenarios:**
- Launcher label shows Fathom
- Prototype brand-title shows Fathom
- No user-facing “Fitness OS” remains in primary chrome, empty states, or accessibility labels (pubspec package name may stay `fitness_os`)
- Colour/typography/icon tokens match pool-night DS direction from prototype

### U2. Shell IA → Home | Vitals | Workouts
**Goal:** Match locked bottom tabs; Workouts no longer only a push from Home.
**Files:** `lib/app/shell/app_shell.dart`, `lib/app/shell/app_shell_route.dart`, `lib/app/routing/route_registry.dart`, workout history screen entry
**Tests:** `test/app/shell/` (new or existing) — tab count, labels, IndexedStack children
**Scenarios:**
- Three tabs labeled Home, Vitals, Workouts
- Selecting Workouts shows workout history without leaving shell
- Vitals unchanged as tab body

### U3. Home now-state surface
**Goal:** Home answers “what’s true now” per R4–R6, with the frozen Home state precedence table above.
**Files:** new/refactored home screen under `lib/features/` (prefer dedicated home feature over embedding pairing), widgets for sync pill, vitals snapshot, swim takeaway, today’s totals
**Depends on:** U2, **U4 lifecycle contract** (Home UI binds to real sync states; may stub visuals only after state enum is frozen)
**Tests:** home widget tests for each precedence state + forbidden sections (no graph widgets on Home)
**Scenarios:**
- Each of the six Home states renders defined UI (not paired → no swim data yet)
- Shows connection/sync health, vitals snapshot, one swim takeaway, today’s totals when data available
- Does not render charts, vitals history lists, diagnosis lists, or reasoner settings
- Unpaired empty-state offers path to pairing without becoming a pairing dashboard

### U4. One-shot auto-sync on open / resume / session-ready
**Goal:** R10–R11 without sticky FGS.
**Files:** `lib/app/bootstrap.dart` or app lifecycle observer near `lib/app/app.dart`; workout + vitals sync triggers via existing blocs/`HuaweiSyncLock`
**Depends on:** existing sync single-flight
**Tests:** unit tests for “fires once per resume”; rejects when lock busy; no FGS started
**Scenarios:**
- App open with session-ready → one sync pass attempted
- Resume from background → at most one pass
- Manual Sync still works and shares the lock
- No persistent foreground service added

### U5. Brand splash hook (placeholder-tolerant)
**Goal:** Cold start can show Discobolus→T→Fathom moment; everyday icon stays wordmark-led.
**Files:** splash / launch screen assets, optional Flutter splash package wiring, Android/iOS launch images
**Depends on:** Design Head constraints (geometry/motion budget)
**Tests:** smoke that app launches; splash does not block first frame excessively
**Scenarios:**
- Cold start shows splash brand moment (or approved placeholder)
- App icon is not a full Discobolus figure

### U6. Prototype + docs alignment (continuous)
**Goal:** Design samples stay the living contract with Flutter — not a cleanup pass.
**Files:** `docs/design/home-prototype/*`, status notes in `docs/status/AUTO_DRIVE.md`
**Scenarios:**
- Prototype brand and tab labels say Fathom / Home|Vitals|Workouts
- Prototype Home states mirror the six-state precedence table
- AUTO_DRIVE notes Fathom productization cut
- Prototype updates land in the same PR as matching Flutter IA changes when practical

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Pairing buried after Home reshape | Keep explicit unpaired CTA + settings entry |
| Auto-sync fights manual sync | Reuse `HuaweiSyncLock`; never parallel planes |
| Home shows stale data before sync | Freeze sync lifecycle first; bind Home states to it (Design Head) |
| Logo art not final | Ship wordmark + placeholder splash; gate U5 polish on Design Head must-fixes |
| Chart rewrite scope creep | Prototype direction only this cut; Flutter charts follow-up |
| Flutter diverges from prototypes | U6 continuous with each IA unit |

---

## Execution Order

1. U1 brand token rename (unblocks perception)
2. U2 shell tabs + freeze nav contract in code/docs
3. U4 auto-sync lifecycle (before trusting Home data)
4. U3 Home now-state against that lifecycle
5. U5 splash (after art meets Design Head constraints)
6. U6 continuous alongside U1–U5

---

## Success Criteria

- Owner opens app → Fathom chrome + Home now-state + one auto-sync attempt
- Workouts is a root tab
- No sticky FGS
- Splash/icon rules respected (figure splash-only)
- Origin R1–R13 satisfied against locked design package
- Swim detail matches `swim-analytics.html` IA (invent-guard + on-demand reasoner)

---

## Owner design lock (2026-07-25)

**LOCKED** — owner satisfied with the design package. Flutter productization may proceed.

---

## ChatGPT Design Head review

### Brand/logo (2026-07-25) — LOCKED (owner)
**Canonical:** `docs/design/logo.html` + `docs/design/assets/discobolus.png`

- Wordmark: geometric Fa + Discobolus-as-T + hom; mark on letter baseline; spacing `a · mark · h` (`0.12em`)
- Splash: playable settle animation on logo page
- App icon: letter **F** only

Design Head constraints still apply for production export (small-size legibility, clear-space, no athlete as app icon).

### Plan review (2026-07-25)
**APPROVED WITH CHANGES**

Must-fixes incorporated above:
1. Define Home state precedence (six states) before U3 build
2. Freeze navigation contract (Home / Vitals / Workouts ownership)
3. Treat branding as design tokens, not string replacement

Sequencing notes incorporated:
- U4 before trusting U3 data
- U6 continuous, not cleanup

### Swim analytics — Product Head (2026-07-25) — LOCKED (owner)
**Canonical:** `docs/design/swim-analytics.html`  
**Chat:** APPROVED WITH CHANGES — invent-guard default + overlay normalize + table sync; applied in HTML. Owner signed off 2026-07-25.

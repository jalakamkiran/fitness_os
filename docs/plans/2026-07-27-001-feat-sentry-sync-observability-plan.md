---
title: "feat: Sentry crash and sync observability"
type: feat
status: completed
date: 2026-07-27
---

# feat: Sentry crash and sync observability

## Summary

Add **Sentry Flutter** as the cloud crash + performance SDK so owner sessions can explain Huawei connect/sync stalls and true crashes with scrubbed evidence. Instrument link and OneShotAutoSync phases as Performance transactions; keep soft outcomes (`stuck` / `partial_batch` / `busy`) out of the Issues stream. Privacy scrubbing is a hard gate before any DSN traffic.

---

## Problem Frame

Swimming sync is usable, but connect/sync slowdowns are still diagnosed via adb/`FOS_HUAWEI` logcat — and Flutter Huawei logs are **silent in release**. Hard crashes and hung MethodChannels leave no durable trail. Before investing in sync-speed or prediction-accuracy work, we need cloud-backed evidence of *where* time goes and *what* failed, without shipping MAC/secrets/health payloads.

---

## Requirements

- R1. Capture unhandled Flutter and Android (JVM/NDK) crashes to Sentry in profile/release builds.
- R2. Capture Android ANRs when the main thread freezes during link/sync UI work.
- R3. Emit Performance transactions for OneShotAutoSync pass (workouts then vitals), with link-state breadcrumbs and an optional connect span.
- R4. Soft sync outcomes (`stuck`, `partial_batch`, `busy`, `empty`, schedule rejects) and hung-sync `abandoned` appear as span/breadcrumb context — **not** as crash Issues.
- R5. Detect hung MethodChannel sync (UI responsive, future never completes) via a watchdog distinct from ANR.
- R6. Never send MAC, auth secrets, Gemini key, RFCOMM hex, or workout/HR/sleep/GPS payloads in events, breadcrumbs, or spans.
- R7. Offline buffering: watch sync must not block on Sentry upload; buffered events flush later.
- R8. Owner can open one Sentry project and read a sync stall timeline without adb.

---

## Scope Boundaries

- No Firebase Crashlytics / Analytics / marketing telemetry in this plan (Sentry is the chosen cloud SDK).
- No sync-speed optimization, protocol fixes, or prediction-accuracy work.
- No piping raw `FosHuaweiLog` / logcat into Sentry (release phases are Sentry-owned).
- No sticky FGS / always-on background sync changes.
- No iOS.
- No HCI snoop upload to cloud.

### Deferred to Follow-Up Work

- Sync-speed remediation using Sentry evidence (separate plan after a few owner sessions).
- Prediction-accuracy instrumentation.
- Optional Crashlytics as a second crash backstop (not required).
- Embrace-class ANR flame sampling if Play Vitals ANRs dominate later.

---

## Context & Research

### Relevant Code and Patterns

- App entry: `lib/main.dart` → `lib/app/bootstrap.dart` (Gemma + DI before `runApp`); no crash SDK today.
- Lifecycle: `lib/app/auto_sync_lifecycle.dart` → `OneShotAutoSync` (`lib/core/huawei/one_shot_auto_sync.dart`, `…/one_shot_auto_sync_di.dart`) — workouts then vitals; both return `Either` (no throw).
- Link: `lib/core/huawei/huawei_link.dart`, channel `lib/core/huawei/huawei_bt_channel.dart`.
- Debug-only Flutter logs: `lib/core/huawei/fos_huawei_log.dart` (`kDebugMode`).
- Native hotspots: `android/.../huawei/RfcommTransport.kt`, `HuaweiSession.kt`, `HuaweiBtPlugin.kt`, `HuaweiWorkoutSync.kt`, `HuaweiFitnessDataSync.kt`, `HuaweiSyncLock.kt`.
- MAC redaction already exists in Dart/native logs — extend that allowlist mindset to Sentry scrubbers.
- No custom `Application` class today (`MainActivity` registers the plugin).

### Institutional Learnings

- No `docs/solutions/` crash-SDK cards. Closest: `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md` — stalls are often protocol/state, need breadcrumb sequences not crash dumps alone.
- MVP plan risk row: secrets must not land in crash reports (`docs/plans/2026-07-17-001-feat-huawei-gt5-companion-mvp-plan.md`).

### External References

- [Sentry Flutter](https://docs.sentry.io/platforms/dart/guides/flutter/) — dual stack, ANR, custom instrumentation, offline cache.
- [Sentry custom instrumentation](https://docs.sentry.io/platforms/dart/guides/flutter/tracing/instrumentation/custom-instrumentation/) — transactions/spans for sync phases.
- [Sentry pricing (Developer)](https://sentry.io/pricing/) — solo-friendly free quotas (errors + spans).
- Runner-up researched: Firebase Crashlytics + Performance (aggregates, weaker per-sync timeline) — rejected for this plan’s “explain one stall” goal.

---

## Key Technical Decisions

- **Primary SDK = Sentry Flutter** (bundles Android/NDK): best Flutter↔Kotlin breadcrumbs + per-sync transactions on a free Developer tier. Crashlytics is runner-up only if we later want a free crash-only backstop.
- **Crashes + Performance** (not crash-only): “slowing down” needs spans; Issues stay for true failures/ANR.
- **Init before DI/Gemma**: Sentry wraps `runZonedGuarded` / Flutter error hooks as early as practical so bootstrap failures are visible; document any pre-init blind spot.
- **Release/profile ON; debug OFF by default** (optional debug toggle later): avoids noise and accidental richer debug PII.
- **Soft outcomes + hung sync ≠ Issues**: map `stuck` / `partial_batch` / `busy` / `empty` / schedule rejects / `sync.abandoned` onto span status + breadcrumbs only. Reserve Issues for uncaught exceptions and SDK ANR/crash. Never `captureException` / `captureMessage`-as-Issue on expected soft paths.
- **Pass aggregate tags**: `AutoSyncOutcome.ran` can hide workout `Left` + vitals `partial` — tag both legs and an aggregate pass quality.
- **DSN vs auth token**: DSN via `--dart-define=SENTRY_DSN=…` (not committed). `SENTRY_AUTH_TOKEN` for symbol upload is CI/local secret only — never git. Init sets `sendDefaultPii: false`.
- **Attach-surface allowlist**: spans/breadcrumbs may only carry status enums, counts, durations, phase names, `trigger`, window class — never MethodChannel `result`/`arguments`/`details` maps.
- **Keep today’s auto-pass sequencing** (vitals still runs after workout `Left`); instrument both legs rather than changing product behavior.

---

## Open Questions

### Resolved During Planning

- Cloud SDK choice: **Sentry** (user confirmed cloud crash SDK; research selected Sentry over Crashlytics/Bugsnag/Embrace for per-sync traces).
- Soft sync failures + hung/`abandoned`: Performance spans + breadcrumbs only — never Issues.
- Soft `stuck` vs `abandoned`: soft = native/Dart returned a status enum (often within ~20s exchange timeouts); abandoned = MethodChannel future exceeded Flutter watchdog with no return (UI may still be responsive; not an ANR).
- Auto-pass after workout failure: keep continue-both-legs; tag both statuses.
- Consent screen: none for v1 (solo owner device); revisit before any non-owner / Play build flavor.
- Named phases for v1: `autosync.pass`, `sync.workouts`, `sync.vitals`, link-state breadcrumbs (+ connect span when cheap). Drop custom `anr.detected` — SDK ANR Issues cover R2.

### Deferred to Implementation

- Exact Flutter sync `Future.timeout` budgets: prefer dual policy — (a) hard abandon for no-progress / connect-write deadlock, (b) longer cap tagged `window=full_history|incremental` so legit long enrichment is not false-`abandoned`. Const thresholds OK; no watchdog framework.
- Final `tracesSampleRate` for release (start high for owner digs; free Developer ~5k errors / 5M spans is ample if soft paths stay off Issues).
- Whether a thin Kotlin breadcrumb bridge is needed beyond Flutter MethodChannel phase tags (only if native-only crashes lack last-phase context).

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```mermaid
sequenceDiagram
  participant Boot as bootstrap
  participant S as Sentry
  participant Life as AutoSyncLifecycle
  participant Link as HuaweiLink
  participant Pass as OneShotAutoSync
  participant Native as HuaweiBtPlugin

  Boot->>S: init + beforeSend scrub
  Boot->>Boot: DI / Gemma / runApp
  Life->>S: txn lifecycle.ensure_session
  Life->>Link: startLink / reconnect
  Link->>S: breadcrumb link.state
  Life->>Pass: trySchedule
  Pass->>S: txn autosync.pass
  Pass->>Native: syncWorkouts
  Native-->>Pass: status enum
  Pass->>S: span sync.workouts (status)
  Pass->>Native: syncActivity
  Pass->>S: span sync.vitals (status)
  Note over Pass,S: stuck/partial = span status only
  Note over Pass,S: hung channel = sync.abandoned watchdog
```

**Named phases (v1):** `autosync.pass` (parent), `sync.workouts`, `sync.vitals`, link-state breadcrumbs, optional connect span, `sync.abandoned` (watchdog only). Soft statuses live as span tags (`status=stuck|…`), not separate Issue events. ANR = SDK Issues (no custom `anr.detected` phase).

---

## Implementation Units

### U1. Sentry bootstrap and build wiring

**Goal:** Profile/release builds initialize Sentry early with DSN, release name, and Flutter+Android error hooks; debug stays off by default.

**Requirements:** R1, R2, R7

**Dependencies:** None (owner creates Sentry project + DSN)

**Files:**
- Modify: `lib/app/bootstrap.dart`, `lib/main.dart`, `pubspec.yaml`
- Modify: `android/app/build.gradle.kts` (if native/NDK options or plugin require it)
- Create: `docs/runbooks/sentry-owner-setup.md` (DSN, auth token, symbol upload, stall queries, privacy checklist — single runbook)
- Test: `test/core/observability/sentry_bootstrap_test.dart` (or equivalent)

**Approach:**
- Add `sentry_flutter`; init after `WidgetsFlutterBinding`, before Gemma/DI, via `SentryFlutter.init` + `appRunner` wrapping the rest.
- Enable ANR / NDK scope sync; set `sendDefaultPii: false`.
- Gate init on release/profile (or explicit dart-define override).
- Document `sentry_dart_plugin` + `SENTRY_AUTH_TOKEN` (never commit) for obfuscated builds.
- Transport must not block RFCOMM/sync paths; offline outbox is fine.

**Patterns to follow:**
- Existing bootstrap sequencing in `lib/app/bootstrap.dart`.
- Secrets: prefer dart-define / non-committed config like other keys.

**Test scenarios:**
- Happy path: release-mode init called once when DSN present → SDK ready flag / no throw.
- Edge case: missing DSN → app still starts; observability disabled; no crash.
- Error path: init failure → logged locally; app continues (observability must not brick launch).

**Verification:** Profile/release build launches; Sentry project receives a test event from a deliberate debug throw behind a debug-only hook or Sentry’s test mechanism; debug builds do not spam.

---

### U2. Privacy scrub allowlist and envelope tests

**Goal:** Hard-fail tests if forbidden PII/payload shapes appear in outbound event fields; wire `beforeSend` / breadcrumb scrubbers.

**Requirements:** R6

**Dependencies:** U1

**Files:**
- Create: `lib/core/observability/sentry_privacy_scrub.dart` (name flexible)
- Create: `test/core/observability/sentry_privacy_scrub_test.dart`
- Modify: bootstrap/init site from U1 to register scrub hooks

**Approach:**
- Primary prevention: instrumentation never attaches MethodChannel `result`/`arguments`/`PlatformException.details` (defense-in-depth scrub is secondary).
- Dart: `beforeSend`, `beforeSendTransaction`, `beforeBreadcrumb` scrubbers — strip/redact MAC patterns, secret key names, workout/HR/sleep-shaped maps, hex dumps.
- Android: mirror with Kotlin `SentryAndroidOptions.beforeSend` (Dart alone is not R6-complete for JVM/NDK crashes). Scrub breadcrumbs at add-time before NDK scope sync stores them.
- Native/channel errors: only `code` + short safe reason — never forward raw `e.message` if it may contain protocol/hex.

**Patterns to follow:**
- `HuaweiLink` / `RfcommTransport` MAC redaction.
- MVP plan crash-report risk guidance.

**Test scenarios:**
- Happy path: event with `link.state=connected` and duration tags passes scrub unchanged for safe fields.
- Edge case: full MAC string in message/extra → redacted or dropped.
- Edge case: workout summary map / HR series-shaped map in event or **transaction/span** contexts → removed (`beforeSendTransaction` fixture).
- Edge case: `PlatformException(details: {workouts: […]})` → outbound event has no workout/HR/sleep keys.
- Error path: Gemini key / auth material key names → stripped.
- Integration: Dart + documented native scrub checklist in runbook for forced JVM crash with MAC-like message.

**Verification:** Unit tests green; intentional forbidden fixture fails the test suite if scrub regresses.

---

### U3. Sync and link Performance instrumentation

**Goal:** One owner session produces a readable Sentry transaction for cold-open auto-sync and manual Sync, with child spans for workouts/vitals and link state breadcrumbs.

**Requirements:** R3, R4, R8

**Dependencies:** U1, U2

**Files:**
- Modify: `lib/app/auto_sync_lifecycle.dart`
- Modify: `lib/core/huawei/one_shot_auto_sync.dart` and/or `one_shot_auto_sync_di.dart`
- Modify: `lib/core/huawei/huawei_link.dart` (state breadcrumbs / connect span)
- Modify: workout/vitals sync entry points as needed for status tags (prefer Dart status enums already returned)
- Test: `test/core/huawei/one_shot_auto_sync_observability_test.dart` (or extend existing `one_shot_auto_sync_test.dart`)

**Approach:**
- Parent transaction `autosync.pass` (tag `trigger=auto|manual`, `window=full_history|incremental` when known).
- Child spans `sync.workouts` / `sync.vitals` tagged with status enum, counts only (not rows), `partial` flags — allowlisted keys only.
- Soft returned statuses (`stuck`, `partial_batch`, …) → span status/tags only; optional breadcrumb with step name — no payload, no Issue.
- Link state changes → breadcrumbs with enum only; never include MAC from connect args.
- Do not `captureException` / Issue-level `captureMessage` on `ServerFailure` / expected `Left` paths.

**Patterns to follow:**
- Existing `WorkoutSyncStatus` / vitals result shapes and `AutoSyncOutcome`.
- Op tags already used in logs: `pair|reconnect|auth|sync|…`.

**Execution note:** Prefer characterization tests around outcome→span tagging with a fake/hub test double if available; otherwise unit-test a thin mapper from status → span attributes.

**Test scenarios:**
- Happy path: both legs `ok` → pass aggregate success tags; no Issue capture.
- Happy path: workout `stuck` + vitals `ok` → both leg statuses recorded; still no Issue.
- Edge case: `rejectedBusy` / `alreadyFired` → schedule breadcrumb only; no sync spans started.
- Error path: unexpected throw in pass → Issue + transaction finished with error.
- Integration: scrub still applied to any span data attached during sync.

**Verification:** Owner Sync in profile/release shows a transaction with phase spans in Sentry UI; soft `stuck` does not create a crash Issue.

---

### U4. Hung-sync timeout and owner runbook

**Goal:** Distinguish “UI fine, sync forever” from ANR and from soft `stuck`; document how the owner reads stalls in Sentry.

**Requirements:** R5, R7, R8

**Dependencies:** U3

**Files:**
- Modify: sync invoke sites / `HuaweiLink` MethodChannel wrappers as appropriate
- Modify: `docs/runbooks/sentry-owner-setup.md` (single runbook: setup + stall playbook)
- Test: `test/core/observability/sync_watchdog_test.dart`

**Approach:**
- Prefer `Future.timeout` at MethodChannel sync invokes (same pattern as connect timeout) — not a configurable watchdog framework.
- On expiry: finish span `deadline_exceeded`, breadcrumb `sync.abandoned`; **no Issue**. Not an ANR (worker-thread RFCOMM hangs won’t show native step stacks in Sentry).
- Late completion after timeout: record only safe status string + `superseded=true` — never stringify the full result map.
- Dual budget guidance: short hard-abandon for no-return deadlocks; longer cap when `window=full_history` so enrichment isn’t false-abandoned. Soft `stuck` usually still completes the channel after native ~20s exchange timeouts — expect most stalls as completed spans with `status=stuck`, not `abandoned`.
- Runbook: Sentry queries for `autosync.pass`, leg statuses, privacy checklist, auth token handling, quota notes, “BT sync ≠ Sentry upload”, event deletion if scrub regresses.

**Patterns to follow:**
- Existing Flutter connect timeouts (e.g. 30s connect) as precedent for explicit deadlines.
- Soft `stuck` semantics already returned by native sync.

**Test scenarios:**
- Happy path: invoke completes before threshold → no abandoned signal.
- Edge case: invoke exceeds threshold → abandoned span/breadcrumb; no Issue.
- Error path: timeout then late completion → superseded; no full payload attached.

**Verification:** Simulated hang in tests; runbook lists exact Sentry queries/tags the owner should use after a slow Sync.

---

## Risk Analysis & Mitigation

| Risk | Mitigation |
|------|------------|
| Health/PII leak via MethodChannel args/results or breadcrumbs | Attach allowlist + Dart/Android scrub + tests; never attach raw sync maps/`details` |
| Issue spam from expected soft timeouts / abandoned | Soft + abandoned = spans only; alert on crashes/ANR only |
| Free-tier span quota burn | One parent txn per pass; sample traces if needed (5M spans is ample for solo) |
| Init order misses early Gemma crashes | Sentry after binding, before Gemma; document residual blind spot |
| Native worker hang invisible as ANR | U4 Dart timeout; calibrate runbook (abandoned ≠ stuck-on-page-N) |
| Native-only crash lacks Dart phase context | Prefer completing U3 breadcrumbs before heavy native work; optional later Kotlin bridge |
| Observability blocks sync | Never await Sentry flush on sync path; rely on offline outbox |
| False `abandoned` on full-history | Dual timeout budgets tagged by window class |

---

## Success Metrics

- After one owner pool session + Sync: Sentry shows a pass transaction with workouts/vitals spans and durations.
- A forced soft `stuck` (or simulated) does **not** create a crash Issue.
- Scrub tests prevent MAC/workout-shaped fixtures from shipping.
- Owner can answer “which phase was slow?” without adb for that session.

---

## System-Wide Impact

- **Owner:** gains cloud stall/crash visibility; must create Sentry project and supply DSN for builds.
- **Privacy:** new outbound network to Sentry — constrained by scrub allowlist.
- **Sync path:** additive timing only; no protocol change.
- **Build:** new dependency + optional symbol upload step for release.

---

## Sources & References

- Research: Sentry Flutter docs; Crashlytics/Bugsnag/Embrace comparison (2026) favoring Sentry for per-sync traces.
- Repo: Huawei auto-sync DI, `FosHuaweiLog` release silence, Gate A / secrets posture.
- Learnings: `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md` (stall taxonomy).

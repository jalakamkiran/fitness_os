# Fathom Onboarding Guide

Fathom (`fitness_os`) is an Android Flutter companion for the Huawei Watch GT5-A07. You pair over direct LPv2 RFCOMM, sync workouts and vitals locally, and read swim analytics on-device — without Huawei Health Kit.

Detailed HLD/LLD with Excalidraw scenes live under [`docs/onboarding/`](docs/onboarding/README.md). Living architecture notes: [`docs/architecture/README.md`](docs/architecture/README.md).

---

## What Is This?

You are building a **local-first swim companion**. The watch talks Classic RFCOMM with LPv2 framing to an Android native stack; Flutter owns UI, repositories, and local persistence. Product surfaces are a calm Home tab, Recovery (sleep/HR), and Workouts (session history + Swim Bible v0).

The repo package name is `fitness_os`; product naming in docs and UI is **Fathom**. Current horizon work centers on Gate A (pair/reconnect), Gate B (workout sync), vitals sync, and Swim Bible evidence → diagnosis → recommendations with an on-device reasoner.

---

## User Experience

Open the app on Android → splash → bottom shell with **Home | Recovery | Workouts**.

1. **Pair** a GT5 (or reconnect a remembered MAC) via device pairing / Gate A.
2. **Sync** runs automatically on resume when the link is connected, or via Home’s Sync CTA — workouts first, then vitals.
3. **Home** shows the Today stack (sleep, totals, body HR ± one spark, today’s session cards) from local stores (precedence: not paired → syncing → never synced → failed → trusted day).
4. **Recovery** opens sleep/HR detail and history.
5. **Workouts** lists sessions; detail opens charts and Swim Bible coach settings.

Brand/IA context: [`docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md`](docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md). Design reviews: [`docs/design/`](docs/design/).

---

## How Is It Organized?

### System architecture

```
       User (Android phone)
              |
              |  UI / BLoC
              v
+---------------------------+
| Flutter app (Fathom)      |
| features + core HuaweiLink|
+-------------+-------------+
              |
              |  Method/EventChannel
              v
+---------------------------+
| Android Huawei LPv2 stack |
| Session / Sync / Secrets  |
+-------------+-------------+
              |
              |  RFCOMM LPv2
              v
        Huawei GT5-A07
              |
              v
   Local prefs + side-files
   (optional Sentry / Gemma)
```

Editable Excalidraw: [`docs/onboarding/diagrams/01-hld-system-context.excalidraw`](docs/onboarding/diagrams/01-hld-system-context.excalidraw).

### User interaction flow

```
Open app
  |
  v
Gate A pair / reconnect
  |
  v
Auto-sync: workouts -> vitals
  |
  +--> Home Today stack (sleep / totals / HR / sessions)
  +--> Recovery sleep / HR
  +--> Workout detail + Swim Bible
```

Journey diagram: [`docs/onboarding/diagrams/04-hld-user-journeys-sync-planes.excalidraw`](docs/onboarding/diagrams/04-hld-user-journeys-sync-planes.excalidraw).

### Internal structure

```
fitness_os/
  lib/
    main.dart           # entry
    app/                # bootstrap, shell, routes, splash
    core/               # DI, Huawei bridge, storage, Sentry
    features/           # clean-arch feature packages
  packages/
    blueprint_ui/       # design system
  android/.../huawei/   # LPv2 native stack
  docs/
    onboarding/         # HLD/LLD + Excalidraw
    architecture/       # living architecture
    wire-specs/         # LPv2 protocol notes
  test/                 # Dart tests (mirrors lib/)
```

| Module | Responsibility |
|--------|----------------|
| `lib/app/` | Bootstrap, MaterialApp, shell tabs, route registry |
| `lib/core/huawei/` | `HuaweiLink`, channel, one-shot auto-sync |
| `lib/features/device_pairing/` | Gate A scan/pair/reconnect/Forget |
| `lib/features/home/` | Precedence Home + Sync CTA |
| `lib/features/vitals/` | Sleep, HR, FitnessTotals, enable auto-tracking |
| `lib/features/workout_history/` | Gate B list/detail, Swim Bible, coach |
| `lib/features/diagnostics/` | Local JSON export |
| `android/.../huawei/` | Framing, auth, workout/fitness sync, secrets |
| `packages/blueprint_ui/` | Theme tokens and primitives |

### External dependencies

| Dependency | What it's used for | Configured via |
|-----------|-------------------|----------------|
| Huawei GT5 RFCOMM | Pair + protocol sync | Native secrets / MAC |
| Sentry | Crash and sync tracing | `SENTRY_DSN`, `SENTRY_FORCE` |
| Flutter Gemma / LiteRT | On-device Swim Bible reasoner | Bootstrap init |
| SharedPreferences + files | Local-first persistence | App support paths |

This project is otherwise self-contained for runtime (no cloud backend required for core sync). Env names only: [`.env.example`](/.env.example).

Full HLD prose: [`docs/onboarding/HLD.md`](docs/onboarding/HLD.md).

---

## Key Concepts and Abstractions

| Concept | What it means in this codebase |
|---------|-------------------------------|
| Gate A | Pair + auth + remember + prove reconnect |
| Gate B | Workout Count → Totals → enrichment sync |
| `HuaweiLink` | Singleton typed Flutter API over the BT channel |
| `LinkState` | Connection/auth readiness (`gateAIncomplete`, `connected`, …) |
| LPv2 | Watch wire framing (TLV) in `HuaweiFraming` |
| Single-flight Sync | `HuaweiSyncLock` + Flutter `syncInFlight` — no overlapping Sync |
| `OneShotAutoSync` | On open/resume: workouts then vitals when connected |
| `StoreInvalidation` | Broadcast so tabs reload after sync/Forget |
| Side-files | No-backup JSON series under app support (HR, sleep stages, canonical swim) |
| `GateAPrefs` | Canonical SharedPreferences key names for identity/sync |
| Home precedence | Resolver for Home empty/syncing/data states |
| Swim Bible v0 | Evidence → diagnosis → recommendations → reasoner |
| Clean feature layout | `presentation/` / `domain/` / `data/` + `*_di.dart` |
| Blueprint UI | Local package `packages/blueprint_ui` for Fathom look |

---

## Primary Flows

### Flow 1 — App start and auto-sync

```
lib/main.dart
  calls bootstrap()
  |
  v
lib/app/bootstrap.dart
  Sentry? · Gemma · initDependencies · routes
  |
  v
FitnessOsApp + AutoSyncLifecycle
  startLink / reconnectRemembered
  |
  v
OneShotAutoSync (when LinkState.connected)
  workouts.syncFromWatch()
  then vitals.syncFromWatch()
```

Excalidraw: [`05-lld-bootstrap-di.excalidraw`](docs/onboarding/diagrams/05-lld-bootstrap-di.excalidraw), [`09-lld-sync-pass.excalidraw`](docs/onboarding/diagrams/09-lld-sync-pass.excalidraw).

### Flow 2 — Gate A pair

```
DevicePairingScreen / Bloc
  |
  v
DevicePairingRepository
  |
  v
HuaweiLink.connectAndAuthenticate(mac)
  |
  v
Native: RFCOMM -> auth -> feature upload
  |
  v
GateAPrefs.gateAPassed + remembered MAC
```

Excalidraw: [`08-lld-gate-a-pairing.excalidraw`](docs/onboarding/diagrams/08-lld-gate-a-pairing.excalidraw). Wire notes: [`docs/wire-specs/`](docs/wire-specs/).

### Flow 3 — Workout detail / Swim Bible

1. `WorkoutHistoryRepository` loads local workouts (after Gate B sync).
2. Detail screen reads canonical swim side-files + P0 metrics.
3. `SwimReasonerService` / Qwen3 path produces diagnosis/recs (offline rules as fallback).
4. Coach settings / diagnostics export live under workout settings routes.

Native enrichment path: [`06-lld-huawei-native-stack.excalidraw`](docs/onboarding/diagrams/06-lld-huawei-native-stack.excalidraw).

Full LLD: [`docs/onboarding/LLD.md`](docs/onboarding/LLD.md).

---

## Developer Guide

### Setup

Prerequisites: Flutter SDK matching `pubspec.yaml` (`sdk: ^3.9.2`), Android toolchain, a GT5 for device work.

```bash
cp .env.example .env
# fill SENTRY_DSN / SENTRY_FORCE if you need observability

flutter pub get
flutter run --dart-define-from-file=.env
```

VS Code launch already wires `--dart-define-from-file=.env`. Do not put `SENTRY_AUTH_TOKEN` in `.env` (it would embed in the binary).

### Running and testing

```bash
flutter test
flutter analyze

# Kotlin unit tests (Huawei framing/crypto/sync)
cd android && ./gradlew test
```

Scaffold a new feature package:

```bash
./create_feature.sh <feature_name>
```

Regenerate onboarding Excalidraw scenes after structural changes:

```bash
node scripts/generate_onboarding_excalidraw.mjs
```

Open any `.excalidraw` at [https://excalidraw.com](https://excalidraw.com) → **File → Open**.

### Common change patterns

- **New UI tab/screen** — add under the feature’s `presentation/`, register route in that feature’s route file, call it from `RouteRegistry`.
- **New sync metric** — extend native sync (`HuaweiWorkoutSync` / `HuaweiFitnessDataSync`), map DTOs in `HuaweiLink`, merge in the feature repository, update side-file layout if series data.
- **New local store key** — add the name to `GateAPrefs` (or the owning prefs helper), never invent ad-hoc string keys in UI.
- **Forget / wipe behavior** — compose through pairing Forget hooks already used by vitals and diagnostics DI.

### Key files to start with

| Area | File | Why |
|------|------|-----|
| Boot | `lib/app/bootstrap.dart` | Sentry, Gemma, DI, routes |
| DI order | `lib/core/di/injector.dart` | Feature registration sequence |
| Bridge | `lib/core/huawei/huawei_link.dart` | Typed watch API + DTOs |
| Native session | `android/.../huawei/HuaweiSession.kt` | Auth + sync entry |
| Gate A prefs | `lib/features/device_pairing/domain/gate_a_prefs.dart` | Identity/sync keys |
| Home states | `lib/features/home/domain/home_precedence.dart` | Home empty/data rules |
| Architecture | `docs/architecture/README.md` | Living system map |
| Diagrams | `docs/onboarding/README.md` | HLD/LLD Excalidraw index |

### Practical tips

- Sync features refuse work until `GateAPrefs.gateAPassed` — check Gate A before debugging “empty sync.”
- Prefer side-files for dense series; keep day summaries in SharedPreferences (see architecture rules).
- Do not paste AGPL Gadgetbridge code; treat external captures as oracle only ([`docs/architecture/README.md`](docs/architecture/README.md)).
- Huawei unit tests under `android/app/src/test/.../huawei/` are the fastest way to validate framing/crypto changes without a watch.

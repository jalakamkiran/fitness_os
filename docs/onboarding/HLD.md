# Fathom — High-Level Design (HLD)

This document describes how Fathom is shaped from the outside in: who talks to whom, which layers own which work, and which product surfaces the user moves through. Editable Excalidraw scenes live in [`diagrams/`](diagrams/). Open them at [excalidraw.com](https://excalidraw.com) via **File → Open**.

Companion LLD: [`LLD.md`](LLD.md). Living notes: [`docs/architecture/README.md`](../architecture/README.md).

---

## 1. System context

**Diagram:** [`01-hld-system-context.excalidraw`](diagrams/01-hld-system-context.excalidraw)

Fathom is an Android companion for **Huawei Watch GT5-A07**. It pairs and syncs over **Classic RFCOMM with LPv2 framing** — not Huawei Health Kit.

```
Huawei GT5-A07
      |
      |  RFCOMM / LPv2
      v
Android native Huawei stack
      |
      |  MethodChannel + EventChannel
      v
Flutter app (fitness_os / Fathom)
      |
      +-- SharedPreferences + side-files
      +-- Sentry (optional, via dart-define)
      +-- On-device Swim Bible reasoner (Gemma/Qwen3)
```

Secrets (auth keys) stay in native `HuaweiSecretStore`. Flutter never stores them in prefs.

---

## 2. Layered architecture

**Diagram:** [`02-hld-layered-architecture.excalidraw`](diagrams/02-hld-layered-architecture.excalidraw)

| Layer | Location | Role |
|-------|----------|------|
| Presentation | `lib/features/*/presentation/` | Screens, BLoCs, routes |
| Domain | `lib/features/*/domain/` | Repository contracts, entities, use cases |
| Data | `lib/features/*/data/` | Prefs, side-files, channel-backed repos |
| Core | `lib/core/` | `HuaweiLink`, DI, storage bus, observability |
| Native | `android/.../huawei/` | Session, framing, crypto, sync, secrets |

Features register into GetIt via `*_di.dart`. Device pairing registers the singleton `HuaweiLink` that every sync feature injects.

---

## 3. Feature module map

**Diagram:** [`03-hld-feature-module-map.excalidraw`](diagrams/03-hld-feature-module-map.excalidraw)

| Module | Path | Responsibility |
|--------|------|----------------|
| Shell | `lib/app/shell/` | Bottom tabs: Home · Recovery · Workouts |
| `home` | `lib/features/home/` | Calm “now” view, KPIs, Sync CTA, precedence |
| `vitals` | `lib/features/vitals/` | Sleep, daily HR, FitnessTotals, auto-tracking |
| `workout_history` | `lib/features/workout_history/` | Gate B workouts, Swim Bible analytics/coach |
| `device_pairing` | `lib/features/device_pairing/` | Gate A pair / reconnect / Forget |
| `diagnostics` | `lib/features/diagnostics/` | Local JSON export (coach settings entry) |
| Design system | `packages/blueprint_ui/` | Fathom UI tokens and primitives |

---

## 4. User journeys and sync planes

**Diagram:** [`04-hld-user-journeys-sync-planes.excalidraw`](diagrams/04-hld-user-journeys-sync-planes.excalidraw)

### User journey (happy path)

1. Open app (splash → shell)
2. Pair GT5 (Gate A) or reconnect remembered MAC
3. Auto-sync: workouts, then vitals
4. Home shows today KPIs + one swim takeaway
5. Recovery (sleep/HR) and Workouts (session detail + Swim Bible)

### Sync planes

| Plane | What it unlocks |
|-------|-----------------|
| **Gate A** | Pair, auth, remember, prove reconnect |
| **Gate B** | Workout Count → Totals → enrichment (pace/swim) |
| **Activity** | Sleep sessions/stages, daily HR, FitnessTotals |
| **Swim Bible v0** | Evidence → diagnosis → recommendations → reasoner |

Gate A must pass before workouts/vitals `syncFromWatch` runs. Sync is single-flight (native lock + Flutter `syncInFlight`).

---

## External dependencies

| Dependency | Used for | Configured via |
|------------|----------|----------------|
| Huawei GT5 (RFCOMM) | Pair + sync | Device MAC / native secrets |
| Sentry | Crash + sync observability | `SENTRY_DSN`, `SENTRY_FORCE` |
| Flutter Gemma / LiteRT | On-device Swim Bible reasoner | App bootstrap init |
| SharedPreferences / files | Local-first store | App support paths |

Env template: [`.env.example`](../../.env.example) (variable names only; never commit `.env`).

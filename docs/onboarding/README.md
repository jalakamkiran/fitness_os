# Fathom Onboarding — Architecture Diagrams

Detailed **HLD** (high-level design) and **LLD** (low-level design) for Fathom (`fitness_os`), with editable Excalidraw scenes for the system and each major module.

Start with the prose guide: [`ONBOARDING.md`](../../ONBOARDING.md) at the repo root. Living architecture notes: [`docs/architecture/README.md`](../architecture/README.md).

## How to open the diagrams

Scenes are standard `.excalidraw` JSON (compatible with [excalidraw.com](https://excalidraw.com)).

### Option A — Local preview + Excalidraw.com (recommended)

```bash
npx --yes serve docs/onboarding -p 5179
# SVG preview (fast):     http://localhost:5179/preview.html
# Full Excalidraw embed:  http://localhost:5179/excalidraw-viewer.html
```

`preview.html` renders every scene from `diagrams/` as SVG. Use [excalidraw.com](https://excalidraw.com) (**File → Open** / drag-and-drop) to edit the same `.excalidraw` files.

### Option B — Official excalidraw.com only

1. Open [https://excalidraw.com](https://excalidraw.com)
2. **File → Open** (or drag-and-drop) a file from `docs/onboarding/diagrams/`
3. Edit freely; save back into the same path if you change the design

Regenerate all scenes from the canonical layout script:

```bash
node scripts/generate_onboarding_excalidraw.mjs
```

## Document index

| Doc | Purpose |
|-----|---------|
| [`HLD.md`](HLD.md) | System context, layers, features, user journeys |
| [`LLD.md`](LLD.md) | Bootstrap/DI, Huawei stack, Gate A, sync, persistence, routes |
| [`diagrams/`](diagrams/) | Twelve Excalidraw scenes (HLD 01–04, LLD 05–12) |

## Diagram catalog

### High-level design

| File | Contents |
|------|----------|
| [`01-hld-system-context.excalidraw`](diagrams/01-hld-system-context.excalidraw) | Watch ↔ native ↔ Flutter ↔ local · Sentry · on-device reasoner |
| [`02-hld-layered-architecture.excalidraw`](diagrams/02-hld-layered-architecture.excalidraw) | Presentation → domain → data → core → native |
| [`03-hld-feature-module-map.excalidraw`](diagrams/03-hld-feature-module-map.excalidraw) | Shell tabs + feature packages + `HuaweiLink` |
| [`04-hld-user-journeys-sync-planes.excalidraw`](diagrams/04-hld-user-journeys-sync-planes.excalidraw) | Pair → sync → Home/Recovery/Workouts · Gate A/B/vitals/Bible |

### Low-level design (per module / flow)

| File | Contents |
|------|----------|
| [`05-lld-bootstrap-di.excalidraw`](diagrams/05-lld-bootstrap-di.excalidraw) | `main` → bootstrap → GetIt order → routes |
| [`06-lld-huawei-native-stack.excalidraw`](diagrams/06-lld-huawei-native-stack.excalidraw) | Kotlin session, framing, auth, sync modules |
| [`07-lld-huawei-flutter-bridge.excalidraw`](diagrams/07-lld-huawei-flutter-bridge.excalidraw) | `HuaweiLink` / channel / auto-sync |
| [`08-lld-gate-a-pairing.excalidraw`](diagrams/08-lld-gate-a-pairing.excalidraw) | `device_pairing` Gate A + reconnect |
| [`09-lld-sync-pass.excalidraw`](diagrams/09-lld-sync-pass.excalidraw) | Workouts-then-vitals single-flight sync |
| [`10-lld-feature-internals.excalidraw`](diagrams/10-lld-feature-internals.excalidraw) | Clean-arch internals per feature |
| [`11-lld-persistence-map.excalidraw`](diagrams/11-lld-persistence-map.excalidraw) | Prefs vs side-files vs native secrets |
| [`12-lld-navigation-routes.excalidraw`](diagrams/12-lld-navigation-routes.excalidraw) | `AppRouter` route map |

## Color legend (in diagrams)

| Color | Meaning |
|-------|---------|
| Red / pink | Watch or caution (Gate A, secrets) |
| Green | Android native |
| Blue | Flutter UI / presentation |
| Purple | Feature modules |
| Teal | Core bridge / infra |
| Yellow | Persistence |
| Gray | External / optional services |

# Fathom — Low-Level Design (LLD)

Module- and flow-level design: bootstrap order, Huawei native/Flutter contracts, Gate A, sync pass, feature internals, persistence, and routes. Open matching Excalidraw files in [`diagrams/`](diagrams/) at [excalidraw.com](https://excalidraw.com) (**File → Open**).

Companion HLD: [`HLD.md`](HLD.md). Wire protocols: [`docs/wire-specs/`](../wire-specs/).

---

## 1. Bootstrap and DI

**Diagram:** [`05-lld-bootstrap-di.excalidraw`](diagrams/05-lld-bootstrap-di.excalidraw)

```
lib/main.dart
  |
  v
lib/app/bootstrap.dart
  optional SentryFlutter.init
  FlutterGemma.initialize(LiteRtLmEngine)
  initDependencies()          # lib/core/di/injector.dart
  RouteRegistry.registerAll()
  runApp(FitnessOsApp)
```

### GetIt registration order

1. `StoreInvalidation`
2. `device_pairing` — creates singleton `HuaweiLink`
3. `workout_history`
4. `vitals` — hooks Forget wipe → `clearLocal`
5. `diagnostics` — export + wipe composition
6. `OneShotAutoSync` — workouts then vitals
7. `home`

---

## 2. Android Huawei native stack

**Diagram:** [`06-lld-huawei-native-stack.excalidraw`](diagrams/06-lld-huawei-native-stack.excalidraw)

Path: `android/app/src/main/kotlin/com/example/fitness_os/huawei/`

| Class | Role |
|-------|------|
| `HuaweiBtPlugin` | MethodChannel `fitness_os/huawei_bt` + EventChannel |
| `RfcommTransport` | BLE discovery → Classic SDP RFCOMM |
| `HuaweiSession` | Auth + sync orchestration entry |
| `HuaweiFraming` | LPv2 TLV frames |
| `HuaweiPacketCrypto` | Session packet crypto |
| `HuaweiNormalAuth` / `HuaweiHiChain` | Auth modes |
| `HuaweiSecretStore` | Native-only secrets |
| `HuaweiFeatureUpload` | Post-auth feature file upload |
| `HuaweiWorkoutSync` | Gate B Count→Totals→0x0e/0x0a/0x0c |
| `HuaweiFitnessDataSync` | Sleep / HR / FitnessTotals / enable |
| `HuaweiFileDownload` | TruSleep soft enrich files |
| `HuaweiSyncLock` | Native single-flight Sync |

Channel methods include: `checkPermissions` / `requestPermissions`, `startBleDiscovery`, `connect`, `authenticate`, `syncWorkouts`, `syncActivity`, `enableAutoTracking`, `setAuthKey`, `hasSecrets` / `clearSecrets`, `disconnect`.

---

## 3. Flutter Huawei bridge

**Diagram:** [`07-lld-huawei-flutter-bridge.excalidraw`](diagrams/07-lld-huawei-flutter-bridge.excalidraw)

```
UI / BLoCs
  -> Feature repositories
    -> HuaweiLink          # typed LinkState + DTOs
      -> HuaweiBtChannel   # Method/EventChannel
        -> HuaweiBtPlugin
```

Key `HuaweiLink` APIs: `start`, `ensurePermissions`, `startScan` / `stopScan`, `connectAndAuthenticate`, `reconnect`, `syncWorkouts`, `syncActivity`, `enableAutoTracking`.

`OneShotAutoSync` runs on open/resume/session-ready when `LinkState.connected`, calling workouts then vitals.

---

## 4. Gate A pairing (`device_pairing`)

**Diagram:** [`08-lld-gate-a-pairing.excalidraw`](diagrams/08-lld-gate-a-pairing.excalidraw)

```
permissions
  -> BLE scan (GT5 name)
    -> RFCOMM connect + authenticate
      -> feature upload (stabilize)
        -> GateAPrefs: remembered MAC + gateAPassed
          -> LinkState.connected
```

Reconnect path: remembered MAC + native secrets → `reconnect(mac)`. Forget clears identity, vitals local data, export cache, and notifies `StoreInvalidation`.

Prefs key ownership: `lib/features/device_pairing/domain/gate_a_prefs.dart`.

---

## 5. Sync pass

**Diagram:** [`09-lld-sync-pass.excalidraw`](diagrams/09-lld-sync-pass.excalidraw)

```
Trigger (AutoSyncLifecycle / Home Sync CTA)
  |
  v
Gate A passed?  --no--> refuse
  |
  v
syncInFlight / native busy? --yes--> skip / wait
  |
  v
WorkoutHistoryRepository.syncFromWatch()
  |
  v
VitalsRepository.syncFromWatch()
  |
  v
Persist + StoreInvalidation.notify -> BLoCs reload
```

---

## 6. Feature internals

**Diagram:** [`10-lld-feature-internals.excalidraw`](diagrams/10-lld-feature-internals.excalidraw)

Every feature follows clean architecture under `lib/features/{name}/`:

| Folder | Contents |
|--------|----------|
| `presentation/` | Screens, BLoC, routes |
| `domain/` | Repository interfaces, entities, prefs contracts |
| `data/` | RepositoryImpl + `*_di.dart` |

| Feature | Notable types |
|---------|---------------|
| `device_pairing` | `DevicePairingBloc`, `GateAPrefs`, `RememberedDevice` |
| `home` | `HomeBloc`, `HomePrecedence`, `GetHomeData` |
| `vitals` | `VitalsBloc`, `VitalsSnapshot`, Recovery/Sleep screens |
| `workout_history` | `CanonicalSwimStore`, `SwimReasonerService`, P0 metrics |
| `diagnostics` | `AppDataExportService` |

---

## 7. Persistence map

**Diagram:** [`11-lld-persistence-map.excalidraw`](diagrams/11-lld-persistence-map.excalidraw)

| Store | Holds |
|-------|-------|
| SharedPreferences | Gate A identity/status, `workouts_json`, sleep/HR/FT summaries, home sync status, coach settings |
| Side-files (app support, no-backup) | `vitals/hr_series/`, `vitals/sleep_stages/`, `vitals/sleep_enrich/`, `vitals/sleep_files/`, `workouts/canonical_swim/` |
| Native `HuaweiSecretStore` | Auth keys / pairing secrets only |

UI refresh bus: `lib/core/storage/store_invalidation.dart`.

---

## 8. Navigation and routes

**Diagram:** [`12-lld-navigation-routes.excalidraw`](diagrams/12-lld-navigation-routes.excalidraw)

Registered in `lib/app/routing/route_registry.dart` into `AppRouter.routes` (imperative `MaterialApp.routes`).

| Path | Surface |
|------|---------|
| `/` | `AppShell` (Home \| Recovery \| Workouts) |
| `/home` | Home screen |
| `/device_pairing` | Gate A pairing |
| `/workout_history` | Workout list |
| `/workout_detail` | Session detail + Swim Bible |
| `/coach_settings` | Reasoner / export settings |
| `/sleep_detail` | Sleep detail |
| `/sleep_history` | Sleep history |

Recovery tab host embeds Vitals \| Sleep subtabs without a separate top-level path.

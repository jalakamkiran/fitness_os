# Testing Guide

This document describes the test suite and CI pipeline for Fitness OS.

## Overview

Fitness OS has comprehensive test coverage across three main areas:

1. **Flutter/Dart** — UI, business logic, workout history, vitals, programs
2. **Android/Kotlin** — Huawei BLE wire protocol, parsers, framing, crypto
3. **Backend/TypeScript** — Firebase Cloud Functions, ingest endpoints, daily summaries

## Running Tests Locally

### Prerequisites

- **Flutter SDK 3.44.7** (stable channel)
- **Java 17** (for Android Gradle builds)
- **Node.js 22** (for backend functions)
- **Android SDK** (for APK compilation)

### Flutter Tests

```bash
# Install dependencies
flutter pub get

# Analyze code
flutter analyze

# Run all tests with coverage
flutter test --coverage

# Run specific test file
flutter test test/features/workout_history/domain/huawei_workout_types_test.dart

# Run tests matching a pattern
flutter test --name="isRacketSport"
```

Coverage report is generated at `coverage/lcov.info`.

### Android Kotlin Tests

```bash
cd android

# Run unit tests
./gradlew testDebugUnitTest

# Run specific test class
./gradlew test --tests HuaweiFitnessDataParsersTest

# Run with stacktrace for debugging
./gradlew testDebugUnitTest --stacktrace

# View test report
open app/build/reports/tests/testDebugUnitTest/index.html
```

Test results are at `android/app/build/reports/tests/`.

### Backend Tests

```bash
cd backend/functions

# Install dependencies
npm ci

# TypeScript typecheck
npm run build

# Run linter
npx eslint src --ext .ts

# Run all tests
npm test

# Run tests in watch mode
npm test -- --watch

# Run specific test file
npm test -- auth.test.ts

# Run with coverage
npm test -- --coverage
```

Coverage report is at `backend/functions/coverage/`.

### Build Verification

```bash
# Verify debug APK compiles (proves Android compile success)
flutter build apk --debug
```

This ensures there are no duplicate imports, Gradle misconfigurations, or Kotlin compilation errors.

## CI Pipeline

The CI pipeline runs automatically on:

- **Pull requests** (opened, synchronize, reopened) to any branch
- **Push to main**
- **Manual trigger** via workflow_dispatch

### CI Jobs

#### 1. Flutter Tests (`flutter-test`)

- Installs Flutter SDK 3.44.7
- Runs `flutter pub get`
- Runs `flutter analyze` (static analysis, linting)
- Runs `flutter test --coverage` (all unit/widget tests)
- Uploads coverage artifacts

**Expected tests:** ~89 Dart test files covering:
- Workout history (swim, run, strength sessions)
- Vitals (sleep analytics, recovery metrics)
- Programs (adherence, progress tracking)
- Device pairing and sync
- Huawei workout type helpers
- Racket sport HR parsing

#### 2. Android Kotlin Tests (`android-test`)

- Installs Java 17 and Flutter SDK
- Runs `./gradlew testDebugUnitTest` (Android unit tests)
- Runs `flutter build apk --debug` (compile check)
- Uploads test reports

**Expected tests:** ~9 Kotlin test files covering:
- Huawei wire framing (0x5A header, TLV encoding)
- Packet crypto (encryption, key derivation)
- Normal auth flow
- Workout sync (totals 0x17:0x08, data pages 0x17:0x0A)
- Fitness data sync (0x07:0x03, 0x0A, 0x0B)
- Sleep sequence parsing
- Physio capture probe
- File download protocol
- Sync lock mechanisms

**Regression coverage:**
- Workout totals 0x17:0x08 (racket sports, swim fields, calorie tags)
- Data pages 0x17:0x0A (racket/badminton packed HR at 1s intervals)
- Strength workout 5s interval parsing
- Fitness totals 0x07:0x03 (day rollup, calorie tags)
- Out-of-range HR filtering (40-220 bpm)

#### 3. Backend Tests (`backend-test`)

- Installs Node.js 22
- Runs `npm ci` (clean install)
- Runs `npm run build` (TypeScript typecheck)
- Runs ESLint (code quality)
- Runs Jest tests
- Uploads coverage

**Expected tests:** ~4 TypeScript test suites covering:
- Authentication middleware (read-only and write keys)
- Daily summary service (aggregation, null handling)
- Sync service (workout/sleep/totals ingest)
- Endpoint validation (date formats, required fields)

**Regression coverage:**
- Workout ingest with racket sport fields
- Workout ingest with swim-specific fields
- Workout ingest with strength fields
- Multi-data-type sync payloads
- Date range validation (max 31 days)
- Meal logging validation

### CI Triggers and [skip ci] Behavior

**Important:** The `ci.yml` workflow uses `on: pull_request` triggers, which run on PR events (opened, synchronize, reopened) **regardless of commit messages**. Unlike `on: push` triggers, which skip when `[skip ci]` or `[ci skip]` is in the commit message, `pull_request` triggers **always run** on PR activity.

This means:
- ✅ **CI runs on every PR sync**, even if commits have `[skip ci]`
- ✅ **CI runs when PR is opened or reopened**
- ⚠️  **Push to main with `[skip ci]` skips CI** (only the `on: push` trigger is skipped)

**For agents/automation:**
- **Do NOT use `[skip ci]` on PR branches** — it has no effect on PR CI runs, but may confuse readers
- **Use `[skip ci]` sparingly on main** — only for docs-only commits where CI is truly unnecessary
- **Manual override:** Use `workflow_dispatch` to manually trigger CI if needed

### Test Requirements for PRs

**All changes MUST:**

1. **Add or adjust tests** for new features or bug fixes
2. **Pass all CI checks** before merge (green checkmarks required)
3. **Not decrease coverage** — aim to maintain or increase test coverage
4. **Fix any new linter warnings** introduced by the change

**For agents and contributors:**

- If you add a new workout type, add tests to `huawei_workout_types_test.dart`
- If you change wire parsing, add tests to the relevant Android test files
- If you modify backend endpoints, add tests to `endpoints.test.ts` or `sync-service.test.ts`
- If you fix a bug, add a regression test that would have caught it

## Test Organization

### Flutter Tests (`test/`)

```
test/
├── features/
│   ├── workout_history/       # Workout sessions, TCX export, history UI
│   ├── vitals/                # Sleep, recovery, HR analytics
│   ├── programs/              # Training programs, adherence tracking
│   ├── food/                  # Meal logging
│   ├── device_pairing/        # BLE pairing flow
│   └── diagnostics/           # Export, forget/wipe
├── core/
│   ├── huawei/                # Dart-side BLE channel, sync lock
│   └── observability/         # Sentry, privacy scrubbing
└── fixtures/
    └── huawei/                # Binary wire fixtures (redacted)
```

### Android Tests (`android/app/src/test/`)

```
android/app/src/test/java/com/example/fitness_os/huawei/
├── HuaweiFramingTest.kt                    # TLV encoding/decoding
├── HuaweiPacketCryptoTest.kt               # Encryption, HMAC
├── HuaweiNormalAuthTest.kt                 # Auth handshake
├── HuaweiWorkoutSyncTest.kt                # 0x17:0x08, 0x17:0x0A
├── HuaweiFitnessDataSyncTest.kt            # 0x07:0x03, 0x0A, 0x0B (if exists)
├── HuaweiFitnessDataParsersTest.kt         # Regression tests for wire parsers
├── HuaweiSleepDetailsSequenceParserTest.kt # Sleep stage parsing
├── HuaweiPhysioCaptureProbeTest.kt         # Diagnostic probes
├── HuaweiFileDownloadTest.kt               # File download protocol
└── HuaweiSyncLockTest.kt                   # Sync coordination
```

### Backend Tests (`backend/functions/src/__tests__/`)

```
backend/functions/src/__tests__/
├── auth.test.ts            # Authentication middleware
├── daily-summary.test.ts   # Daily summary aggregation
├── sync-service.test.ts    # Ingest service tests
└── endpoints.test.ts       # API validation tests
```

## Key Test Cases

### Huawei Wire Parsers (Android)

- **Workout totals 0x17:0x08:** HR min/max, swim laps/strokes/SWOLF, racket sport type 129
- **Workout data 0x17:0x0A:** Racket packed HR (1s intervals), strength HR (5s intervals)
- **Fitness totals 0x07:0x03:** Day-anchor slot (1=today, N=N-1 days), steps, calories
- **HR filtering:** Out-of-range values (< 40 or > 220 bpm) are filtered

### Workout Type Helpers (Flutter)

- `isRacketSport(129)` → true (badminton)
- `isRacketSport(131)` → true (tennis)
- `isStrengthWorkout(140)` → true
- `isSwimWorkout(6)` → true (pool swim)
- `workoutTypeLabel(999)` → "Workout type 999" (graceful fallback)

### Backend Ingest (TypeScript)

- Sync workout with racket sport fields
- Sync workout with swim-specific fields
- Sync sleep with stages (deep, light, REM, awake)
- Sync daily totals (steps, active kcal, total kcal)
- Multi-data-type payloads (workouts + sleep + totals in one request)
- `syncedAt` timestamp is added to all records

## Test Coverage Goals

- **Flutter:** Maintain > 80% line coverage
- **Android:** > 70% line coverage (wire protocol is complex, focus on critical paths)
- **Backend:** > 85% line coverage (endpoints are straightforward, should be well-tested)

## Debugging Test Failures

### Flutter test fails

```bash
# Run with verbose output
flutter test --verbose

# Run single test
flutter test test/path/to/test_file.dart

# Debug widget tests with golden files
flutter test --update-goldens  # Only if UI changed intentionally
```

### Android test fails

```bash
# Run with stacktrace
./gradlew testDebugUnitTest --stacktrace

# Clean and retry
./gradlew clean testDebugUnitTest

# View detailed report
open app/build/reports/tests/testDebugUnitTest/index.html
```

### Backend test fails

```bash
# Run with verbose output
npm test -- --verbose

# Run single test file
npm test -- sync-service.test.ts

# Clear Jest cache
npm test -- --clearCache
```

### Build APK fails

```bash
# Clean Flutter build
flutter clean
flutter pub get

# Clean Gradle build
cd android && ./gradlew clean && cd ..

# Retry build
flutter build apk --debug --verbose
```

## Adding New Tests

### For new workout types

1. Add entry to `kHuaweiWorkoutTypes` in `lib/features/workout_history/domain/huawei_workout_types.dart`
2. Add tests in `test/features/workout_history/domain/huawei_workout_types_test.dart`
3. Verify `workoutTypeLabel()` and `workoutTypeCategory()` work correctly

### For new wire parsers

1. Add Kotlin parser in `android/app/src/main/kotlin/com/example/fitness_os/huawei/`
2. Add tests in `android/app/src/test/java/com/example/fitness_os/huawei/`
3. Use synthetic TLV fixtures, not AGPL-sourced bytes (see `test/fixtures/huawei/README.md`)

### For new backend endpoints

1. Add route handler in `backend/functions/src/index.ts`
2. Add service logic in `backend/functions/src/services/`
3. Add tests in `backend/functions/src/__tests__/`
4. Test auth middleware, validation, and Firestore writes

## CI Monitoring

- **View CI runs:** GitHub Actions tab in the repository
- **PR checks:** CI status shows on every PR (required for merge)
- **Failure notifications:** GitHub sends notifications for failed runs
- **Artifacts:** Test reports and coverage are uploaded as artifacts (7-day retention)

## Notes for Agents

When making changes to this repository:

1. **Always run tests locally** before pushing
2. **Add tests for your changes** — CI will fail if coverage drops
3. **Fix any analyze/lint warnings** introduced by your PR
4. **Do not skip CI on PR branches** — `[skip ci]` has no effect on PR events
5. **Wait for green checkmarks** before marking PR ready for review
6. **If CI fails, read the logs** — failure messages are detailed and actionable

## Continuous Improvement

This test suite is a living document. As bugs are found:

1. **Add a regression test** before fixing the bug
2. **Verify the test fails** on the buggy code
3. **Verify the test passes** after the fix
4. **Document the test** in commit messages and PR descriptions

This ensures bugs stay fixed and coverage improves over time.

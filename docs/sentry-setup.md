# Sentry Setup Guide

Fitness OS integrates Sentry for error monitoring and observability across both Dart (Flutter) and Kotlin (native Android) layers. This guide explains how to configure Sentry for development and production builds.

## Overview

Sentry provides:
- **Error tracking**: Automatic capture of uncaught exceptions
- **Breadcrumbs**: Privacy-safe event trails for Huawei LPv2 sync operations
- **Performance monitoring**: Transaction tracing for workout sync and data parsing
- **Privacy-first**: PII and health data are automatically scrubbed before upload

## Configuration

### 1. Obtain a Sentry DSN

1. Create a project on [sentry.io](https://sentry.io)
2. Copy your DSN (looks like `https://abc123@o123.ingest.sentry.io/456`)
3. Keep this secret — never commit it to git

### 2. Set the DSN for your environment

#### Development (local builds)

Create a `.env` file in the project root:

```bash
# .env (never commit this file!)
SENTRY_DSN=https://your-dsn-here@sentry.io/project-id
```

Add `.env` to your `.gitignore` if not already present.

#### CI/CD (GitHub Actions, etc.)

Set `SENTRY_DSN` as a secret environment variable in your CI system.

#### Optional: Force Sentry in debug builds

By default, Sentry only initializes in release/profile mode. To enable it in debug:

```bash
# .env
SENTRY_DSN=https://your-dsn-here@sentry.io/project-id
SENTRY_FORCE=true
```

### 3. Build with Sentry enabled

```bash
# Development build with Sentry
flutter build apk --dart-define-from-file=.env

# Or for quick debug testing with forced Sentry
flutter run --dart-define-from-file=.env
```

**Without a `.env` file**, Sentry is disabled and the app runs normally with no observability overhead.

## What Gets Logged

### Privacy-Safe Data

Sentry **only** logs:

✅ Workout type codes (e.g. `type=129` for badminton)  
✅ TLV tag IDs and lengths (e.g. `tag=0x0c, length=4`)  
✅ Counts (workout count, data pages, segments)  
✅ Parse failures and error messages  
✅ Connection/auth step names  
✅ Timeout events  
✅ Sync phase transitions (Count → Totals → Enrichment)  

### What's Never Sent

❌ Heart rate values or series  
❌ GPS coordinates or location data  
❌ Raw sample bodies (HR points, leftover TLVs)  
❌ MAC addresses (redacted to `AA:••:••:••:••:FF`)  
❌ User IDs or account tokens  
❌ Workout totals (calories, distance, steps)  

All health data is scrubbed by `SentryPrivacyScrub.beforeSend` on the Dart side and never included in Kotlin breadcrumbs.

## Key Breadcrumb Categories

### Dart Side

| Category | Description | Example |
|----------|-------------|---------|
| `workout.type` | Unknown or mapped workout types | `Unknown workout type encountered: 129` |
| `workout.sync` | Sync start/complete/error | `Workout sync complete: ok, workoutCount=5` |
| `workout.parse` | TLV parse failures | `TLV parse failure: tag=0x0c, length=4` |
| `workout.enrich` | Enrichment status | `Workout enrichment: #17, dataCount=1, status=ok` |
| `workout.badminton` | Badminton-specific data | `Badminton workout data parsed: #125` |

### Kotlin Side

| Category | Description | Example |
|----------|-------------|---------|
| `huawei.connection` | Bluetooth connection events | `Huawei BT connected: AA:••:••:••:••:FF` |
| `huawei.auth` | Authentication steps | `Huawei auth: link_params_response` |
| `huawei.workout.sync` | Workout sync phases | `Workout sync: count_request` |
| `huawei.workout.parse` | Workout parsing events | `Workout totals parsed: #17 type=129` |
| `huawei.workout.racket` | Racket sport workouts | `Racket sport workout: #125 type=129` |
| `huawei.parse` | TLV parse failures | `TLV parse failure: totals_parse_failed_workout_17` |

## Testing Your Setup

1. **Build with an invalid DSN** to ensure the app still runs:
   ```bash
   echo "SENTRY_DSN=" > .env
   flutter run
   ```
   The app should start normally with a log: `Sentry not initialized (no DSN or debug mode)`

2. **Trigger a test error**:
   ```dart
   // Add to your test code
   import 'package:sentry_flutter/sentry_flutter.dart';
   
   Sentry.captureException(Exception('Sentry test exception'));
   ```

3. **Check the Sentry dashboard** for the event within 1-2 minutes.

## Troubleshooting

### Sentry not initializing

- **Symptom**: No events in Sentry dashboard
- **Check**: Run `flutter run -v` and look for:
  ```
  Sentry init failed — continuing without observability
  ```
- **Fix**: Verify your DSN in `.env` and rebuild with `--dart-define-from-file=.env`

### DSN exposed in logs

- **Symptom**: DSN visible in terminal output
- **Fix**: Never log `SentryConfig.dsn` directly. Use `SentryConfig.hasDsn` for boolean checks.

### Too many events

- **Symptom**: Hitting Sentry quota limits
- **Fix**: Adjust `tracesSampleRate` in `bootstrap.dart` (default: 1.0 = 100%)

## Kotlin-Only Initialization

The Kotlin/Android layer automatically inherits Sentry from the Dart initialization via `SentryFlutter.init()`. No separate Android manifest configuration is needed.

However, if you need to test Kotlin breadcrumbs independently:

```kotlin
// This is only for testing — production uses Dart initialization
import io.sentry.Sentry

if (!Sentry.isEnabled()) {
    Sentry.init { options ->
        options.dsn = "your-test-dsn"
        options.environment = "test"
    }
}
```

## Code References

- **Dart config**: `lib/core/observability/sentry_config.dart`
- **Dart scrubbing**: `lib/core/observability/sentry_privacy_scrub.dart`
- **Dart breadcrumbs**: `lib/core/observability/workout_sync_breadcrumbs.dart`
- **Kotlin breadcrumbs**: `android/app/src/main/kotlin/com/example/fitness_os/observability/HuaweiSyncBreadcrumbs.kt`

## Security Notes

1. **Never commit `.env`** — add it to `.gitignore`
2. **Rotate DSNs** if accidentally exposed
3. **Use separate DSNs** for dev/staging/production
4. **Review scrubbing rules** in `SentryPrivacyScrub` before adding new instrumentation
5. **Test with real health data** to ensure no leaks slip through

## Further Reading

- [Sentry Flutter Documentation](https://docs.sentry.io/platforms/flutter/)
- [Sentry Android Documentation](https://docs.sentry.io/platforms/android/)
- [Privacy Scrubbing Best Practices](https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/)

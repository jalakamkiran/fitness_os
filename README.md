# Fitness OS (Fathom)

A Flutter-based swim companion for Huawei GT5 Pro watches with direct LPv2 RFCOMM sync.

## Features

- **Direct LPv2 Sync**: Bluetooth workout and vitals sync without cloud dependency
- **Comprehensive Workout Types**: Badminton, swimming, running, strength, and 30+ sport types
- **Privacy-First Observability**: Optional Sentry integration with automatic PII scrubbing
- **Offline AI Coach**: Local Gemma-based swim coaching and analysis

## Setup

### Prerequisites

- Flutter SDK 3.9.2+
- Android Studio with SDK 24+
- Huawei Watch GT5 Pro

### Building

```bash
# Standard build (no observability)
flutter build apk

# With Sentry observability (requires DSN)
flutter build apk --dart-define-from-file=.env
```

### Sentry Configuration (Optional)

Sentry provides error monitoring and breadcrumb trails for debugging sync issues. It's completely optional—the app works perfectly without it.

1. **Create `.env` file** (never commit this):
   ```bash
   SENTRY_DSN=https://your-dsn@sentry.io/project-id
   ```

2. **Add to `.gitignore`**:
   ```
   .env
   ```

3. **Build with Sentry enabled**:
   ```bash
   flutter run --dart-define-from-file=.env
   ```

4. **Force Sentry in debug mode** (optional):
   ```bash
   # .env
   SENTRY_DSN=https://your-dsn@sentry.io/project-id
   SENTRY_FORCE=true
   ```

**See [`docs/sentry-setup.md`](docs/sentry-setup.md) for complete Sentry configuration guide.**

### Privacy & Observability

When Sentry is enabled:
- ✅ Logs: workout type codes, TLV tag IDs, counts, error messages
- ❌ Never logs: HR values, GPS coords, raw health data, MAC addresses (redacted)

All health data is automatically scrubbed before upload via `SentryPrivacyScrub`.

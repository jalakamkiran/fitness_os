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
# Standard build (local storage only, no cloud sync)
flutter build apk

# With backend sync enabled (syncs data to Firebase)
flutter build apk --dart-define=BACKEND_WRITE_KEY=<device-write-key>

# With Sentry observability (requires DSN)
flutter build apk --dart-define-from-file=.env

# Full release build (Sentry + backend sync)
# Create .env with SENTRY_DSN and BACKEND_WRITE_KEY
flutter build apk --dart-define-from-file=.env
```

### Backend Sync Configuration (Optional)

The app can sync workout and vitals data to a Firebase backend, exposing a read-only API for an AI fitness coach.

**Backend sync is optional**—the app works perfectly with local storage only.

#### For Local Builds

1. **Get the device write key** from Firebase:
   ```bash
   firebase functions:secrets:access DEVICE_WRITE_KEY --project fathom-fitness-os
   ```

2. **Build with backend sync enabled**:
   ```bash
   flutter build apk --dart-define=BACKEND_WRITE_KEY=<paste-key-here>
   ```

3. **Or add to `.env` file** (never commit):
   ```bash
   BACKEND_WRITE_KEY=<your-device-write-key>
   ```

#### For GitHub Actions / CI

Add `BACKEND_WRITE_KEY` as a repository secret:

1. Go to **GitHub repo → Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Name: `BACKEND_WRITE_KEY`
4. Value: (paste the key from Firebase)
5. Click **Add secret**

The workflow in `.github/workflows/app-distribution.yml` will automatically include it in release builds.

**Value must match** the Firebase Functions secret `DEVICE_WRITE_KEY`.

**See [`docs/backend.md`](docs/backend.md) for complete backend setup and API documentation.**

### Sentry Configuration (Optional)

Sentry provides error monitoring and breadcrumb trails for debugging sync issues. It's completely optional—the app works perfectly without it.

1. **Create `.env` file** (never commit this):
   ```bash
   SENTRY_DSN=https://your-dsn@sentry.io/project-id
   BACKEND_WRITE_KEY=<device-write-key>  # Optional, for backend sync
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

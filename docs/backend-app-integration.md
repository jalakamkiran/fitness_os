# Backend Sync - App Integration

## Overview

The Flutter app syncs fitness data to the Firebase backend on:
1. **App open** - Immediate sync when the app launches or resumes
2. **Periodic background** - WorkManager runs sync ~hourly (Android only)

Sync is **incremental** and **idempotent** - records are identified by unique IDs and updates are merged.

## Configuration

Backend sync is **opt-in** and requires build-time environment variables.

### 1. Get Firebase Functions URL

After deploying the backend:
```bash
cd backend
firebase deploy
# Functions URL: https://asia-south1-fathom-fitness-os.cloudfunctions.net/api
```

**Note:** The Express app has its own `/api` prefix, so endpoints are `/api/api/v1/...`

### 2. Get Device Write Key

```bash
firebase functions:secrets:access DEVICE_WRITE_KEY
# Or check the original key you generated during setup
```

### 3. Build App with Backend Config

**For development/testing:**
```bash
flutter run --dart-define=BACKEND_URL=https://asia-south1-fathom-fitness-os.cloudfunctions.net/api \
           --dart-define=BACKEND_WRITE_KEY=<your-device-write-key>
```

**For release builds:**
```bash
flutter build apk --release \
  --dart-define=BACKEND_URL=https://asia-south1-fathom-fitness-os.cloudfunctions.net/api \
  --dart-define=BACKEND_WRITE_KEY=<your-device-write-key>
```

**Build without backend sync:**
```bash
flutter build apk --release
# Omitting dart-define flags disables backend sync
```

## How It Works

### On App Open

1. App initializes and loads dependencies
2. `AutoSyncLifecycle` triggers on resume
3. After Huawei watch reconnects, `BackendSyncService.syncToBackend()` is called
4. Sync respects 5-minute rate limit (won't sync if last sync < 5 min ago)

### Periodic Background Sync (Android)

1. `WorkManager` schedules a periodic task (~hourly)
2. Task wakes up the Flutter engine in background
3. `BackgroundSyncWorker` runs sync
4. Requires network connectivity (WorkManager constraint)

### Sync Payload

The app sends:
- **Workouts** - All synced workout sessions from local storage
- **Sleep** - Sleep sessions with stages and TruSleep enrichment
- **Daily Totals** - Steps, calories, distance per day
- **Heart Rate** - Daily resting/avg/max HR
- **HRV** - Daily HRV measurements

Data is read from:
- `WorkoutHistoryRepository.loadWorkouts()`
- `VitalsRepository.loadSleepSessions()` + `loadSleepStages()` + `loadTruSleepSummary()`
- `VitalsRepository.loadFitnessTotals()`
- `VitalsRepository.loadDailyHr()`

### Sync Logic

```dart
// lib/core/backend/backend_sync_service.dart
Future<void> syncToBackend() async {
  // Check if sync is enabled and rate limit allows
  if (!canSync) return;
  
  // Build payload from local repositories
  final payload = await _buildSyncPayload();
  
  // POST to /api/v1/sync
  await _dio.post('/sync', data: payload, ...);
  
  // Update last sync timestamp
  await _prefs.setInt('backend_last_sync_ms', now);
}
```

## Testing

### Test with Emulator

1. Start Firebase emulator:
```bash
cd backend
npm run emulator
```

2. Build app with emulator URL:
```bash
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:5001/fathom-fitness-os/asia-south1/api \
           --dart-define=BACKEND_WRITE_KEY=test-write-key
```

3. Open app and trigger sync (logs will show in console)

### Verify Sync

Check backend logs:
```bash
firebase functions:log --only api
```

Query Firestore:
```bash
firebase firestore:get workouts --limit 5
```

Or use the read-only API:
```bash
curl -H "Authorization: Bearer <READ_ONLY_API_KEY>" \
  "https://asia-south1-fathom-fitness-os.cloudfunctions.net/api/api/v1/sync-status"
```

## Troubleshooting

**Sync not running:**
- Check logs: `flutter logs` will show "Backend sync failed" if it's attempting
- Verify `BackendConfig.isEnabled` returns true (logged on startup)
- Ensure `BACKEND_URL` and `BACKEND_WRITE_KEY` are set at build time

**401 Unauthorized:**
- Verify `BACKEND_WRITE_KEY` matches the Functions secret
- Check `Authorization: Bearer <key>` header is present

**Network errors:**
- Ensure device has internet connectivity
- Check Firebase Functions URL is accessible
- For emulator, use `10.0.2.2` (Android) or `localhost` (iOS)

**Rate limit hit:**
- Sync respects 5-minute rate limit - wait and retry
- Check `backend_last_sync_ms` in SharedPreferences

**Empty payload:**
- Ensure data exists locally (run a Huawei watch sync first)
- Check repositories return non-empty lists

## Security

- **Write key never committed** - Passed as build-time environment variable only
- **Sync is one-way** - App writes to backend, never reads
- **No personal data in logs** - Sync errors don't log payload contents
- **Rate limited** - 5-minute minimum between syncs prevents abuse

## Disabling Sync

To disable backend sync:
1. Build without `BACKEND_URL` and `BACKEND_WRITE_KEY` dart-define flags
2. `BackendConfig.isEnabled` will return `false`
3. Sync service won't be registered in DI container
4. No network calls will be made

## Future Enhancements

- [ ] Retry with exponential backoff on network failures
- [ ] Selective sync (only changed records since last sync)
- [ ] Sync progress notification (Android)
- [ ] Manual sync button in Settings
- [ ] Sync health check (show last successful sync time in UI)

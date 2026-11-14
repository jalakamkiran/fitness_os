# Fitness OS Backend

Firebase-based backend for syncing Huawei Watch GT5 Pro fitness data and exposing a read-only API for the AI fitness coach (Arjun).

## Architecture

### Storage
- **Firestore collections:**
  - `workouts` - Individual exercise sessions
  - `sleep` - Sleep sessions with stages
  - `dailyTotals` - Daily activity summaries (steps, calories, distance)
  - `heartRate` - Daily HR metrics (resting, avg, max)
  - `hrv` - Daily HRV data
  - `weight` - Weight measurements
  - `meals` - Food logger entries (optional, disabled by default)

### Authentication
Two authentication modes for app writes:
1. **Firebase Auth** - Single user authentication via Firebase Authentication
2. **Device Write Key** - Simple bearer token stored as Functions secret `DEVICE_WRITE_KEY`

Read-only API uses a long-lived bearer token stored as `READ_ONLY_API_KEY`.

### Daily Summaries
Computed on-demand from Firestore data, grouped by IST date (Asia/Kolkata, UTC+5:30).

## Setup

### Prerequisites
- Node.js 20
- Firebase CLI (`npm install -g firebase-tools`)
- Firebase project (free Spark plan is sufficient for single-user)

### 1. Create Firebase Project

```bash
# Login to Firebase
firebase login

# Create a new project in Firebase console or via CLI
firebase projects:create fitness-os-backend

# Select the project
firebase use fitness-os-backend
```

### 2. Initialize Firestore

```bash
# In Firebase Console:
# 1. Navigate to Firestore Database
# 2. Click "Create database"
# 3. Choose production mode
# 4. Select asia-south1 region (closest to IST timezone)
```

Or via CLI:
```bash
firebase firestore:create --location=asia-south1
```

### 3. Set Secrets

Generate a secure random API key for read-only access:
```bash
# Generate read-only API key (save this for Arjun)
openssl rand -hex 32

# Set as Functions secret
firebase functions:secrets:set READ_ONLY_API_KEY
# Paste the generated key when prompted
```

Generate a device write key:
```bash
# Generate device write key (save this for the Flutter app)
openssl rand -hex 32

# Set as Functions secret
firebase functions:secrets:set DEVICE_WRITE_KEY
# Paste the generated key when prompted
```

### 4. Install Dependencies

```bash
cd backend
npm install
cd functions
npm install
```

### 5. Deploy

```bash
cd backend
npm run build
firebase deploy
```

This deploys:
- Firestore rules
- Firestore indexes
- Cloud Functions

### 6. Get API Base URL

After deployment, Firebase will output the Cloud Functions URL:
```
Function URL (api): https://us-central1-fitness-os-backend.cloudfunctions.net/api
```

Save this URL - it's your API base for all endpoints.

## API Reference

All endpoints use `Authorization: Bearer <token>` header.

### Read-Only Endpoints (Use READ_ONLY_API_KEY)

Rate limit: 60 requests per hour per IP.

#### GET /api/v1/daily-summary

Fetch daily summary for a single day or date range.

**Single day:**
```bash
curl -H "Authorization: Bearer <READ_ONLY_API_KEY>" \
  "https://<functions-url>/api/v1/daily-summary?date=2026-11-14"
```

**Date range (max 31 days):**
```bash
curl -H "Authorization: Bearer <READ_ONLY_API_KEY>" \
  "https://<functions-url>/api/v1/daily-summary?from=2026-11-01&to=2026-11-14"
```

**Response:**
```json
{
  "date": "2026-11-14",
  "activeKcal": 650,
  "totalKcal": 2450,
  "restingKcal": 1800,
  "steps": 12500,
  "distanceKm": 8.5,
  "restingHr": 52,
  "hrvMs": 65,
  "sleep": {
    "start": "2026-11-13T22:30:00+05:30",
    "end": "2026-11-14T06:45:00+05:30",
    "totalMin": 495,
    "deepMin": 120,
    "remMin": 95,
    "lightMin": 245,
    "awakeMin": 35,
    "score": 85
  },
  "weightKg": 75.5,
  "workouts": [
    {
      "id": "workout_1234",
      "type": "running",
      "start": "2026-11-14T06:00:00+05:30",
      "end": "2026-11-14T07:00:00+05:30",
      "durationMin": 60,
      "activeKcal": 500,
      "avgHr": 150,
      "maxHr": 180
    },
    {
      "id": "workout_1235",
      "type": "strength",
      "start": "2026-11-14T17:30:00+05:30",
      "end": "2026-11-14T18:30:00+05:30",
      "durationMin": 60,
      "activeKcal": 150,
      "avgHr": 120,
      "maxHr": 145
    }
  ],
  "lastSyncedAt": "2026-11-14T18:45:30+05:30"
}
```

**Null handling:** Missing metrics are `null`, never `0`. This distinguishes "not measured" from "zero value".

#### GET /api/v1/workouts

Fetch workouts within date range.

```bash
curl -H "Authorization: Bearer <READ_ONLY_API_KEY>" \
  "https://<functions-url>/api/v1/workouts?from=2026-11-01&to=2026-11-14"
```

**Response:**
```json
[
  {
    "id": "workout_1234",
    "type": "swimming",
    "startTime": "2026-11-14T06:00:00+05:30",
    "endTime": "2026-11-14T07:15:00+05:30",
    "durationMin": 75,
    "activeKcal": 550,
    "avgHr": 145,
    "maxHr": 165,
    "distanceKm": 2.5,
    "steps": null,
    "swimLaps": 50,
    "swimStrokes": 1250,
    "swimAvgSwolf": 42,
    "swimPoolLength": 50,
    "load": 320,
    "aerobicEffect": 4.5,
    "anaerobicEffect": 2.1,
    "recoveryTime": 36
  }
]
```

**Workout types:** All lowercase strings:
- `running`, `walking`, `cycling`, `swimming`, `strength`, `badminton`, `mma`, `hiking`, `yoga`, `other`

**Swim extras:** `swimLaps`, `swimStrokes`, `swimAvgSwolf`, `swimPoolLength` are only present for swim workouts.

**Huawei extras:** `load` (training load), `aerobicEffect`, `anaerobicEffect`, `recoveryTime` (hours) are included when available.

#### GET /api/v1/weight

Fetch weight measurements within date range.

```bash
curl -H "Authorization: Bearer <READ_ONLY_API_KEY>" \
  "https://<functions-url>/api/v1/weight?from=2026-11-01&to=2026-11-14"
```

**Response:**
```json
[
  {
    "timestamp": "2026-11-14T07:30:00+05:30",
    "weightKg": 75.5
  },
  {
    "timestamp": "2026-11-07T07:25:00+05:30",
    "weightKg": 76.0
  }
]
```

#### GET /api/v1/sync-status

Get last sync timestamp for each data type.

```bash
curl -H "Authorization: Bearer <READ_ONLY_API_KEY>" \
  "https://<functions-url>/api/v1/sync-status"
```

**Response:**
```json
{
  "workouts": "2026-11-14T18:45:30+05:30",
  "sleep": "2026-11-14T08:15:20+05:30",
  "dailyTotals": "2026-11-14T18:45:30+05:30",
  "heartRate": "2026-11-14T18:45:30+05:30",
  "hrv": "2026-11-14T08:15:20+05:30",
  "weight": "2026-11-14T07:30:00+05:30",
  "meals": null
}
```

### Write Endpoints (Use DEVICE_WRITE_KEY)

#### POST /api/v1/sync

Sync data from the Flutter app.

```bash
curl -X POST \
  -H "Authorization: Bearer <DEVICE_WRITE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "workouts": [...],
    "sleep": [...],
    "dailyTotals": [...],
    "heartRate": [...],
    "hrv": [...],
    "weight": [...]
  }' \
  "https://<functions-url>/api/v1/sync"
```

**Payload format:** See `backend/functions/src/services/sync-service.ts` for the full TypeScript interface.

**Response:**
```json
{
  "synced": 42
}
```

#### POST /api/v1/meals (Optional, Disabled by Default)

Log a meal. Enable by setting `MEALS_WRITE_ENABLED=true` in Functions config.

```bash
curl -X POST \
  -H "Authorization: Bearer <DEVICE_WRITE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2026-11-14T12:30:00+05:30",
    "items": ["chicken breast", "brown rice", "broccoli"],
    "grams": [150, 200, 100],
    "kcal": 550,
    "protein": 45
  }' \
  "https://<functions-url>/api/v1/meals"
```

To enable:
```bash
firebase functions:config:set meals.write_enabled=true
firebase deploy --only functions
```

## Local Development

### Firebase Emulator

Test functions locally without deploying:

```bash
cd backend
npm run emulator
```

This starts:
- Functions emulator on `http://localhost:5001`
- Firestore emulator on `http://localhost:8080`
- Emulator UI on `http://localhost:4000`

Set environment variables for testing:
```bash
export READ_ONLY_API_KEY="test-read-key"
export DEVICE_WRITE_KEY="test-write-key"
```

Test the API:
```bash
curl -H "Authorization: Bearer test-read-key" \
  "http://localhost:5001/<project-id>/us-central1/api/api/v1/sync-status"
```

### Running Tests

```bash
cd backend/functions
npm test
```

## Data Priorities

### P0 (Critical)
- Active/total calories
- Exercise sessions (type, duration, time)
- Steps
- Sleep (duration, stages, score)
- Weight

### P1 (High)
- HR per session (avg, max)
- Resting HR
- HRV
- Distance/speed

### P2 (Nice to Have)
- SpO2
- Respiratory rate
- Swim-specific metrics (SWOLF, laps)
- Training load, recovery time, VO2max

## Deployment Checklist

- [ ] Firebase project created
- [ ] Firestore database initialized (asia-south1 region)
- [ ] `READ_ONLY_API_KEY` secret set
- [ ] `DEVICE_WRITE_KEY` secret set
- [ ] Dependencies installed (`npm install` in backend/ and backend/functions/)
- [ ] Functions deployed (`firebase deploy`)
- [ ] API base URL saved
- [ ] Keys shared with app team and Arjun (securely)
- [ ] Test API endpoint with curl
- [ ] Verify rate limiting works

## Monitoring

View logs:
```bash
firebase functions:log
```

Monitor usage in Firebase Console:
- Functions → Dashboard (invocations, errors, execution time)
- Firestore → Usage (reads, writes, deletes)

## Security Notes

- **Never commit secrets** - Keys are stored as Functions secrets
- **Firestore rules deny direct access** - All access must go through Cloud Functions
- **Rate limiting** - 60 req/hour prevents abuse
- **Read-only key** - Arjun can only read, never write or delete
- **Device write key** - App can only write via sync endpoint, not query Firestore directly

## Troubleshooting

**"Missing authorization header"**
- Ensure `Authorization: Bearer <key>` header is present
- Check key is correct (no extra spaces or newlines)

**"Rate limit exceeded"**
- Wait for the retry period (returned in `retryAfter` field)
- Implement exponential backoff in the client

**"Invalid date format"**
- Use `YYYY-MM-DD` format for all dates
- Ensure date range is ≤31 days

**Functions deployment fails**
- Check Node version is 20 (`node --version`)
- Verify all dependencies are installed
- Check Firebase project is selected (`firebase use`)

**Empty responses**
- Data may not be synced yet - check `/api/v1/sync-status`
- Verify date range matches synced data
- Check Firestore console for actual documents

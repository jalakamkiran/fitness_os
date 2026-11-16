# Fathom Sync Webhook Setup

This document explains how to configure the outbound sync webhook for the Fathom backend.

## Overview

After any successful sync write (workouts, daily calories/steps, sleep, heart rate, weight), the backend can POST a notification to a configured webhook URL. This allows external services to be notified of new fitness data without polling the API.

## Configuration

The webhook is configured via Firebase secrets:

### 1. Set the webhook URL

```bash
firebase functions:secrets:set FATHOM_SYNC_WEBHOOK_URL
```

When prompted, enter the full URL (e.g., `https://your-service.example.com/fathom-sync`).

### 2. Set the authentication key

```bash
firebase functions:secrets:set FATHOM_SYNC_WEBHOOK_KEY
```

When prompted, enter the Bearer token (e.g., a random API key like `sk_live_abc123...`).

### 3. Deploy the function

```bash
cd backend/functions
npm run build
firebase deploy --only functions:api
```

## Webhook Behavior

### When is it sent?

- After **every successful sync** from the mobile app
- One POST per phone sync (debounced/batched, not one per record)

### What if it fails?

- **Fire-and-forget**: Webhook failures never fail the sync
- 5-second timeout
- Errors are logged but do not affect data ingestion

### What if URL/key is unset?

- Skips silently (no error)
- Safe to leave unconfigured if you don't need webhook notifications

## Webhook Request Format

### Headers

```http
POST /your-endpoint HTTP/1.1
Host: your-service.example.com
Content-Type: application/json
Authorization: Bearer YOUR_WEBHOOK_KEY
User-Agent: Fathom-Fitness-OS/1.0
```

### Payload

```json
{
  "event": "sync_completed",
  "userId": "owner",
  "timestamp": "2026-11-16T13:00:00.000Z",
  "dataTypes": ["workouts", "dailyTotals", "sleep"],
  "summary": {
    "workouts": [
      {
        "id": "workout_2",
        "type": "129",
        "startTime": "2026-11-15T07:32:00.000Z",
        "durationMin": 111,
        "activeKcal": 412
      }
    ],
    "dailyTotals": [
      {
        "date": "2026-11-15",
        "activeKcal": 450,
        "steps": 8500
      }
    ],
    "sleep": [
      {
        "id": "sleep_1731628800",
        "date": "2026-11-15",
        "totalMin": 480
      }
    ]
  }
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `event` | string | Always `"sync_completed"` |
| `userId` | string | User ID (typically `"owner"` for single-user app) |
| `timestamp` | string | ISO 8601 timestamp when webhook was sent |
| `dataTypes` | string[] | Which data types were synced (e.g., `["workouts", "sleep"]`) |
| `summary` | object | Per-type summary with IDs, dates, and key metrics |

### Summary Details

**Workouts**:
- `id`: Firestore document ID (`workout_{number}`)
- `type`: Workout type code as string (e.g., `"129"` for badminton)
- `startTime`: ISO 8601 start time
- `durationMin`: Duration in minutes
- `activeKcal`: Active calories (null if not available)

**Sleep**:
- `id`: Firestore document ID (`sleep_{beginUnix}`)
- `date`: Date in YYYY-MM-DD format
- `totalMin`: Total sleep duration in minutes

**Daily Totals**:
- `date`: Date in YYYY-MM-DD format
- `activeKcal`: Active calories for the day (null if not available)
- `steps`: Step count for the day (null if not available)

**Heart Rate**:
- `date`: Date in YYYY-MM-DD format

**HRV**:
- `date`: Date in YYYY-MM-DD format

**Weight**:
- `timestamp`: ISO 8601 timestamp
- `weightKg`: Weight in kilograms

**Meals**:
- `id`: Meal ID
- `timestamp`: ISO 8601 timestamp
- `kcal`: Total calories

## Expected Response

Your webhook endpoint should:
- Respond with any 2xx status code (200-299) for success
- Respond quickly (within 5 seconds)
- Handle duplicate notifications gracefully (sync may be retried)

## Security

### Authentication

The webhook key is sent as a Bearer token in the `Authorization` header:

```http
Authorization: Bearer YOUR_WEBHOOK_KEY
```

**Your endpoint should**:
1. Verify the `Authorization` header is present
2. Check the token matches your expected secret
3. Reject requests with 401 Unauthorized if token is invalid

### Best Practices

1. **Use HTTPS**: Only accept webhooks over HTTPS
2. **Validate payload**: Check `event` field is `"sync_completed"`
3. **Idempotency**: Use `summary.workouts[].id` or `summary.sleep[].id` to detect duplicates
4. **Rate limiting**: Consider rate limiting per `userId` to prevent abuse

## Troubleshooting

### Webhook not being sent

1. Check secrets are set:
   ```bash
   firebase functions:secrets:access FATHOM_SYNC_WEBHOOK_URL
   firebase functions:secrets:access FATHOM_SYNC_WEBHOOK_KEY
   ```

2. Check Cloud Functions logs:
   ```bash
   firebase functions:log --only api
   ```

3. Look for `[Webhook]` entries:
   - `Sent successfully: 200` - webhook worked
   - `Request failed: ...` - network/DNS issue
   - `Request timed out after 5s` - endpoint too slow
   - `Server returned 4xx/5xx` - endpoint rejected

### Testing the webhook

Use `curl` to simulate a webhook POST:

```bash
curl -X POST https://your-service.example.com/fathom-sync \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_WEBHOOK_KEY" \
  -d '{
    "event": "sync_completed",
    "userId": "owner",
    "timestamp": "2026-11-16T13:00:00.000Z",
    "dataTypes": ["workouts"],
    "summary": {
      "workouts": [{
        "id": "workout_test",
        "type": "129",
        "startTime": "2026-11-15T07:32:00.000Z",
        "durationMin": 60,
        "activeKcal": 400
      }]
    }
  }'
```

## Disabling the Webhook

To disable webhook notifications:

1. Unset the URL secret:
   ```bash
   firebase functions:secrets:destroy FATHOM_SYNC_WEBHOOK_URL
   ```

2. Redeploy:
   ```bash
   firebase deploy --only functions:api
   ```

The function will skip webhook calls silently when the URL is unset.

## Example Implementation (Node.js/Express)

```javascript
const express = require('express');
const app = express();

app.use(express.json());

app.post('/fathom-sync', (req, res) => {
  // Verify authorization
  const auth = req.headers.authorization;
  if (!auth || auth !== 'Bearer YOUR_SECRET_KEY') {
    return res.status(401).json({error: 'Unauthorized'});
  }

  // Validate payload
  if (req.body.event !== 'sync_completed') {
    return res.status(400).json({error: 'Invalid event'});
  }

  // Process sync notification
  console.log('Sync received:', {
    userId: req.body.userId,
    dataTypes: req.body.dataTypes,
    workoutCount: req.body.summary.workouts?.length || 0,
  });

  // TODO: Store in database, trigger alerts, etc.

  res.status(200).json({received: true});
});

app.listen(3000);
```

## Implementation Details

See source files:
- `backend/functions/src/services/webhook-notifier.ts` - Webhook logic
- `backend/functions/src/services/sync-service.ts` - Integration with sync flow
- `backend/functions/src/index.ts` - Secrets configuration

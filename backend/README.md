# Fitness OS Backend

Firebase backend for syncing Huawei Watch GT5 Pro fitness data.

## Quick Start

See [docs/backend.md](../docs/backend.md) for complete setup and API documentation.

### Prerequisites
- Node.js 20
- Firebase CLI: `npm install -g firebase-tools`

### Setup

1. **Create Firebase Project**
```bash
firebase login
firebase projects:create fitness-os-backend
firebase use fitness-os-backend
```

2. **Initialize Firestore**
```bash
firebase firestore:create --location=asia-south1
```

3. **Set Secrets**
```bash
# Generate keys
openssl rand -hex 32  # READ_ONLY_API_KEY
openssl rand -hex 32  # DEVICE_WRITE_KEY

# Set in Firebase
firebase functions:secrets:set READ_ONLY_API_KEY
firebase functions:secrets:set DEVICE_WRITE_KEY
```

4. **Install and Deploy**
```bash
npm install
cd functions && npm install && cd ..
npm run deploy
```

### Local Development

```bash
npm run emulator
```

### Testing

```bash
cd functions
npm test
```

## Documentation

- [Backend Architecture & API](../docs/backend.md)
- [App Integration](../docs/backend-app-integration.md)

## API Endpoints

Base URL: `https://asia-south1-fathom-fitness-os.cloudfunctions.net/api`

**Note:** Express routes maintain their own `/api` prefix, so full endpoints are:
- `GET /api/api/v1/daily-summary` - Daily fitness summary
- `GET /api/api/v1/workouts` - Workout sessions
- `GET /api/api/v1/weight` - Weight measurements
- `GET /api/api/v1/sync-status` - Last sync timestamps
- `POST /api/api/v1/sync` - Sync data from app (write-only)

Rate limit: 60 requests/hour per IP (in-memory, resets on cold start)

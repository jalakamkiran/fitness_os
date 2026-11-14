# 🔐 Required GitHub Secrets for CI/CD

**URGENT**: Add these secrets to fix the CI build and enable observability.

Navigate to: https://github.com/jalakamkiran/fitness_os/settings/secrets/actions

---

## ❗ CRITICAL Secrets (CI Build Will Fail Without These)

### 1. `SENTRY_DSN` (REQUIRED)

**Purpose**: Crash reporting and sync failure observability.

**Problem**: CI build 0.1.0+10 sent **ZERO events** to Sentry because this wasn't configured.

**How to get**:
1. Go to Sentry project: https://sentry.io/organizations/kiran-sai/projects/fathom/
2. Navigate to: **Settings** → **Client Keys (DSN)**
3. Copy the DSN (format: `https://<key>@o<org-id>.ingest.sentry.io/<project-id>`)

**Example**:
```
SENTRY_DSN=https://abc123def456@o123456.ingest.sentry.io/789012
```

**What happens without it**: 
- ❌ CI build will **FAIL** with clear error message
- ❌ No crash reports or sync error telemetry
- ❌ Sync failures are invisible to debugging

---

### 2. `FIREBASE_SERVICE_ACCOUNT_JSON` (REQUIRED)

**Purpose**: Upload APKs to Firebase App Distribution.

**How to get**:
1. Go to: https://console.cloud.google.com
2. Select project: `fathom-fitness-os`
3. Navigate to: **IAM & Admin** → **Service Accounts**
4. Find or create service account: `github-actions-app-distribution`
5. Grant role: **Firebase App Distribution Admin**
6. Create JSON key: **KEYS** tab → **ADD KEY** → **Create new key** → **JSON**
7. Download the JSON file
8. Copy the **entire JSON content** and paste as the secret value

**What happens without it**: 
- ❌ CI build succeeds but APK upload to Firebase fails
- ❌ Testers don't receive OTA updates

---

## 🔧 Optional Secrets

### 3. `BACKEND_WRITE_KEY` (Optional)

**Purpose**: Sync workout and vitals data to Firebase backend for AI coach access.

**How to get**:
```bash
firebase functions:secrets:access DEVICE_WRITE_KEY --project fathom-fitness-os
```

**Value must match** the Firebase Functions secret `DEVICE_WRITE_KEY`.

**What happens without it**: 
- ✅ App still works perfectly
- ℹ️ Workouts and vitals are stored locally only
- ℹ️ No cloud sync or AI coach integration
- ⚠️ Startup logs: "Backend sync DISABLED: BACKEND_WRITE_KEY not provided"

**What happens with it**:
- ✅ App syncs data to Firebase on app open and hourly in background
- ✅ Read-only API available for AI fitness coach (Arjun)
- ✅ Data accessible via: https://asia-south1-fathom-fitness-os.cloudfunctions.net/api/api/v1

**See**: `docs/backend.md` for complete backend setup

---

### 4. Release Keystore Secrets (Optional)

**Purpose**: Sign release APKs for production distribution.

**What happens without them**: 
- ⚠️ CI uses debug signing with a warning
- ✅ OK for testing, but NOT for production

Required keystore secrets (all 4 needed together):
- `ANDROID_KEYSTORE_BASE64`: Base64-encoded keystore file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias (e.g., `upload`)
- `ANDROID_KEY_PASSWORD`: Key password

**How to generate**:
See `docs/app-distribution.md` section "Release Keystore Setup"

---

## ✅ Verification Checklist

After adding secrets:

1. **Trigger CI Build**:
   - Go to: https://github.com/jalakamkiran/fitness_os/actions/workflows/app-distribution.yml
   - Click: **Run workflow** → **Run workflow**
   
2. **Check Build Logs**:
   - Look for: `✅ Created .env file (DSN: XX chars)`
   - Look for: `✅ Built release APK: com.example.fitness_os@0.1.0+<build>`
   
3. **Install APK**:
   - Check email: `jalakam.kiran@gmail.com`
   - Open Firebase App Distribution link
   - Install APK on Pixel 8a
   
4. **Test Sync**:
   - Pair with Huawei Watch GT5 Pro
   - Trigger sync
   - If sync fails, tap "Copy details" button
   - Paste error details to Slack/email
   
5. **Verify Sentry**:
   - Go to: https://sentry.io/organizations/kiran-sai/projects/fathom/
   - Check for events with release: `com.example.fitness_os@0.1.0+<build>`
   - Check for breadcrumbs on sync operations

---

## 🆘 Troubleshooting

### "SENTRY_DSN secret is required but not set"
- Add the secret in GitHub Settings → Secrets
- DSN format must be: `https://<key>@o<org-id>.ingest.sentry.io/<project-id>`
- Get it from Sentry project settings

### "Firebase service account error"
- Check that JSON is valid (paste entire file, not just part)
- Verify service account has `Firebase App Distribution Admin` role
- Verify app ID matches: `1:842234944328:android:3dc4d51ae03b539827f17d`

### "Sync still fails after adding SENTRY_DSN"
- The DSN fix only enables observability, not sync itself
- Tap "Copy details" button on sync failure
- Share error details for diagnosis
- Check if `BACKEND_WRITE_KEY` is needed

### "No Sentry events showing up"
- Wait 2-3 minutes after app launch (Sentry batches events)
- Check Sentry filters: release should be `com.example.fitness_os@0.1.0+<build>`
- Check device has internet connectivity
- Try triggering a test crash: shake device → report bug

---

## 📚 Additional Documentation

- Full CI/CD setup: `docs/app-distribution.md`
- Sentry configuration: `docs/sentry-setup.md`
- Badminton data research: `docs/badminton-data.md`

---

**Questions?** Contact: Kiran (@jalakamkiran) or see PR #20

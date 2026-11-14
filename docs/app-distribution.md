# Firebase App Distribution Setup

This guide explains how to set up Firebase App Distribution for OTA (over-the-air) APK installs without a USB cable.

## Overview

The GitHub Actions workflow automatically builds and distributes **release APKs** to testers via Firebase App Distribution when code is pushed to:
- `main` branch
- `cursor/badminton-type-mapping-e9d5` branch (PR #20)
- Manual workflow trigger (`workflow_dispatch`)

## Required GitHub Secrets

**Critical**: Add these secrets first or the CI build will fail.

Navigate to: https://github.com/jalakamkiran/fitness_os/settings/secrets/actions

### 1. `SENTRY_DSN` (REQUIRED)

**Purpose**: Crash reporting and sync failure observability.

- **Get from**: Sentry project → Settings → Client Keys (DSN)
- **Format**: `https://<key>@o<org-id>.ingest.sentry.io/<project-id>`
- **Why required**: Without this, the app has NO crash reporting and sync failures are invisible. The CI build will FAIL if this is missing.

Example:
```
SENTRY_DSN=https://abc123@o123456.ingest.sentry.io/789012
```

### 2. `FIREBASE_SERVICE_ACCOUNT_JSON` (REQUIRED)

**Purpose**: Upload APKs to Firebase App Distribution.

- **Value**: Paste the **entire JSON content** from the service account key file
- **Format**: Full JSON (see "Create Service Account" section below)

### 3. `BACKEND_WRITE_KEY` (Optional)

**Purpose**: Sync workout data to cloud backend.

- **What happens if missing**: Workouts are only stored locally on the device
- **Format**: API key string

### 4. Release Keystore Secrets (Optional)

**Purpose**: Sign release APKs for production distribution.

**If missing**: The build will use debug signing with a warning (OK for testing, not for production).

Required keystore secrets:
- `ANDROID_KEYSTORE_BASE64`: Base64-encoded keystore file
- `ANDROID_KEYSTORE_PASSWORD`: Keystore password
- `ANDROID_KEY_ALIAS`: Key alias (e.g., `upload`)
- `ANDROID_KEY_PASSWORD`: Key password

See "Release Keystore Setup" section below for how to generate these.

## Firebase Project Setup

### Project Details

- **Firebase Project**: `fathom-fitness-os`
- **Android App ID**: `1:842234944328:android:3dc4d51ae03b539827f17d`
- **Package Name**: `com.example.fitness_os`
- **Testers**: `jalakam.kiran@gmail.com` (group: `me`)

### 1. Create Firebase Service Account

The GitHub Actions workflow needs a service account with Firebase App Distribution Admin permissions.

#### Steps:

1. **Go to Google Cloud Console**:
   - Navigate to: https://console.cloud.google.com
   - Select project: `fathom-fitness-os`

2. **Create Service Account**:
   - Go to: **IAM & Admin** → **Service Accounts**
   - Click: **+ CREATE SERVICE ACCOUNT**
   - Name: `github-actions-app-distribution`
   - Description: `GitHub Actions workflow for Firebase App Distribution`
   - Click: **CREATE AND CONTINUE**

3. **Grant Permissions**:
   - Role 1: **Firebase App Distribution Admin**
     - Search: "Firebase App Distribution Admin"
     - Select: `roles/firebaseappdistro.admin`
   - Role 2 (optional): **Firebase Admin** (if you need full access)
     - `roles/firebase.admin`
   - Click: **CONTINUE** → **DONE**

4. **Create JSON Key**:
   - Click on the newly created service account
   - Go to: **KEYS** tab
   - Click: **ADD KEY** → **Create new key**
   - Key type: **JSON**
   - Click: **CREATE**
   - Save the downloaded JSON file (never commit this!)

### 2. Add Testers to Firebase

1. **Go to Firebase Console**:
   - Navigate to: https://console.firebase.google.com
   - Select project: `fathom-fitness-os`

2. **Add Tester**:
   - Go to: **App Distribution** (left sidebar)
   - Click: **Testers & Groups** tab
   - Click: **Add testers**
   - Enter email: `jalakam.kiran@gmail.com`
   - Click: **Add**

3. **Create Tester Group** (optional):
   - Click: **New group**
   - Group name: `me`
   - Add testers: `jalakam.kiran@gmail.com`
   - Click: **Create group**

## GitHub Secrets Setup

Add the following secrets to your GitHub repository:

### Required Secrets

Navigate to: **Repository** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

#### 1. `FIREBASE_SERVICE_ACCOUNT_JSON`

- **Name**: `FIREBASE_SERVICE_ACCOUNT_JSON`
- **Value**: Paste the entire contents of the service account JSON file
- **Format**:
  ```json
  {
    "type": "service_account",
    "project_id": "fathom-fitness-os",
    "private_key_id": "...",
    "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
    "client_email": "github-actions-app-distribution@fathom-fitness-os.iam.gserviceaccount.com",
    "client_id": "...",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    ...
  }
  ```

#### 2. `SENTRY_DSN` (optional, for observability)

- **Name**: `SENTRY_DSN`
- **Value**: Your Sentry DSN (e.g., `https://abc123@o123.ingest.sentry.io/456`)
- If not provided, Sentry will be disabled in the build

#### 3. `FIREBASE_ANDROID_APP_ID` (optional)

- **Name**: `FIREBASE_ANDROID_APP_ID`
- **Value**: `1:842234944328:android:3dc4d51ae03b539827f17d`
- Default is already set in the workflow, but you can override it

### Optional Variables

For non-sensitive configuration, you can use **Variables** instead of secrets:

Navigate to: **Settings** → **Secrets and variables** → **Actions** → **Variables** tab

- `FIREBASE_ANDROID_APP_ID`: `1:842234944328:android:3dc4d51ae03b539827f17d`

## Installing Builds on Android

### 1. Install Firebase App Tester

On your Android device (Pixel):

1. **Download Firebase App Tester**:
   - Open Google Play Store
   - Search: "Firebase App Tester"
   - Install: [Firebase App Tester](https://play.google.com/store/apps/details?id=com.google.firebase.appdistribution)

2. **Sign in**:
   - Open Firebase App Tester
   - Sign in with: `jalakam.kiran@gmail.com`

### 2. Accept Invite

After the first workflow run:

1. **Check Email**:
   - Look for email from Firebase App Distribution
   - Subject: "You've been invited to test Fathom on Firebase App Distribution"

2. **Accept Invite**:
   - Open email on your device
   - Click: **Accept the invitation**
   - Or open Firebase App Tester → **Accept** the invite

### 3. Install APK

1. **Open Firebase App Tester**
2. **Find Fathom** in the app list
3. **Click Download** on the latest build
4. **Install** when prompted
5. **Open** the app

### 4. Subsequent Updates

Once installed, new builds will appear in Firebase App Tester automatically:

1. Open Firebase App Tester
2. Fathom will show "Update available"
3. Click **Download**
4. Click **Install** to update

## Triggering a Build

### Automatic Triggers

The workflow runs automatically on:

- **Push to `main`**: Production releases
- **Push to `cursor/badminton-type-mapping-e9d5`**: PR #20 testing builds
- Any commit pushed to these branches triggers a new build

### Manual Trigger

To manually trigger a build:

1. Go to: **GitHub Repository** → **Actions**
2. Select: **Firebase App Distribution** workflow
3. Click: **Run workflow**
4. Choose branch: `cursor/badminton-type-mapping-e9d5` or `main`
5. Optional: Add custom release notes
6. Click: **Run workflow**

## Build Artifacts

Each workflow run produces:

1. **Firebase App Distribution**:
   - Distributed to testers via Firebase App Tester
   - Release notes include branch, commit, and features

2. **GitHub Artifacts**:
   - Uploaded as workflow artifact: `app-debug-<run_number>-<sha>`
   - Available for 30 days
   - Download from: **Actions** → **Workflow run** → **Artifacts**

## Build Configuration

The workflow builds a **debug-signed APK** with:

- ✅ Sentry observability enabled
- ✅ Raw workout payload dumps (`SENTRY_RAW_WORKOUT_DUMP=true`)
- ✅ Badminton type 129 mapping
- ✅ Racket sport icons
- 🐛 Debug mode (debuggable, no obfuscation)

**Not included** (debug builds don't need):
- ❌ Release signing (uses debug keystore)
- ❌ ProGuard/R8 obfuscation
- ❌ App bundle (AAB) format

## Troubleshooting

### Build Fails: "SENTRY_DSN not set"

The workflow will create an empty `.env` if `SENTRY_DSN` is not provided. This is fine—Sentry will be disabled.

### Build Fails: "FIREBASE_SERVICE_ACCOUNT_JSON not set"

Add the service account JSON as a GitHub secret. See **GitHub Secrets Setup** above.

### Can't Install APK: "App not installed"

1. **Uninstall existing Fathom** if installed via different signing
2. Go to: **Settings** → **Apps** → **Fathom** → **Uninstall**
3. Try installing again from Firebase App Tester

### Firebase App Tester Shows "No apps available"

1. **Check email** for Firebase invite
2. **Accept invite** from email link
3. **Refresh** Firebase App Tester
4. **Sign in** with the correct Google account (`jalakam.kiran@gmail.com`)

### Build Succeeds but Not Visible in App Tester

1. **Check workflow logs** for upload success
2. **Verify tester email** matches Firebase invite
3. **Check Firebase Console** → App Distribution → Releases
4. Wait 1-2 minutes for Firebase to process the upload

## Monitoring Builds

### GitHub Actions

- Go to: **Repository** → **Actions** → **Firebase App Distribution**
- View: Run status, logs, artifacts
- Download: APK artifacts as fallback

### Firebase Console

- Go to: https://console.firebase.google.com
- Select: `fathom-fitness-os`
- Go to: **App Distribution** → **Releases**
- View: All distributed builds, testers, install stats

## Security Notes

1. **Never commit**:
   - ❌ Service account JSON
   - ❌ Sentry DSN
   - ❌ `.env` file

2. **Service account permissions**:
   - Limit to: Firebase App Distribution Admin only
   - Do not grant broader IAM roles

3. **GitHub secrets**:
   - Only accessible to workflow runs
   - Not exposed in logs (automatically redacted)
   - Rotate if accidentally exposed

4. **Debug builds**:
   - Use debug signing (not production keys)
   - No sensitive data in release notes
   - Testers controlled via Firebase groups

## Further Reading

- [Firebase App Distribution Docs](https://firebase.google.com/docs/app-distribution)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [wzieba/Firebase-Distribution-Github-Action](https://github.com/wzieba/Firebase-Distribution-Github-Action)

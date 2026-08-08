# Sentry owner setup (Fathom / Fitness OS)

Solo-owner crash + sync observability. Cloud SDK: **Sentry Flutter**.

## One-time project setup

1. Create a Sentry project (Flutter / Android).
2. Copy Client Keys **DSN** into local `.env` (gitignored):

```bash
cp .env.example .env
# edit .env
SENTRY_DSN=https://…@….ingest.sentry.io/…
```

3. Run profile/release with dart-defines:

```bash
flutter run --release --dart-define-from-file=.env
# or use VS Code launch configs (already wired)
```

**Do not** put `SENTRY_AUTH_TOKEN` in `.env` — `--dart-define-from-file` embeds values in the APK. Export the auth token only in shell/CI when uploading obfuscated symbols later.

## When Sentry initializes

| Build | Behavior |
|-------|----------|
| release / profile | ON if `SENTRY_DSN` is set |
| debug | OFF unless `SENTRY_FORCE=true` |

Missing DSN → app still launches; observability disabled.

## Soft sync vs crashes

| Signal | Where it appears | Issues? |
|--------|------------------|---------|
| Uncaught exception / ANR / NDK crash | Issues | Yes |
| `stuck` / `partial_batch` / `busy` / schedule rejects | Performance spans + breadcrumbs | **No** |
| Hung MethodChannel (`sync.abandoned`) | Span + breadcrumb | **No** |

Never expect soft sync outcomes as crash Issues.

## Stall playbook (Performance)

After a slow Sync / cold-open auto-sync:

1. Sentry → **Performance** → transaction name `autosync.pass`.
2. Tags: `trigger=auto|manual`, optional `window=full_history|incremental`.
3. Child spans: `sync.workouts`, `sync.vitals` — check duration + `status` tag.
4. Breadcrumbs: `link.state`, `autosync.schedule`, `sync.abandoned`.

Useful filters:

- `transaction:autosync.pass`
- `span.status:deadline_exceeded` (soft stuck / abandoned)
- breadcrumb category `sync.abandoned`

**BT sync ≠ Sentry upload** — RFCOMM must not wait on Sentry flush; events buffer offline and upload later.

## Privacy checklist

Allowed on spans/breadcrumbs: status enums, counts, durations, phase names, `trigger`, window class.

Forbidden (scrubbed + never attached by instrumentation):

- MAC / `phoneMac` / `userId`
- Auth / Gemini / secret key material
- MethodChannel `result` / `arguments` / `details` maps
- Workout / HR / sleep / segment / sample payloads
- RFCOMM hex dumps

Dart hooks: `beforeSend`, `beforeSendTransaction`, `beforeBreadcrumb` in `lib/core/observability/sentry_privacy_scrub.dart`.

**v1 note:** Kotlin `SentryAndroidOptions.beforeSend` mirror is deferred. Native-only JVM crashes may not get the same map scrub — avoid putting health payloads in native breadcrumbs; delete events in Sentry if a scrub regression appears.

## Quotas

Sentry Developer free tier is ample for solo owner sessions if soft paths stay off Issues. Lower `tracesSampleRate` later if span volume grows.

## Symbol upload (optional, later)

Only needed when enabling Dart/Android obfuscation. Current release builds are not obfuscated. When you add it:

```bash
export SENTRY_AUTH_TOKEN=…
# use sentry_dart_plugin / gradle upload — never commit the token
```

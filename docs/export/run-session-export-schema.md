# Outdoor Run session export schema (v1)

Owner-initiated dump of **one Outdoor Run** session from Run detail (“Export for AI”). **Not a backup.** Do not commit real exports or leftover bodies.

## Envelope

| Field | Meaning |
|-------|---------|
| `schemaVersion` | `1` |
| `kind` | `run_session` |
| `exportedAt` | ISO-8601 UTC |
| `sensitivityNotes` | Non-anonymized session health; shared copies not revoked by Forget |
| `consistencyClass` | `best_effort` (blocked during Sync / Forget / app or food export; mid-assemble recheck) |
| `knownOmissions` | Always includes secrets / MAC / account / bind tokens / structured GPS series. Opaque leftover bodies are **not** claimed omitted. |
| `sessionKey` | Workout number, start, type (+ `observedType` if present), typeLabel, distance, duration — matches confirm identity |
| `confirmIdentity` | Same human-readable lines shown in the confirm dialog |
| `workout` | Present decoded lean prefs fields (`WorkoutSummary.toJson`) |
| `countHints` | `dataCount` / `paceCount` / `sampleCount` when present |
| `honesty` | Enrichment + leftovers / dataPages / paceBlocks stamps |
| `leftovers` | `refs` (id+len), optional on-device `bodies` (base64), `sideFilePresent` |
| `dataPages` / `paceBlocks` | Honesty, page meta, item id+len, `noPagesHint` / `partial` flags — **not** GPS |

Cache: `{temp}/run_session_exports/` (peer to app-data `exports/` and day-food caches).

## Redaction matrix (R13)

| Always omit | Notes |
|-------------|--------|
| Huawei secrets / native auth material | Never read into dump |
| `remembered_mac` / MAC-shaped strings | Scrubbed + self-check |
| Account id / 17-digit `userId` shapes | Scrubbed + self-check |
| Bind / auth tokens (`authKey`, `bindToken`, …) | Forbidden keys |
| Gemini API key | Scrubbed + self-check |
| GPS / location **series** (keyed fields) | Forbidden keys this cut (`gps_location_series` in `knownOmissions`) |

| May include (on-device share only) | Notes |
|-----------------------------------|--------|
| Present decoded Totals / session scalars | From lean workout JSON |
| Leftover TLV **bodies** | Session dump only — never commit. Opaque bytes are not GPS-scrubbed; confirm dialog discloses that undecoded leftovers may contain location-related wire data until catalogued. |
| Sample / pace **id+len** + honesty / no-pages flags | Bodies not required for honesty |
| Count hints | From prefs |

## Busy / Forget

- Session export blocks while Sync, Forget, app-data export, or day-food export is in flight (and mid-assemble recheck).
- Forget blocks while session `exportInFlight`.
- Forget wipe clears `RunSessionStore` dirs + prunes `run_session_exports/`; pairing **directory-empty-verifies** leftovers / data_pages / pace_blocks + export cache and asserts lean `workouts_json` cleared.

## App-data export contrast

Full [app-data-export-schema.md](./app-data-export-schema.md) inventories the same side-file dirs as **IDs/lengths only** under `meta.sideFileInventory.runSessionSideFiles` — **never bodies**.

# App data export schema (v1)

Owner-initiated diagnostic dump from Reasoner settings. **Not a backup.** Do not commit real exports.

## Envelope

| Field | Meaning |
|-------|---------|
| `schemaVersion` | `1` |
| `exportedAt` | ISO-8601 UTC |
| `sensitivityNotes` | Health biometrics; not anonymized |
| `consistencyClass` | `best_effort` (blocked during sync/Forget; re-check before write) |
| `knownOmissions` | Streams/keys absent after assemble (dynamic). Always includes `remembered_mac`, `gemini_api_key`, `native_huawei_secrets`. Optional analysis fields (`swim_sample_data_pages`, `swim_pace_blocks`, coach/diagnosis snapshots, daily activity calories) appear here only when not already present on device — export does **not** start persisting them. |
| `meta` | Allowlisted prefs + side-file inventory (orphan canonical swim **IDs only**, no bodies; run leftover/data/pace **IDs/lengths only**) |
| `workouts` | `{ parseStatus, items }` — raw prefs JSON items (preserves lean refs if present; never leftover bodies) |
| `canonicalSwim` | On-disk non-orphan swim files with `parseStatus` |
| `vitals` | Sleep prefs, daily HR summaries, HR series side-files |
| `optionalPresent` | Present only when optional coach/diagnosis/day-calorie prefs already exist |

`parseStatus`: `ok` | `corrupt` | `absent`.

`meta.sideFileInventory.runSessionSideFiles`: inventories `workouts/totals_leftovers`, `workouts/data_pages`, and `workouts/pace_blocks` as workout-number keyed **id+len** (and page indexes) — **never** `bodyBase64` / binary bodies. Target-session AI dump is a separate schema: [run-session-export-schema.md](./run-session-export-schema.md).

## Redaction

Omitted: Gemini API key, remembered MAC, `userId` / MAC-shaped strings, native Huawei secrets (never read). `rememberedName` may remain (nickname PII) — see `sensitivityNotes`.

## Offline analysis notes

- Home calories = Σ today's workout `calories` (not FitnessTotals day energy).
- Lap `rest` is not in wire/persisted segment models.
- Sample/pace streams are only in the dump if already stored in prefs JSON.
- Diagnosis/recs are recomputed offline unless an optional prefs snapshot was already present.
- Orphan `workouts/canonical_swim/` files after Forget are inventory IDs only until a separate wipe fix.

# Day-Food Export Schema

## Overview

Owner-initiated export of a single day's meal logs as a shareable ZIP package for external QA (e.g., ChatGPT calorie estimation).

**Schema version:** 1  
**Format:** ZIP containing `manifest.json` + `images/{mealId}.jpg` copies  
**Cache location:** `{temp}/day_food_exports/` (peer to app-data exports, NOT nested under `exports/`)

---

## Security & Privacy

- **Consent:** Blocking confirm dialog before assemble (sensitive health data warning).
- **Path guard:** Only share from export cache; SoT meal paths never exposed.
- **Prune ≠ revoke:** Cache prune deletes local copies but does not revoke already-shared files (recipient retention).
- **EXIF stripped:** Meal photos are EXIF-stripped at capture; export copies remain clean.
- **No secrets:** No API keys or device identifiers in manifest or ZIP.

---

## manifest.json Schema

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-09-06T20:15:30.123Z",
  "dayKey": "2026-09-06",
  "meals": [
    {
      "id": "meal-uuid",
      "capturedAtMs": 1725651330000,
      "slot": "lunch",
      "name": "Chicken salad",
      "note": "Light dressing",
      "kcal": 450.0,
      "photoRelPath": "images/meal-uuid.jpg",
      "photoStatus": "present",
      "source": "manual"
    }
  ]
}
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schemaVersion` | int | Yes | Schema version (currently 1) |
| `exportedAt` | string | Yes | ISO 8601 UTC timestamp of export |
| `dayKey` | string | Yes | Local calendar day (YYYY-MM-DD) |
| `meals` | array | Yes | List of meal records for this day |

### Meal Record Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique meal identifier |
| `capturedAtMs` | int | Yes | Unix milliseconds when meal was logged |
| `slot` | string | No | Optional meal slot: "breakfast", "lunch", "dinner", "snack" |
| `name` | string | No | Optional meal name |
| `note` | string | No | Optional meal note |
| `kcal` | number | No | Manual calorie entry (null if not provided) |
| `photoRelPath` | string | Yes | Relative path within ZIP to meal image |
| `photoStatus` | string | Yes | Image availability: "present", "absent", "corrupt" |
| `source` | string | Yes | Data source: "manual" (v0), "ai_confirmed" (v0.5 future) |

### photoStatus Values

- **`present`**: Image bytes included in ZIP at `photoRelPath`
- **`absent`**: Meal photo file missing from SoT; no image in ZIP
- **`corrupt`**: Photo file exists but could not be read; no image in ZIP

---

## ZIP Structure

```
food_day_2026-09-06_20260906_201530.zip
├── manifest.json
└── images/
    ├── meal-abc123.jpg
    ├── meal-def456.jpg
    └── meal-ghi789.jpg
```

- Missing/corrupt images omitted from `images/`; `photoStatus` reflects absence.
- Empty kcal fields omitted from manifest (not serialized as `null`).
- No README or additional metadata files in v0 (external QA only).

---

## Export Lifecycle

1. **User selects day** → Export CTA (disabled if zero meals).
2. **User confirms** → Blocking dialog (sensitive data + prune ≠ revoke warning).
3. **Assemble** → `manifest.json` + image copies under cache.
4. **Path guard** → Refuse share if path escapes cache.
5. **Size warn** → Soft warning at ~25MB (optional continue).
6. **Share sheet** → OS share to Files, ChatGPT, etc.
7. **Prune** → Delete prior day-food ZIPs from cache after successful share.
8. **Forget wipe** → Prune entire `day_food_exports/` cache.

---

## Version Notes

- **v0:** Manual kcal only; `source: "manual"`; no AI fields.
- **v0.5 (future):** Add `aiSuggestionKcal` vs `confirmedKcal` distinction; `source: "ai_confirmed"` when estimate was confirmed.
- **Schema evolution:** Bump `schemaVersion` on breaking changes; maintain backward-compatible readers where possible.

---

## Usage Example (ChatGPT QA)

User exports a day → shares ZIP to ChatGPT → prompts:

> "Estimate total calories for this day from the meal photos. The manifest has my manual entries if provided."

ChatGPT reads `manifest.json`, views `images/`, returns approximate kcal totals. User manually enters confirmed values back into app (no automatic write-back in v0).

---

## Related

- App-data export: `docs/export/app-data-export-schema.md`
- Meal SoT: `food/meals/{dayKey}/{mealId}.jpg` under app-support
- Export cache prune: Composed into Forget wipe via `diagnostics_di.dart`

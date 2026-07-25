# Fitness OS Architecture (living)

**Goal this horizon (5 weeks):** Swimming Bible v0 in-app — enrichment → metrics → diagnosis → recs → LLM coach shell. Direct LPv2 only (Health Kit dropped). Owner 25m probe = W0 gate. Roadmap: `docs/plans/2026-07-23-001-product-roadmap-swim-bible-v0.md`.

## System context

```mermaid
flowchart LR
  watch[Huawei_GT5]
  native[Android_Huawei_stack]
  flutter[Flutter_app]
  local[(Local_persist)]
  bible[Swimming_Bible_Notion]
  chatgpt[ChatGPT_Product_Head]
  watch -->|RFCOMM_LPv2| native
  native -->|MethodChannel| flutter
  flutter --> local
  bible -.->|evaluator_gap_map| chatgpt
  flutter -.->|STATUS_links| bible
```

## Sync data planes

```mermaid
flowchart TD
  gateA[GateA_pair_session]
  totals[GateB_Count_Totals]
  enrich[Enrichment_Data_Pace_Swim]
  activity[Activity_sleep_daily_HR]
  series[HR_minute_series_sidefile]
  ui[Basic_UI_charts]
  gateA --> totals
  totals -->|segmentsCount_gt_0| enrich
  totals -->|dataCount_gt_0| enrich
  enrich -->|0x0e_then_0x0a_then_0x0c| ui
  gateA --> activity
  activity --> series
  totals --> ui
  enrich --> ui
  series --> ui
```

## Module map

| Layer | Path | Role |
|-------|------|------|
| Wire framing | `android/.../HuaweiFraming.kt` | LPv2 TLV |
| Workout Sync | `android/.../HuaweiWorkoutSync.kt` | Count→Totals→enrichment (0x0e/0x0a/0x0c) |
| Fitness Sync | `android/.../HuaweiFitnessDataSync.kt` | Sleep / HR / enable |
| Session | `android/.../HuaweiSession.kt` | Auth + sync entry |
| Flutter bridge | `lib/core/huawei/` | Link + DTOs |
| Workouts UI | `lib/features/workout_history/` | List + detail |
| Vitals UI | `lib/features/vitals/` | Enable + HR/sleep |
| HR series side-files | `{applicationSupport}/vitals/hr_series/{dayKey}.json` | Per-minute HR (no-backup); day summaries stay in prefs |
| Status | `docs/status/` | Monitor progress |

## Rules

- No AGPL paste from Gadgetbridge — oracle only.
- Enrichment parsers may ship behind count gates; do not claim observed until owner capture.
- Prefer local no-backup files for series; SharedPreferences for summaries.

## UI navigation (basic)

```mermaid
flowchart TD
  home[Home / Pairing tab]
  workouts[Workout list /workout_history]
  detail[Workout detail /workout_detail]
  vitals[Vitals tab]
  hrChart[Latest-day HR sparkline]
  home -->|Workouts CTA| workouts
  workouts -->|tap row| detail
  vitals -->|loadDailyHrSeries| hrChart
```

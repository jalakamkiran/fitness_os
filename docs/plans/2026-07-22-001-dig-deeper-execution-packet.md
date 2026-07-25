# Execution packet — Dig deeper (2026-07-22)

## Acceptance (before owner swim)
1. Totals map includes optional enrichment fields + count hints (`dataCount`,`paceCount`,`segmentsCount`) when present.
2. Synthetic Kotlin tests for enrichment TLV parse (HR peaks / swim tags / counts) without device.
3. Daily HR minute samples persisted locally; day summary still drives list UI.
4. Workout detail screen shows summary + enrichment/debug fields (basic feel).
5. Vitals shows latest day + simple HR sparkline/chart from series if present.
6. `docs/architecture/` diagrams current; Notion status page links them.
7. Owner checklist for 25m pool probe ready.

## File touch list (preferred)
- `HuaweiWorkoutSync.kt` — parse enrichment tags; attach count hints to totals maps
- `HuaweiWorkoutSyncTest.kt` — synthetic fixtures
- `HuaweiFitnessDataSync.kt` / vitals repo — series side-file
- `huawei_link.dart` `WorkoutSummary` — optional fields
- `workout_history` — detail route/UI
- `vitals` — chart
- `pubspec.yaml` — fl_chart if needed
- docs as above

## Non-goals
Full Bible depth for run/gym; GPS FileDownload productization; polish design system.

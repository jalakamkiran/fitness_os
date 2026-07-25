# Execution packet — W1 Canonical swim + P0 metrics (2026-07-23)

**Verdict in:** W0 owner probe **PASS** (Totals match watch; segments parse; type/pool length fixed). Lap row count may be &lt; `laps` (PARTIAL honesty for length coverage).

## Acceptance (close today)
1. Canonical swim session model: workout number, pool length m, totals, ordered laps, optional in-workout HR flag.
2. Persist canonical swim locally (side-file under app support; summaries stay in `workouts_json`).
3. P0 metrics computed (pure Dart): avg pace, lap pace/splits, strokes, SWOLF, stroke rate (derived OK).
4. `hrCoverage`: `present` | `partial` | `absent` — no fake in-workout HR.
5. Fixture unit tests from #11-shaped laps (no device, no AGPL).
6. Workout detail shows a **P0 metrics** block (basic, not W2 polish).
7. AUTO_DRIVE + roadmap marked W0 PASS / W1 done.

## File touch list
- `lib/features/workout_history/domain/swim_session.dart` — canonical + P0
- `lib/features/workout_history/domain/swim_p0_metrics.dart` — calculators
- `lib/features/workout_history/data/...` — build + persist on sync merge
- `lib/features/device_pairing/domain/gate_a_prefs.dart` — path keys
- `workout_detail_screen.dart` — P0 block
- `test/features/workout_history/swim_p0_metrics_test.dart`
- docs: this packet, `AUTO_DRIVE.md`, roadmap status row

## Non-goals (W2+)
Lap decay charts, confidence tags, multi-session trends, coach, GPS, run/gym.

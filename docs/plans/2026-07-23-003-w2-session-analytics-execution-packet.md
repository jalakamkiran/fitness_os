# Execution packet — W2 Session analytics UI (2026-07-23)

**Parallel with:** owner controlled freestyle probe (length vs interval semantics). W2 treats rows as **intervals**, not proven lengths.

## Acceptance
1. Pure Dart session analytics from P0 laps: pace decay, pace consistency, SWOLF trend / per-interval efficiency.
2. Each claim has confidence **High | Med | Low** + short evidence note.
3. HR zone/drift section **only** when `hrCoverage == present`; otherwise omitted (no fake physiology).
4. Workout detail shows **Session analytics** block (basic feel, interval glossary).
5. Fixture tests (#11-shaped + clean 8-interval set).
6. AUTO_DRIVE / roadmap → W2 done; next W3.

## Non-goals
Diagnosis rules (W3), recommendations/coach (W4), chasing missing lengths, chart polish.

# SwimSessionInsight contract (R21)

Short non-goals note for a future Programs (or other) consumer. **Not** a dual-consumer API design.

## Source of truth today

- Assembler: `lib/features/workout_history/domain/swim_session_insight.dart`
- Builder: `buildSwimSessionInsight(...)`
- Presentation owns invent-guard filtering, HR lock peel, prefs, and orientation
- Swim Bible compute (`canonical_swim_session`, P0, invent-guard, diagnoses, allow-listed recs) remains the metric SoT

## Athlete fields

| Field | Honesty |
| --- | --- |
| `story` | Always present; coverage-honest when tippless |
| `storyDiagnosisId` / `primaryTip.sourceDiagnosisId` | Same winning session diagnosis when tip exists |
| `chips` | Focus-relative vs prior comparable; omit when thin — never earliest→latest `buildSwimTrends` deltas |
| `primaryTip` | Session diagnoses only; coverage-only IDs never win; null → empty-tip escape |
| `kpis` | Distance / duration (swim·rest only when `0 < moving ≤ duration`) / pace / SWOLF; HR only from passed-in lock |
| `secondaryFindings` | Collapsed “More findings”; no metric-ID footers / sticker farms |

## Non-goals (this cut)

- No Programs UI, plan chips, or “add to plan” CTAs
- No second Programs-facing DTO or versioned API surface
- No quality / readiness / 0–100 scores
- Dig-deeper prefs and landscape orientation never enter the builder
- Open-water coaching narratives beyond shared-shell omit may defer

Programs may later **read** this assembler’s output; do not invent a parallel insight pipeline.

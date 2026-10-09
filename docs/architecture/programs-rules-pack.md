# Programs Rules Pack (pool swim)

**Version:** `1.0.0` (stamped on `Program.rulesPackVersion`)  
**Code:** `lib/features/programs/domain/rules_pack/`  
**Consumer:** `ProgramPlanner` (`lib/features/programs/domain/program_planner.dart`)

## What this is

Fathom-owned, deterministic planning data for pool-only Programs: capacity rung formulas, weekly session roles, warm-up / main / cool-down patterns, proof slip rules, and pace-vs-horizon feasibility bounds. Not a licensed workout feed; patterns are authored in Fathom notation (no vendor copy).

## Provenance

Distilled from research pack:

- `docs/brainstorms/research/2026-10-09-swim-training-algorithms-datasets.md` §6–7  
  (capacity rungs +15–25% default +20%, session roles by `n`, WU/main/CD, proof slip, CSS gain 0.3–0.5 s/100/wk)

Supporting source maps (ingest vs distill): USMS public articles, Swim Smooth CSS guidance, Open Swim formats / community practice — see sibling research notes under `docs/brainstorms/research/`.

Evidence grades in research are planning heuristics **[D]** unless marked otherwise; dogfood calibration (1000→1200 m) locks the default rung.

## Pack layout

| File | Contents |
|------|----------|
| `rules_pack.dart` | `rulesPackVersion`, meta, exports |
| `formulas.dart` | Rung step, volume growth, WU/CD clamps, slip days, helpers |
| `patterns.dart` | Curated set pattern IDs (WU/AE/CS/TK/RC/PRF/CD) |

JSON/YAML asset export is optional later; v1 keeps constants in Dart for unit-testability without asset loading.

## Versioning

Bump `rulesPackVersion` (semver) when formulas or pattern IDs change in a way that would alter generated plans. Existing saved programs keep their stamped version; regeneration uses the current pack.

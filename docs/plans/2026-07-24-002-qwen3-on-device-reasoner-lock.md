# On-device reasoner lock — Qwen3 (2026-07-24)

## Locked
- **Model:** Qwen3 0.6B (`litert-community/Qwen3-0.6B`, `.litertlm`, ~586MB)
- **Runtime:** `flutter_gemma` + `flutter_gemma_litertlm` (needs **Flutter ≥ 3.44** — native assets on stable)
- **Role:** Reasoning over diagnoses → prioritize allow-listed recs (not coach voice)
- **Guard:** `orderedRecIds` ⊆ allow-list; invent dropped
- **Fallback:** Deterministic offline reasoner (always works without download)

## Non-goals
Gemini API dependency, Gemma voice models, fine-tuning FunctionGemma (yet).

## Owner flow
1. Workouts → psychology icon → Download Qwen3 (~586MB)
2. Open swim → **Run reasoner** (Qwen3 if installed, else offline)
3. Recs reorder + summary; invent-guard enforced in code

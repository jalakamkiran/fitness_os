# Execution packet — W4 Recs + Gemini coach (2026-07-24)

## Acceptance
1. Deterministic allow-listed recommendations from W3 diagnosis IDs.
2. Owner can enter / clear **Gemini API key** in-app (device-local prefs; never git).
3. Gemini coach call: explain + prioritize **only** IDs from the payload; reject unknown IDs.
4. Workout detail shows Recs always; Coach prose when key present (fallback message if missing/fail).
5. Trace line visible: diagnosis → rec → metrics.
6. Unit tests for rec mapping + coach JSON guard; no live API in CI.
7. AUTO_DRIVE / roadmap → W4 done.

## Non-goals
Fine-tune own model, multi-provider UI, cloud key sync, Bible full text dump.

# Owner probe checklist — 25m pool swim (go/no-go)

**When:** Tomorrow (owner return)  
**Device:** Huawei GT5-A07 + Fitness OS companion  
**Pool:** **25 m**

## Before swim
1. Open Fitness OS → ensure watch connected (`session_ready`).
2. Vitals → **Enable auto-tracking** → confirm TruSleep / auto-HR / auto-SpO2 outcomes.
3. Note firmware string if shown; leave Sync idle.

## Swim seed (must)
1. Start **Pool swim** on watch (≥4 lengths / ~2–4+ min preferred).
2. Complete workout; wait for watch to finish saving.
3. Companion → Workout Sync.
4. Open workout detail — capture (notes only, no GPS payloads in git):
   - `type`, duration, calories, distance
   - `dataCount`, `paceCount`, `segmentsCount`
   - any swim tags / SWOLF / strokes / laps shown
5. If empty enrichment: one reconnect + Sync retry (do not Forget device).

## After
1. Vitals Sync (HR/sleep if overnight armed).
2. Paste outcomes into ChatGPT Huawei Watch project thread + update `docs/status/AUTO_DRIVE.md`.
3. Decision:
   - **GO dig-deeper** if segments/swim tags or Data counts appear
   - **PIVOT analytics scope** if only Totals scalars after honest budget
   - **KEEP summary companion** still valuable either way

## Privacy
Log tag ids + lengths + presence. No raw tracks / full series in git.

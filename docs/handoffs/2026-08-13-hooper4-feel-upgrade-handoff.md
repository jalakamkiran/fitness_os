# Handoff: Hooper-4 morning wellness (feel upgrade)

**Date:** 2026-08-13  
**Status:** Ready to implement — product decisions locked in brainstorm  
**Requirements:** `docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md`  
**Implement on branch:** `feat/recovery-sleep-detail` (sleep + feel-on-wake live here)  
**Do not implement on:** `feat/vitals-auto-tracking-enable` (no feel survey on that line)

Paste this doc into a new chat to continue. Prefer `/ce-plan` then `/ce-work`, or implement directly if the cut stays small.

---

## Goal / done means

Upgrade Recovery · Sleep **feel-on-wake** from one global emoji to a **four-item Hooper-style wellness check**:

1. Sleep quality  
2. Fatigue  
3. Muscle soreness (DOMS)  
4. Stress  

Persist once per overnight sleep session. Owner completes in ~10–15s. No workout-intensity coaching. No claiming the watch measured soreness.

**Exit:** overnight session → four answers saved under that session key → survey hidden; tests cover once-per-key, overnight-only, and migration from legacy single-string feel.

---

## Why (evidence, short)

- Saw et al.: subjective wellness often tracks training stress better than objective markers; subjective ≠ objective is useful, not a bug.  
- Hooper & Mackinnon wellness / Hooper Index: daily **sleep quality, stress, fatigue, DOMS** on a short ordinal scale is the practical athlete battery.  
- GT5 **cannot** measure DOMS — soreness must stay user-entered.  
- Broader recovery analytics (overnight HR/HRV/RR/SpO₂ POC, baselines, P4 composite, training join) run **in parallel / later** — out of this handoff.

---

## Product locks (do not reopen unless owner says so)

| Decision | Lock |
|----------|------|
| Dimensions | Sleep quality, fatigue, soreness, stress only (no motivation v1) |
| Scale | Prefer **1–7** Hooper-style with clear labels; same scale for all four |
| Trigger | Overnight only (`sleepCrossesLocalMidnight`); same session as today |
| Completeness | All four required before survey is “answered” |
| Coaching | **No** hard / easy / rest suggestion |
| Watch DOMS | Never derive or imply |
| Parallel work | Physio capture POC is a **separate** agent/track |

---

## Current code (SoT on `feat/recovery-sleep-detail`)

| Area | Path / behavior |
|------|------------------|
| UI survey | `lib/features/vitals/presentation/view/sleep_tab_screen.dart` — `_FeelOnWakeSurvey`, single question “How do you feel waking up?”, keys `awful`…`great` |
| Show rules | Overnight session, `_feelAnswer == null`, prefer today’s overnight else most recent unanswered overnight |
| Repo API | `VitalsRepository.loadFeelOnWake` / `saveFeelOnWake(session, String answer)` |
| Persist | Prefs key `GateAPrefs.sleepFeelOnWakeJson` → JSON map `mergeKey → string` |
| Once-per-key | `saveFeelOnWake` no-ops if key already present |
| SoT migration | `_migrateFeelOnWake` rekeys onto file-window mergeKeys on TruSleep SoT flip — **must keep working** for new payload |
| Forget | Removes `sleepFeelOnWakeJson` with other sleep wipe |
| Tests | `test/features/vitals/vitals_repository_test.dart` (save once); fakes in sleep_tab / recovery_tab / detail / home tests |

**Legacy shape today:**

```json
{ "<mergeKey>": "good" }
```

**Target shape (recommended):**

```json
{
  "<mergeKey>": {
    "sleepQuality": 3,
    "fatigue": 4,
    "soreness": 5,
    "stress": 2,
    "answeredAt": "<iso8601 optional>",
    "schema": 2
  }
}
```

Keep loaders tolerant of legacy string values (treat as incomplete for Hooper-4 → re-prompt, **or** map once into a deprecated `overall` field and still require the four — pick in plan; prefer **re-prompt for full Hooper-4** so baselines stay clean).

---

## Implementation guidance

1. **Domain model** — Introduce a small immutable `MorningWellness` (or similar) with the four ints + helpers `isComplete`. Do not leave parsing in the widget forever.  
2. **Repository** — Replace or overload feel APIs:
   - `Future<MorningWellness?> loadMorningWellness(session)`
   - `Future<void> saveMorningWellness(session, MorningWellness)`  
   Keep thin deprecated wrappers only if many fakes break — update fakes instead when cheaper.  
3. **UI** — Multi-step or single card with four rows; one tap per dimension; progress “2/4”; submit/persist when complete (atomic save of full object is simplest for AE2). Match existing Recovery / blueprint_ui card language; emoji OK inside prompts only (existing pattern).  
4. **Copy** — Neutral athlete language. Examples: “Sleep quality”, “Fatigue”, “Muscle soreness”, “Stress”. Avoid clinical / diagnostic wording.  
5. **Migration** — Update `_migrateFeelOnWake` to move **objects** (and legacy strings) onto new mergeKeys with longest-overlap rules unchanged.  
6. **Tests** — Repo: save complete set once; reject/ignore partial if atomic; migrate map; forget clears. UI: survey shows for unanswered overnight; hides after complete; naps skipped. Update all `VitalsRepository` fakes.  
7. **Export (if touched)** — If app data export includes feel JSON, export the new schema without breaking readers silently — document in export notes if that file is in scope on the branch.

---

## Out of scope (explicit)

- Enabling / parsing overnight HR, HRV, RR, SpO₂ from GT5  
- Baseline engine (7/14/28-day bands)  
- P4 Good / Moderate / Caution composite  
- Training-load → recovery join / intensity suggestions  
- Collapsing to one-tap after 30 days  
- Changing TruSleep file SoT timing / stage attach (separate handoff if still open)

---

## Suggested agent prompt

```text
Read docs/handoffs/2026-08-13-hooper4-feel-upgrade-handoff.md
and docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md.

Work on branch feat/recovery-sleep-detail (feel-on-wake lives there).
Replace single emoji feel-on-wake with Hooper-4: sleep quality, fatigue,
soreness, stress (1–7), once per overnight mergeKey, atomic complete save,
migrate legacy string feel + TruSleep rekey path. No intensity coaching,
no watch-derived DOMS. Update repo/UI/tests/fakes. Commit only if I ask.
```

---

## Related context (broader recovery — not this cut)

Brainstorm closed after locking parallel tracks:

1. **This cut** — Hooper-4 feel upgrade  
2. **Parallel** — GT5 physio capture POC (HR, HRV, RR, SpO₂ availability matrix)  
3. **Later** — provisional baselines (~7 nights early / ~28 mature), P4 state+explanation only (no intensity), P5 training join  

External PRD reference (not binding for this handoff): owner Downloads `Fathom_GT5_Recovery_Analytics_PRD.md`. Prior sleep IA: `docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md` (R15 single-emoji — superseded by Hooper-4 for survey shape).

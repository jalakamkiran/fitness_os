# Handoff: Overnight sleep session coalesce (2026-10-09)

## What shipped

Hybrid overnight SoT on `fix/overnight-sleep-session-coalesce`:

1. **Micro-merge ≤3m** retained (Aug 11 Health fidelity).
2. **Scientific SEQUENCE mains** (`sleepScore > 0`) define overnight bounds at `fallAsleep→wakeup` (else begin→end); overlapping interval fragments are removed (no glue-then-shrink).
3. **Nocturnal coalesce ≤90m** runs only on leftover intervals / days without scientific SEQUENCE (same Huawei sleep-day).
4. **Classifier** uses `SleepDay` kind (overnight vs nap), not calendar midnight-crossing — same-day nights (e.g. 01:36→08:11) count as overnight.
5. **History** shows `Awake Xm` from stages when awake > 0; presentation coalesce covers stale fragmented prefs until next Sync.
6. **activitySyncImplVersion → 3** forces one wide re-pull so SoT rewrite converges.

## What changed vs Aug 11 / Aug 12

| Prior | Now |
|-------|-----|
| Timing SoT = gap-merge ≤3m only | ≤3m micro + SEQUENCE-first main + ≤90m nocturnal leftovers |
| Label = `sleepCrossesLocalMidnight` | `SleepDay.isMainNightSleep` / `kindLabel` |
| SEQUENCE attaches enrich/stages to interval windows | Scientific SEQUENCE *defines* main window when present |

Stub SEQUENCE (`score=0`) still must not wipe prior detail. Afternoon / non-nocturnal naps stay on ≤3m only.

## Manual verify (Pixel + GT5)

1. Sync from Recovery · Sleep.
2. Sleep history · Oct 2026: nights 7/8/9 show **one overnight** each (not nap fragments).
3. Oct 9 row: score (e.g. 74) and **Awake** when stages present.
4. Today hero: primary = sleep-day overnight; afternoon nap does not replace it.
5. Feel-on-wake still eligible for same-calendar-day overnight mains.

## Deferred

- Home day-total / napsHint UX
- History month filter keyed purely by sleep-day id
- Persist SEQUENCE `stageMinutes` on enrich JSON for score-path awake without stage load

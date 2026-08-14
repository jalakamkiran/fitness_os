# Swim stroke style capability check (GT5-A07)

**When:** Tonight / overnight force Sync (no new swim required)  
**Device:** Huawei GT5-A07 + Fitness OS companion  
**Goal:** Prove pool-swim segments carry per-lap stroke style via inspectable logs.  
**Build:** **debug** only — Flutter `FosHuaweiLog` is silent in profile/release (`kDebugMode`).

Pass / Fail / Blocked is **manual** (this runbook’s Verdict section). Sync UI success is **not** Pass. Style UI stays gated until a recorded Pass (or explicit owner proceed-despite-partial).

---

## Before Sync

1. Install / run a **debug** build (not profile/release).
2. Ensure Gate A / watch connected (`session_ready`).
3. Optional safety: Coach Settings → export app data JSON (snapshot before replace-by-number merge).
4. Open logcat:

```bash
adb logcat -s flutter FOS_HUAWEI
```

Filter for `swim-style` / `swim-style-outcome` / `FOS_HUAWEI`.

---

## Force full-history Sync

1. Companion → **Workouts** → **Sync all history**  
   (Home Sync may be hidden after a prior successful sync — use Workouts.)
2. Parser version bump (v3) forces one full-history window so the existing Medley / older pool workout is in range.
3. Wait for Sync to finish.

### If Sync fails (busy / stuck / partial_batch / not ready)

- Log line shape: `swim-style-outcome status=sync_not_ok syncStatus=…`
- This is a **Sync failure**, not capability Blocked.
- One reconnect + Sync retry. **Do not Forget** the device.
- Stop if still failing; do not treat toast success from a later empty window as Pass.

### If Sync ok

Look for capability lines on **incoming** swims only:

| Outcome | Log signals |
|---------|-------------|
| Styles present | One `swim-style number=… startTime=… lap=… style=… label=…` per lap, then `swim-style-outcome … status=styles_logged laps=N` |
| Empty / no segments | `swim-style-outcome … status=blocked reason=segments_empty` or `segments_count_zero` |
| Segments but no styles | `swim-style-outcome … status=blocked reason=all_styles_null` |

Labels: 1 Breaststroke, 2 Freestyle, 3 Butterfly, 4 Backstroke, 5 Medley; unknown → `Stroke N`; null → `null`.

---

## Memory compare (only when `styles_logged`)

1. Note workout `number` + `startTime` so the wrong session is not compared.
2. Compare **working-lap stroke order** to memory (approx match is enough).
3. Rest / transition laps may be unknown or Medley — that is OK.
4. **Fail** only when styles are present but order clearly mismatches memory.
5. **All-null styles** → Blocked (not Fail).

---

## Empty enrichment retry

If blocked empty / no styles:

1. One reconnect + Sync retry.
2. If still empty → mark **Blocked**. Do **not** Forget the device.
3. Schedule next pool swim seed with this logging already landed.

---

## Export fallback (if logcat unavailable)

1. Coach Settings → app data JSON export.
2. Open canonical swim side-file for the workout.
3. Inspect lap `style` fields — same vocabulary as logs.
4. Still record Pass / Fail / Blocked here; Sync toast ≠ Pass.

---

## Gate for Style UI

- **Do not** start Intervals Style column / stroke labels UI from an unrecorded “looked fine” Sync.
- Style UI only after **Pass** in Verdict below, or explicit owner proceed-despite-partial.

---

## Verdict

| Field | Value |
|-------|--------|
| Date | 2026-08-14 |
| Workout number | 36 (latest; also styles_logged on 6, 7, 10–13, 16, 18–21, 26–28, 30, 31, 33) |
| startTime | 1786588295 |
| Observed sequence (codes / labels) | Free×4, Back, Breast×2, Free, Back, Free, Breast, Free×2, Back, Free, Back, Breast, Back, Free, Back (ends lap 19 = Backstroke) |
| Result | Pass |
| Notes | Owner confirmed last lap was Backstroke. Per-lap styles retained on GT5 full-history Sync (`styles_logged`). Session-level Medley / future mapping corrections deferred to Style UI follow-up. |

_Fill after the check. This section is the R6 handoff for Style UI follow-up._

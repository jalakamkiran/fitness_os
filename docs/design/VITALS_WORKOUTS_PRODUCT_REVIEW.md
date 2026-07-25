# Fathom — Vitals + Workouts tabs · Product Head review

**Status: Product Head APPROVED (2026-07-25)**  
**Chat:** [Huawei Watch · Product Head](https://chatgpt.com/g/g-p-6a60ffa173a4819192ab40fb9bce162a-huawei-watch/c/6a64a809-e4d0-83e8-996c-4e15f3ddef90)  
**Surfaces:** `docs/design/vitals-tab.html` · `docs/design/workouts-tab.html`  
**Hub:** `docs/design/index.html`  
**Local review:** http://127.0.0.1:8765/vitals-tab.html · http://127.0.0.1:8765/workouts-tab.html

## Brief (sent to Product Head)

Role: **Product Head** (not Design Head). Swim-first Huawei GT5 companion.

Locks (do not reopen): Brand Fathom; logo/app icon F; tabs Home | Vitals | Workouts; Home = now-state only; swim session detail locked at `swim-analytics.html`.

Review ask:

1. **Vitals** — owns physiological trends (HR etc.), Day/Week/Month, calm Fathom chrome, light/dark, phone + rail notes.
2. **Workouts** — owns session history; Swim populated; Run/Strength empty scaffolding OK; list → swim detail; no full charts dump on list.

Verify Home remains protected; Workouts list stays thin; charts only on locked swim detail.

## Verdict

| Authority | Result |
|---|---|
| ChatGPT Product Head | **APPROVED** |
| Owner | Pending notify / sign-off |

### Turn notes

1. First reply was **REJECTED** solely because localhost URLs were unreachable (not an IA reject).
2. Follow-up with screenshots of both phone+rail surfaces + inventory → **APPROVED**.
3. No must-fixes returned.

## Must-fixes applied

None — Product Head returned clean APPROVED after screenshot review.

## Surfaces inventory (for owner)

### Vitals (`vitals-tab.html`)

- Owns Day / Week / Month physiology trends
- Primary resting-HR series + Last HR / SpO₂ / HRV / Sleep cards
- Zone-time strip; explicitly defers session charts to Workouts → detail
- Never: workout lists, diagnoses, reasoner

### Workouts (`workouts-tab.html`)

- Sport tabs: Swim | Run (Soon) | Strength (Soon)
- Thin session rows → `swim-analytics.html`
- Optional one-line flag teaser only; no Pace/SWOLF/strokes charts on list
- Run/Strength empty scaffolding

## Do not reopen without owner unlock

Frozen tab ownership; Home chart-free; swim analytics package; Fathom brand/mark.

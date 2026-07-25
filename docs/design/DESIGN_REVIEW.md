# Fathom design review

**Date:** 2026-07-25  
**Role:** Design Review agent (findings only — no Flutter, no redesign)  
**Authority:** `docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md`, `docs/plans/2026-07-25-001-feat-fathom-brand-ia-productization-plan.md` (Design Head sections)

---

## Verdict

**LOCKED — owner signed off 2026-07-25**

Primary package (brand, Home IA, swim analytics) is approved. Residual Fitness OS leftovers on secondary research pages are hygiene only — do not reopen the locked package.

| Gate | Status |
|---|---|
| **Owner lock** | **Yes** — Flutter productization may proceed |
| **Hold** | **No** |

---

## Package inventory (re-check after wait)

| File | Status |
|---|---|
| `docs/design/design-system.html` | Present |
| `docs/design/logo.html` | Present |
| `docs/design/home-states.html` | Present |
| `docs/design/home-prototype/index.html` | Present — **says Fathom** (title + `brand-title`) |
| `docs/design/index.html` + `tokens.css` | Present (review hub + shared tokens) |

**Note:** During the wait window, `home-prototype/index.html` was still titled “Fitness OS”; it was updated to **Fathom** before this review closed. Current chrome is Fathom.

---

## Pass / fail checklist

### Design Head — logo must-fixes

| # | Requirement | Result | Notes |
|---|---|---|---|
| 1 | T legible at small sizes (favicon / icon / avatar); Discobolus→T must not hurt readability | **PASS** | Size ladder at `logo.html` § “Size ladder — T legibility” (≈L235–265). Raster check at 16 / 20 / 24 px: capital T remains a clear letter; shoulder ticks (`logo.html` L153–155) collapse into crossbar ends at 16 px rather than forming a competing glyph. |
| 2 | Figure secondary to wordmark; splash-only; never everyday UI mark | **PASS** | Splash storyboard banner “Splash only — never everyday icon” (`logo.html` L286–288). App icon section uses wordmark / lettermark T only (L202–232). No figure in Home chrome. |
| 3 | Simplified monochrome silhouette that scales | **PASS** | `#discobolus` / `#t-pose` are few solid shapes, `currentColor` fill (`logo.html` L168–181). No gradients/filters on mark artwork. |

### Design Head — production constraints

| # | Requirement | Result | Notes |
|---|---|---|---|
| 1 | Wordmark identifiable at 16–24 px height | **PASS** | Ladder + tokens `--mark-min: 16px`, `--wordmark-min: 20px` (`tokens.css` L26–27; restated `design-system.html` L278–280). |
| 2 | Single-colour vector; no gradients / shadows / fine interior detail | **PASS** | SVG symbols use flat `currentColor` (`logo.html` L137–138, L144–182). Page chrome shadows are UI, not mark fills. |
| 3 | Document + enforce min clear-space and min reproduction for **wordmark and splash figure** | **PARTIAL FAIL** | Wordmark clear-space + floors documented (`logo.html` L268–283; `tokens.css` `--clear-space`). **Splash figure** lacks its own clear-space diagram / min reproduction size — only “splash-only” usage copy. |

### IA locks

| Requirement | Result | Notes |
|---|---|---|
| Tabs: Home \| Vitals \| Workouts | **PASS** | `home-prototype/index.html` L106–109; all six frames in `home-states.html` tabbars. Frozen ownership table in `design-system.html` L218–247. |
| Home = sync / vitals snapshot / one swim takeaway / today’s totals | **PASS** | Happy-path Home: sync card L38–48, KPI totals L50–77, vitals snapshot L79–88, one takeaway L90–103. |
| Home never: graphs | **PASS** | Pool spatial board / pace charts removed from Home; rail notes move them to Swim charts (`home-prototype/index.html` L121). Subtle KPI sparks allowed by DS never-list (`design-system.html` L255–257). |
| Home never: vitals history | **PASS** | Snapshot only + “Vitals →” (`home-prototype/index.html` L79–87). |
| Home never: diagnosis lists | **PASS** | Single takeaway card; no Evidence→Diagnosis stack on Home. |
| Home never: reasoner settings | **PASS** | No reasoner/settings controls on Home; comment + rail (`home-prototype/index.html` L90, L118). |
| Six Home precedence states | **PASS** | `home-states.html` states 01–06 match plan order: Not paired → Paired never synced → Syncing → Failed → Data available → No swim data yet. |
| Brand name Fathom on product surfaces | **PASS** (primary) | Hub, DS, logo, Home, states all say Fathom. |
| Branding as tokens (not string-only) | **PASS** (prototype) | Shared `tokens.css`; Manrope + mint/amber pool-night language. |

### Secondary / research surfaces (not IA blockers)

| Surface | Result | Notes |
|---|---|---|
| `home-prototype/charts.html` | **PASS** (title) | Title is “Fathom — Swim charts…”; brand-mark `F`. |
| `home-prototype/advanced.html` | **FAIL** (leftover) | Still “Fitness OS” title + `FOS` mark (L6, L20). Reachable from charts → Advanced. |
| `chart-samples/index.html` | **FAIL** (leftover) | Still “Fitness OS research” copy (L6, L22). Research-only; linked from hub as analytics. |
| `swim-graphs-research.md` | **FAIL** (leftover) | Still names Fitness OS — markdown research, low owner risk. |

---

## Screenshot guidance (owner — look first)

Open `docs/design/index.html` in a browser, then in this order:

1. **Design system** — Confirm positioning (instrument / not coach theater), nav contract table, and Home never-list. Toggle light/dark once.
2. **Logo — Size ladder** — Stare at **16 px and 24 px** rows: does “Fathom” still read, and does the capital **T** stay a letter (not a blob)? Ignore hero size until small sizes pass.
3. **Logo — App icon / mark** — Confirm everyday marks are wordmark or letter **T** only (no Discobolus).
4. **Logo — Splash storyboard** — Frames 1–4: figure → T-pose → assemble → wordmark. Confirm figure feels splash-only and monochrome.
5. **Home prototype** — One phone: sync health, today totals, vitals snapshot, **one** swim takeaway, tabs Home \| Vitals \| Workouts. Confirm **no** pool board, charts, diagnosis list, or reasoner settings.
6. **Home states** — Skim all six frames; check unpaired CTA and “no swim yet” empty takeaway honesty.

Optional later: Swim charts / chart-samples (analytics research — not Home).

---

## Ordered must-fix list (max 7)

Fix before treating brand/production art as locked; **do not block owner viewing** on these:

1. **Document splash-figure clear-space + min reproduction** on `logo.html` Clear-space section (and mirror in `tokens.css` / DS constraints) — closes Design Head production constraint 3.
2. **Rename leftover Fitness OS chrome** on hub-reachable research pages: `home-prototype/advanced.html` (title + `FOS` → Fathom / `F`), `chart-samples/index.html` copy.
3. **Align hub blurb vs DS contents** — `index.html` claims design-system includes “Home state precedence”; the six-state gallery lives in `home-states.html`. Either add a short precedence pointer table to DS or soften the hub card copy.
4. **Owner eye-pass on T shoulder ticks** at 16 px (`logo.html` L153–155) — if they muddy favicon renders on device, drop ticks below 24 px / provide a simplified small-size wordmark variant. (Raster review: currently acceptable.)
5. **Optional:** Retitle `swim-graphs-research.md` Fitness OS references for consistency (low urgency).

---

## Explicit gate

| Question | Answer |
|---|---|
| Safe to show owner the Fathom design package? | **Yes** |
| Hold for missing logo / Home / states pages? | **No** |
| Home prototype still says “Fitness OS”? | **No** — current file says **Fathom** |
| Ready for Flutter execution? | **Yes** — owner locked 2026-07-25 (logo + Home + `swim-analytics.html`) |

---

## Owner lock addendum (2026-07-25)

Owner satisfied with the design package including swim session analytics (Product Head must-fixes applied: invent-guard toggle, normalized overlay, synced table, on-demand reasoner). Canonical surfaces remain under `docs/design/`. Do not reopen without explicit unlock.

---

## Summary

Design package **locked**. Core Design Head / Product Head / owner gates pass on primary HTML. Secondary research-page Fitness OS leftovers remain non-blocking hygiene.

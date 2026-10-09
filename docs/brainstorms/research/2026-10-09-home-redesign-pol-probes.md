---
date: 2026-10-09
topic: home-redesign-pol-probes
status: probe-plan
type: research
origin: /pm-probe (pol-probe-advisor)
informs: docs/brainstorms/2026-10-09-home-redesign-requirements.md
---

# Home redesign — Proof of Life probes

## Hypotheses under test

1. **H1 (value):** A hybrid Home (progress strip + chore CTA + sleep + sessions + adherence) makes opening Fathom feel worth it vs going straight to swim history.
2. **H2 (usability):** Owner can start today’s course in one tap from Home without hunting Programs.
3. **H3 (idle):** No-Agon Home with Odyssey upsell feels intentional, not spammy.

## Recommended probes (cheapest harsh truth first)

### Probe 1 — Narrative + Vibe-Coded HTML (now)
- **Flavor:** Narrative Prototype + Vibe-Coded PoL  
- **Why:** Primary risk is motivational/compositional, not API feasibility. HTML phone frames with state toggles beat Figma statics for “does this earn an open?”  
- **Artifact:** `docs/design/home-redesign-prototype/index.html`  
- **Pass:** Owner prefers Active and No-Agon frames over current Home for a week of opens; can point to chore CTA in &lt;2s.

### Probe 2 — Task-Focused Test (1 dogfood session)
- **Flavor:** Task-Focused Test  
- **Script:** “Open the prototype. Start today’s course. Find last night’s sleep. Say how many plan sessions you’ve done this week.”  
- **Pass:** Zero dead-ends; no request to open a Programs hub first.

### Probe 3 — Feasibility Check (planning, not this brainstorm)
- **Flavor:** Feasibility Check  
- **Why:** Wiring HomeSnapshot + ProgramsController chore CTA + Odyssey snapshot fields.  
- **Defer to:** `/ce:plan` — verify snapshot fields and navigation routes exist.

### Explicitly not first
- Synthetic data simulation (no statistical unknown).  
- Production Flutter as the first probe (too expensive before preference lock).

## Product design questions (probe-ready)

Use these in dogfood / peer review of the prototype:

1. On open, what did you look at first — progress, chore, or sleep? Was that the right order?
2. Did the chore CTA feel like “today’s training” or like another card in a stack?
3. Do the week dots answer “am I showing up this week?” without needing Workouts?
4. No-Agon frame: does the Odyssey upsell feel inviting or nagging?
5. What’s missing that would still make you skip to swim history?
6. If calories/steps are below the fold, do you feel under-informed?
7. Would you hide the game strip on some days? (feeds hide-game-layer later)

## Anti-patterns to reject in probes

- Judging success by how “industry standard” the screen looks.
- Adding charts until the first viewport becomes a dashboard.
- Treating sync blanking as validated by this UI probe (out of scope).

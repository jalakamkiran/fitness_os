---
date: 2026-09-05
topic: food-logging-photo-ai
status: draft-prd
origin: /pm-discover session 2026-09-05 (food logging / scale stall / habit scaffold)
related:
  - docs/plans/2026-08-09-002-feat-recovery-sleep-detail-plan.md (Food under Recovery deferred)
  - docs/export/app-data-export-schema.md (extend or sibling day-food export)
---

# Food logging v1 — photo AI + habit reminders (PRD)

## 1. Executive Summary

We're building a **shippable Food module** in Fitness OS / Fathom for **habit-building athletes** (dogfood first: owner; product-shaped for others) who train and sleep better but **cannot see intake** — especially with **home-cooked / family meals** they won't weigh. **IA:** Recovery bottom tab → **Vitals | Sleep | Food**.

**Delivery (locked):**
- **v0 — Habit logger (ship first):** meal schedule + pre-meal notifications → photo capture → optional name/note + optional manual kcal → day history → **day export** (meals + images for ChatGPT). No in-app AI yet.
- **v0.5 — Approximate (after ~7 days of real logs):** photo → cloud AI estimate → edit/confirm on top of the same logger.
- **Later:** Recovery coaching; local model train/fine-tune.

**Impact:** Form the logging habit and own meal photos first; then add approximation so the owner can judge rough surplus/deficit — without blocking habit on AI.

---

## 2. Problem Statement

### Problem framing narrative

**I am:** A mid-journey athlete using Fitness OS — training consistently, sleeping better, often eating meals prepared at home by family — trying to understand body-composition progress (and eventually bulk/cut cleanly).

**Trying to:** Know roughly what I'm eating day to day so I can tell whether a stuck scale is intake, noise, or something else — without weighing every plate.

**But:**
- Food was never a Fitness OS priority next to workout/sleep/watch sync
- Home-cooked meals have no barcodes / unknown oil and portions
- Manual database logging (MyFitnessPal-style) dies on friction
- Separate photo-calorie apps don't feed Fitness OS history or future Recovery

**Because:** Intake visibility requires a **low-friction capture habit** plus **good-enough estimates** that stay editable — and we jumped past food while shipping physiology features.

**Which makes me feel:** Frustrated that "I'm doing everything right" still doesn't explain the scale; stuck without data to adjust quantity later.

### Final problem statement

People mid-fitness journey (training and sleeping better, often eating unweighed home-cooked meals) struggle to capture rough daily intake inside Fitness OS — so they cannot diagnose energy balance or build a durable food-logging habit. Lean / long-habit users often don't need this; habit-builders and bulk/cut users do.

### Evidence

- Owner symptom: scale not moving despite training + sleep improvements
- Friends/colleagues report the same (home meals, no weighing, logging apps abandoned)
- Competitive category exists (Cal AI, Foodvisor, PlateLens, SnapCalorie, MFP Snap) — proves demand; accuracy often ~±8–14% MAPE for consumer photo AI → edit UX required
- Fitness OS IA already noted **Food under Recovery** as deferred (sleep plan out-of-scope)

🔶 **Assumption:** Friend/colleague pain is representative enough to ship a generic module without more interviews.  
🔶 **Assumption:** ±~15% estimates + edit are "good enough" for habit and weekly energy picture (not clinical cutting).

---

## 3. Target Users & Personas

### Primary proto-persona — Habit Hari

| Field | Hypothesis |
|-------|------------|
| **Who** | 25–40 athlete; uses Fitness OS; trains + tracks sleep; family/home cooking common |
| **Goal** | Build intake awareness habit; understand stuck scale / bulk-cut phases |
| **Behaviors** | Won't weigh food; will snap a photo if reminded before eating; abandons search-heavy loggers |
| **Needs** | Pre-meal nudge, fast photo estimate, always-editable save, day review/export |
| **Doesn't need (yet)** | Recovery "skip breakfast" coaching, local fine-tuned model |

### Secondary — Bulk/Cut Bhavna

Same capture UX; higher willingness to keep logging while manipulating weight. Same v1 surfaces; no special coaching in v1.

### Explicit non-users (v1)

- Already lean / indifferent to scale
- Multi-year habit keepers who don't need scaffolding
- Clinical / medical nutrition precision use cases

### Jobs-to-be-done

1. When a meal is about to happen, help me **capture it in seconds** so I don't forget.
2. When the plate is home-cooked, help me **estimate roughly** without a scale.
3. When the estimate looks wrong, help me **fix and still save** so the day isn't wasted.
4. When I review a day, help me **export meals + images** so I can sanity-check accuracy externally.

---

## 4. Strategic Context

### Why now

- Workout + sleep foundations exist; food is the obvious missing lifestyle signal
- Owner dogfood can validate habit + photo trust before Recovery coupling
- Photo-AI category is mature enough to buy/build via API rather than invent vision research

### Competitive landscape (summary)

| Product | Role vs Fitness OS |
|---------|-------------------|
| Cal AI, Foodvisor, PlateLens, SnapCalorie | Photo-first calorie UX bar; accuracy varies |
| MyFitnessPal / Lose It Snap | Database + optional snap; high friction for home meals |
| Fitness OS v1 | **In-app habit + photo log + export**; Recovery later; not a nutrition coach yet |

### Why not "just use Cal AI"

Separate apps don't create Fitness OS history, reminders tied to the companion, or a path to Recovery. v1 is the **owned logging rail**.

---

## 5. Solution Overview

### Scope lock (checkpoint)

| Phase | In | Out |
|-------|----|-----|
| **v0 Habit logger** | A (schedule + reminders) + photo capture + optional name/note + optional manual kcal + day history + day export | In-app AI estimate; Recovery coaching; local train |
| **v0.5 Approximate** | D + G (photo → AI → edit/confirm) on the v0 rail | Recovery coaching; local train |
| **Later** | Recovery nudges; local VLM / fine-tune on corrected logs | — |

**Save rule (v0, locked):** photo + **optional** manual kcal/note — kcal may be empty until v0.5 or until user fills it.

### Information architecture (locked)

- **Bottom nav:** Recovery (unchanged)
- **Recovery subtabs today:** Vitals | Sleep (`RecoverySubtab`)
- **Change:** Vitals | Sleep | **Food**
- Reminder deep links land on **Recovery → Food** (capture flow)

### High-level product

**v0**
1. **Onboarding (Food):** Usual meal schedule (slots + local times)
2. **Reminders:** Pre-meal notification → deep link to capture
3. **Capture:** Photo (camera or gallery) + optional name/note + optional manual kcal → save
4. **History:** Day list; daily total when kcal present (else show count / “kcal pending”)
5. **Export day:** Meals + images (+ any manual kcal/notes) for ChatGPT review

**v0.5 (after ~7 days dogfood)**
6. **Estimate:** Cloud vision/LLM approximate calories (optional macros)
7. **Confirm:** Edit name/portions/kcal before treating AI values as final (backfill on past photos optional)

### Key user flows

**F1. Schedule setup (v0)**  
Trigger: First open Food / settings  
Steps: Enter meal slots + times → enable notifications  
Outcome: Reminders scheduled locally  
Covered by: R1–R4, US-01

**F2. Pre-meal log (v0)**  
Trigger: Reminder or manual "Log meal"  
Steps: Camera/gallery → optional name/note + optional kcal → save  
Outcome: Meal (with photo) on today's log  
Covered by: R5, R9–R12, US-02a

**F3. Missed meal / late log (v0)**  
Trigger: User opens Food after eating  
Steps: Same capture without requiring reminder; optional meal-slot tag  
Outcome: Day still completable  
Covered by: US-02a

**F4. Day export (v0)**  
Trigger: End of day / Food actions  
Steps: Export meals + images for selected day → share sheet  
Outcome: Owner can send to ChatGPT for estimate/QA externally  
Covered by: R13–R15, US-04

**F5. AI approximate + confirm (v0.5)**  
Trigger: New log or “Estimate” on a saved meal  
Steps: Photo → AI → edit/confirm → save confirmed kcal  
Outcome: In-app rough energy totals  
Covered by: R6–R10, US-02b

### Phased delivery (locked)

1. **Ship v0** Habit logger in Fitness OS (Food subtab)  
2. **Dogfood ~7 days** — habit + export→ChatGPT for external estimates if desired  
3. **Ship v0.5** in-app approximation + edit/confirm  
4. **Later:** Recovery hooks; local VLM / fine-tune on *corrected* logs only

---

## 6. Success Metrics

### Primary (v0 — habit)

| Metric | Target (dogfood / early) | Notes |
|--------|--------------------------|-------|
| **Daily logging habit** | ≥2 meals logged on ≥10 of 14 days | Photos saved; kcal optional |
| **Reminder → log** | 🔵 Open: define % within 30 min of reminder | Track once notifications ship |

### Secondary (v0)

| Metric | Target | Notes |
|--------|--------|-------|
| **Time to save** | Median <45–60s (photo + optional fields) | Friction without AI wait |
| **Export used** | ≥1 day export in first 7 days | Validates ChatGPT QA path |

### v0.5 add-ons (after AI)

| Metric | Target | Notes |
|--------|--------|-------|
| **Discard rate** | <20% of estimate attempts abandoned | Trust/friction |
| **Edit rate** | Track % of saves with kcal edited vs AI | High edit OK if save completes |
| **Would trust weekly trend?** | Owner yes/no after 14 days with AI | Qualitative go for Recovery later |

### Non-goals for v0/v0.5 metrics

- Weight change attribution
- Recovery adherence
- Model MAPE vs weighed food (optional; export→ChatGPT is soft QA)

---

## 7. User Stories & Requirements

### Epic hypothesis

**We believe that** meal-schedule reminders + fast photo logging (optional kcal/note) + day export  
**will result in** a sticky meal-photo habit inside Fitness OS within ~7–14 days  
**and that** adding photo AI estimate + edit/confirm afterward  
**will result in** usable rough daily energy totals  
**we will know when** ≥2 meals/day most days, and (post-v0.5) discard rate stays low.

### Requirements

**Schedule & reminders — v0**
- R1. User can define meal slots (at least breakfast, lunch, dinner; optional snacks) with local times
- R2. App schedules local notifications before each enabled slot (lead time configurable; default 10–15 min)
- R3. Notification opens Food capture for that slot (or Food home if camera unavailable)
- R4. Reminders can be paused / disabled without deleting history

**Photo capture & manual fields — v0**
- R5. User can capture a meal photo via camera or gallery
- R5a. User can save with **photo required**; **name/note and kcal optional** (empty kcal allowed)
- R9. Editable fields: meal name/description, free-text note, optional calories
- R10a. Save must not require network or AI in v0

**AI estimate — v0.5 (not v0)**
- R6. System returns an approximate calorie estimate (and optional macros) from the photo via **cloud** vision/LLM API
- R7. Estimate UI always shows values as **approximate** (copy must not claim lab accuracy)
- R8. User **must** confirm or edit before AI values become the saved confirmed kcal
- R10. Failed AI still allows keeping photo-only or manual kcal so the day isn't blocked

**History — v0**
- R11. Meals list by day with photo thumbnails; show kcal when present; rough daily total only sums confirmed/manual kcal (label if incomplete)
- R12. User can edit or delete a saved meal

**Day export — v0**
- R13. User can export a selected day's meals including **images** + structured text (name, note, kcal if any, timestamps; AI vs confirmed when v0.5 exists)
- R14. Export uses share sheet / Files; suitable to send into ChatGPT app for estimate/QA
- R15. Export is owner-initiated; treat as sensitive health data (same care as existing app data export)

**Product honesty**
- R16. No Recovery "eat less tomorrow / skip breakfast / walk more" coaching in v0/v0.5
- R17. No local model training / on-device fine-tune in v0/v0.5
- R18. **IA (locked):** Food is a **Recovery subtab** beside Sleep — **Vitals | Sleep | Food** under Recovery (`RecoveryTabHost` / `RecoverySubtabs`). Not a new bottom-nav item.
- R19. Food subtab works without depending on Sleep/Vitals data (logging rail only)

### User stories (implementation-ready)

#### US-01 — Set meal schedule & reminders (v0)

- **Summary:** Schedule meal times and get pre-meal photo nudges
- **As a** Habit Hari  
- **I want to** set when I usually eat and get reminded before those times  
- **so that** I don't forget to log  

**Acceptance criteria**

```gherkin
Scenario: Save schedule and schedule notifications
  Given I open Food settings for the first time
  When I set breakfast/lunch/dinner times and enable reminders
  Then local notifications are scheduled for those slots
  And I can disable reminders without losing saved meals
```

#### US-02a — Log meal photo with optional kcal/note (v0)

- **Summary:** Photo + optional fields → save  
- **As a** Habit Hari  
- **I want to** photograph my meal quickly and optionally add a note or kcal  
- **so that** I build a logging habit without waiting on AI  

**Acceptance criteria**

```gherkin
Scenario: Photo-only save
  Given I start Log meal from a reminder or Food home
  When I take or pick a photo
  And I leave kcal empty
  And I save
  Then the meal is saved to today with the photo
  And daily total does not invent calories for that meal

Scenario: Optional manual kcal
  Given I have a meal photo ready
  When I enter a name or note and optional kcal
  And I save
  Then those fields are stored with the meal
```

#### US-02b — Approximate from photo with edit-before-confirm (v0.5)

- **Summary:** Photo → AI estimate → confirm  
- **As a** Habit Hari  
- **I want to** get an approximate calorie estimate and adjust it  
- **so that** my day totals become usable without weighing food  

**Acceptance criteria**

```gherkin
Scenario: Happy path confirm
  Given I have a meal photo (new capture or existing log)
  When the AI returns an approximate estimate
  And I edit or confirm calories and name
  Then confirmed values are saved (distinct from raw AI suggestion when both stored)

Scenario: AI failure fallback
  Given the estimate request fails
  When I enter calories manually or keep kcal empty and save
  Then the meal photo is not lost
```

#### US-03 — Review today's meals (v0)

- **Summary:** See today's log  
- **As a** Habit Hari  
- **I want to** see what I logged today  
- **so that** I know the habit is working  

**Acceptance criteria**

```gherkin
Scenario: Day list
  Given I have saved one or more meals today
  When I open Food for today
  Then I see each meal with photo thumbnail
  And kcal when present
  And a rough daily total only from meals that have kcal
  And I can edit or delete a meal
```

#### US-04 — Export day for ChatGPT review (v0)

- **Summary:** Export day's meals + images  
- **As a** Habit Hari  
- **I want to** export today's meals with photos  
- **so that** I can ask ChatGPT to estimate or sanity-check  

**Acceptance criteria**

```gherkin
Scenario: Export day package
  Given I have meals with images for a selected day
  When I tap Export day
  Then I receive a shareable package including images and meal metadata
  And optional kcal/notes are included when present
```

### Story splits / delivery order (locked)

| Order | Story | Phase |
|-------|-------|-------|
| 1 | US-02a capture + save (photo, optional fields) | v0 |
| 2 | US-03 day history | v0 |
| 3 | US-01 schedule + reminders | v0 |
| 4 | US-04 day export | v0 |
| 5 | API spike + US-02b approximate | v0.5 |

**Suggested delivery order:** US-02a → US-03 → US-01 → US-04 → (dogfood ~7 days) → US-02b.

---

## 8. Out of Scope (v0 / v0.5)

| Out | Why |
|-----|-----|
| In-app AI estimate in **v0** | Habit rail first; AI is **v0.5** after ~7 days |
| Recovery next-day coaching | Needs trusted logs first |
| Local LLM / train or fine-tune on-device | After corrected logs exist |
| Barcode / restaurant DB as primary path | Photo-first for home-cooked |
| Weighing / Bluetooth scale | Conflicts with "no time to weigh" |
| Multi-user / cook-facing UI | Defer |
| Clinical nutrition claims | Accuracy not the v0 bar |
| Third-party Cal AI as dependency | Own the rail |
| Opaque "nutrition score" | Honesty vs Recovery principles |

---

## 9. Dependencies & Risks

### Dependencies

**v0:** Local notifications; camera/gallery; on-device meal photo storage; day export/share  
**v0.5:** Cloud vision/LLM API (reuse Gemini patterns where sensible)  
**Either:** Food-specific day export preferred over overloading full app-data export for ChatGPT UX

### Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Habit without kcal feels "useless" | Export→ChatGPT for external estimates; optional manual kcal; clear “AI coming” framing |
| Reminder fatigue | Default lead time; easy pause; measure reminder→log |
| Photo AI weak on thalis / oil (v0.5) | Edit-before-confirm; approximate copy; export QA |
| API cost / latency (v0.5) | Cap image size; async; budget |
| Privacy (meal photos) | Local-first; owner-initiated export; redact from crash logs |
| **Anti-pattern: coach before habit** | R16 |
| **Anti-pattern: block habit on AI** | v0 ships without estimate |
| ChatGPT export ≠ ground truth | Second opinion only |

---

## 10. Open Questions

| ID | Question | Tag |
|----|----------|-----|
| Q1 | Which cloud vision/LLM for **v0.5** (Gemini vs others)? | 🔵 — defer until after v0 dogfood |
| Q2 | ~~IA placement~~ **Locked:** Recovery → Vitals \| Sleep \| **Food** | ✅ |
| Q3 | Reminder lead time default and quiet hours? | 🔵 |
| Q4 | Store AI suggestion vs confirmed (v0.5)? | 🔵 — recommend both |
| Q5 | Macros in v0.5 or kcal-only? | 🔵 — kcal first |
| Q6 | Image retention policy? | 🔵 |
| Q7 | Day export format (ZIP+JSON+images vs markdown+images)? | 🔵 |
| Q8 | Notification copy (Fathom tone)? | 🔵 |
| Q9 | ~~v0 save rule~~ **Locked:** photo required; name/note/kcal optional | ✅ |

---

## Self-Assessment

| Item | Assessment |
|------|------------|
| **Strongest section** | Phased v0 → v0.5 delivery + IA |
| **Weakest section** | Export package format (Q7) — decide in implementation |
| **Top assumptions to validate** | (1) Reminders + photo save stick for 7 days (2) Optional kcal is enough until AI (3) Export→ChatGPT is tolerable QA |
| **Recommended next step** | Implementation plan / build **v0** (US-02a → US-03 → US-01 → US-04) |

---

## Appendix A — Discovery decisions (locked)

- Primary user: owner dogfood; design bar = generic shippable feature  
- Outcomes: habit + (later) photo quality + shippable module  
- Opportunities: forget → friction → trust  
- **v0 bundle:** schedule + reminders + photo log (optional kcal/note) + day export  
- **v0.5:** photo AI + edit/confirm  
- Local train: phase later  
- Recovery coaching: later  
- **IA:** Recovery → Vitals | Sleep | **Food**  
- **Probe:** in-app v0 dogfood (~7 days), not camera→ChatGPT-only  

## Appendix B — Competitive feasibility (short)

Photo food logging is **product-feasible** via cloud multimodal models (v0.5). Consumer photo-AI error often ~**±8–14%**. Fitness OS optimizes for **habit + editable estimates + export QA**, not clinical MAPE.

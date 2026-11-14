# Fathom Product Review & Information Architecture

## Core User Profile

**The Athlete**: A single badminton/swim/run/strength athlete who:
- Trains 4-6 times per week across multiple disciplines
- Wears a Huawei Watch GT5 Pro to track all sessions
- Wants calorie burn data to inform diet decisions (intake vs. expenditure balance)
- Needs recovery metrics to drive training decisions (when to push, when to rest)
- Uses an AI coach bot that reads synced workout/sleep/food data via a backend
- Values honest metrics over gamification—no invented data, no flashy widgets

**Core Tension**: The current UI feels "gimmicky" rather than strategic. The athlete doesn't need motivation—they need decision support. Every screen should answer: *What should I do today? Am I recovered? Did I eat enough? Is my plan working?*

---

## Jobs-to-be-Done & Daily/Weekly Moments

### Morning Readiness Check (07:00-08:30)
**Job**: Decide today's training intensity  
**Needs**:
- Sleep quality/duration from last night
- Recovery time remaining (hours until ready)
- Today's planned workout (if following Agon program)
- Training load trend (am I overreaching?)

**Current gaps**: No unified readiness score, recovery time buried in home screen, sleep requires navigation to vitals tab, no visual "red/amber/green" signal.

---

### Post-Workout Review (immediately after session)
**Job**: Understand the session's impact & record proof  
**Needs**:
- Session totals (distance/time/pace/load/HR zones)
- Recovery cost (how many hours added?)
- Performance vs. baseline (swim: SWOLF trend, run: pace drift)
- Proof captured (for Agon trials, badminton match records)

**Current state**: Workout detail screens are comprehensive but analytics-heavy. For quick post-session glance, key numbers are diluted by dig-deeper metrics. No "share this session" quick action on detail.

---

### Evening Food vs. Burn Balance (19:00-21:00)
**Job**: Check if daily calorie intake covered expenditure  
**Needs**:
- Total calories burned today (from workouts + basal)
- Total calories logged (from food photos)
- Balance: deficit/surplus with visual indicator
- Macro breakdown (when logged)

**Current gaps**: 
- Home shows "calories burned" but not intake
- Food tab shows intake but not burn
- No single screen showing balance
- Calorie burn on home is just from workouts, not including basal metabolic rate

---

### Weekly Review (Sunday evening)
**Job**: Assess progress toward goals, adjust next week  
**Needs**:
- Week's sessions completed vs. planned (Agon adherence)
- Sleep consistency (avg duration, bed/wake time variance)
- Calorie balance trend (surplus/deficit pattern)
- Performance trend (swim pace improving? Run endurance building?)
- Next week's forecast (Agon milestone dates, recovery needs)

**Current state**: Agon Odyssey screen has streak/Areté/depth, but no weekly summary. Workout history is flat list, no week grouping. Sleep trends are 7-day sparklines but not synthesized. No "weekly digest" screen.

---

## Information Architecture: What Goes Where

### 1. Home/Today (PRIMARY DASHBOARD)

**Purpose**: Morning readiness + day-at-a-glance. This is decision central.

**Priority order**:
1. **Readiness indicator** (NEW) — composite: sleep score + recovery time + training load → Red/Amber/Green with short rationale ("Well rested, light load week" or "5h recovery remaining, consider rest day")
2. **Sleep summary** — last night duration + quality score (keep existing card, elevate position)
3. **Recovery time** — hours remaining (keep, but integrate into readiness)
4. **Today's plan** — Agon course OR "No session scheduled" (keep existing)
5. **Calorie balance** (NEW) — Burned vs. Intake with +/− indicator
6. **Today's completed sessions** — existing cards, collapse if empty
7. **Training load bar** (NEW) — 7-day rolling load with today's position
8. **Body HR** — demote below fold (not decision-critical)

**Remove/demote**:
- Brand header "F" badge → move to settings
- "Advanced tools" icon → settings only
- "Today" chip → implied by screen title
- Sync pill → persistent status bar indicator instead

**Rationale**: Athlete opens app first thing. They need a go/no-go signal, not navigation. Readiness must be immediate. Food balance drives evening check-in. Training load context prevents overtraining.

---

### 2. Workouts (HISTORY & PROOF)

**Purpose**: Session log, performance trends, export for coach

**Tabs remain**: Swim | Run | Strength (+ Badminton when implemented)

**Priority per tab**:
1. **Key trend chart** (NEW, top) — Swim: pace & SWOLF trend (7/14/30d), Run: pace & distance, Strength: load & recovery
2. **This week's sessions** (NEW section) — current week grouped, quick completion view
3. **All sessions list** — existing, keep filterable

**Detail screen**:
- **Keep**: Session meta, charts, HR zones, analytics
- **Elevate**: "Share as TCX" and "Export for AI" buttons to top action bar
- **Add**: "Add to Agon proof" quick action when trial is pending
- **Remove**: Excessive "dig deeper" cards for non-swim sports (run/strength don't need swim-level detail)

**Rationale**: Athletes review recent performance to understand progress. Week grouping makes adherence visible. Trends surface improvement or regression without diving into every session. Export/share supports coach collaboration.

---

### 3. Recovery & Sleep (VITALS TAB)

**Purpose**: Overnight data, sleep optimization, HRV trends

**Rename tab**: "Recovery" (not "Vitals"—more athlete-friendly)

**Priority order**:
1. **Sleep score + quality** — last night hero card (keep existing)
2. **Recovery contributors** (NEW) — what impacted score: deep sleep %, latency, HRV, interruptions
3. **Sleep debt** (NEW) — 7-day avg vs. target (e.g. "6h 45m avg, 15m below target")
4. **Timing chart** — bed/wake consistency (keep existing)
5. **Recent nights** — list with scores (keep)
6. **Feel on wake survey** — keep, but inline not separate card

**Demote**:
- "Enable auto-tracking" / "Sync" buttons → Settings screen
- Advanced metrics card → fold into "Sleep detail" screen

**Rationale**: Recovery is THE decision input for training. Sleep score means nothing without context—contributors and debt make it actionable. Timing chart helps identify consistency issues (late nights before poor sessions).

---

### 4. Food (NEW: NUTRITION HUB)

**Purpose**: Calorie tracking, meal log, balance

**Current state**: Food tab shows day meals, export. No balance or burn context.

**Priority order**:
1. **Daily balance** (NEW, hero position) — Large card: Burned [number] | Intake [number] | Balance +/− [number] with color (green surplus, amber neutral, red deficit)
2. **Today's meals** — photo tiles with calories (keep existing)
3. **Week trend** (NEW) — 7-day balance sparkline
4. **Quick log meal** — FAB (keep)

**Add**:
- Basal metabolic rate estimate (stored in settings, added to daily burn)
- Macro breakdown when available from food logs

**Rationale**: Food screen is currently just a meal log. Athlete needs it for balance decision ("did I eat enough?"). Balance card makes this instant. Week trend shows patterns (training days deficit, rest days surplus).

---

### 5. Programs (AGON)

**Keep existing structure**: Next trial, forecast, today's course, Odyssey strip

**Minor tweaks**:
- **Add**: "Week view" button → opens this week's courses with completion checkmarks
- **Elevate**: Trial proof recording CTA (currently buried)
- **Add**: "Share program" export for coach

**Rationale**: Agon is well-designed. Forecast timeline is strategic. Only gap is weekly adherence view.

---

### 6. Watch (DEVICE & SYNC)

**Purpose**: Pairing, sync, settings

**Reorganize**:
1. **Sync status** — last sync time, next auto-sync, manual sync button
2. **Watch details** — battery, connection state, firmware
3. **Sync history** — recent syncs with success/fail, data counts
4. **Advanced** — Gate A, R11 recovery, forget device

**Add**:
- Sync freshness indicator (time since last sync, color-coded)
- Sync conflict resolution (if backend sync comes)

**Rationale**: Currently pairing screen is dev-focused. Athlete just needs sync status and manual trigger. Advanced stuff can be collapsed.

---

### 7. Settings (NEW HUB)

**Purpose**: Account, preferences, advanced tools

**Sections**:
1. **Profile** — name, weight, basal metabolic rate (for calorie balance)
2. **Goals** — target sleep hours, weekly session frequency, weight goal trend
3. **Preferences** — theme (light/dark), units (metric/imperial)
4. **Advanced tools** — diagnostics, export cache, reasoner settings
5. **About** — version, licenses, privacy policy

**Add**:
- Weight trend graph (for athletes tracking cut/bulk phases)
- Coach bot connection status (when backend ready)

**Rationale**: Settings are scattered (advanced tools on home, reasoner on workout detail). Consolidate. Add profile data needed for calorie balance calc.

---

## Navigation Structure: Tabs vs. Hubs

**Recommendation**: Keep bottom tab navigation (familiar, fast), but optimize labels.

### Proposed Tab Bar (5 tabs):
1. **Today** (home icon) — readiness dashboard
2. **Workouts** (dumbbell icon) — session history
3. **Recovery** (moon icon) — sleep & vitals
4. **Food** (utensils icon) — meals & balance
5. **More** (ellipsis icon) — Programs, Watch, Settings

**Rationale**: 
- 4 primary athlete jobs (readiness, sessions, recovery, nutrition) get dedicated tabs
- Programs (Agon) is advanced feature, doesn't need primary tab—access via "More"
- Watch/sync is infrequent, nests under "More"
- Reduces cognitive load (5 clear choices vs. current 6+ scattered screens)

---

## Feature Gaps Worth Adding

### Quick Wins (implement in redesign):
1. **Readiness score** — composite: sleep score (40%) + recovery time (40%) + training load (20%)
2. **Calorie balance card** — burn (workouts + basal) vs. intake (food logs)
3. **Sync freshness indicator** — persistent status bar showing "Synced 2h ago" with color
4. **Week grouping in workout history** — "This week: 4 sessions, 1200 kcal"
5. **Sleep debt tracker** — 7-day avg vs. target, cumulative shortfall
6. **Training load bar** — rolling 7-day load with red/amber/green zones

### Bigger Bets (note for future, not in mockup scope):
1. **Coach suggestions surface** — AI bot recommendations on Today screen ("Consider rest day" or "Ready for trial")
2. **Goal trend graphs** — weight over time, swim pace over 90 days
3. **Workout calendar view** — month grid with session types
4. **Social proof sharing** — "Share session" with coach or training partner
5. **Badminton match tracking** — opponent, score, rally patterns (watch doesn't record this yet, needs manual entry)
6. **Program templates** — pre-built Agon programs for common goals (marathon, triathlon, cut phase)

---

## Quick Wins vs. Bigger Bets: Effort Matrix

### Quick Wins (Design + Basic Logic, No New Data Sources):
- Readiness score: formula from existing data (sleep score, recovery time, session load)
- Calorie balance: food kcal - (workout kcal + basal rate from settings)
- Sync freshness: display last sync timestamp from state
- Week grouping: UI change, group by week in workout list
- Sleep debt: avg duration calculation vs. target from settings
- Training load bar: sum workout loads from last 7 days

### Medium Effort (Requires New UI + Some Data Modeling):
- Trend charts: aggregate swim pace, run distance over time
- Recovery contributors: parse TruSleep summary fields
- Weight trend: add weight log feature to settings

### Bigger Bets (Requires Backend/AI Integration or Major Features):
- Coach suggestions: needs AI backend with recommendation engine
- Badminton tracking: needs match entry UI + replay viz
- Program templates: needs Agon planner UX overhaul
- Social sharing: needs account system + privacy controls

**Recommendation**: Mockups include all Quick Wins + trend charts (medium). Note Bigger Bets as "future" placeholders.

---

## Design Principles (Applied to Mockups)

1. **Strategic, Not Gimmicky**: Every element answers a decision. No decoration. No invented metrics.
2. **Calm Hierarchy**: Large, confident typography for key numbers. Generous whitespace. Muted accents.
3. **Data Density Where It Matters**: Today screen is concise; detail screens can be dense (athlete is engaged at that point).
4. **Trust Through Honesty**: Show data gaps ("Not synced yet") rather than fake placeholders. Explain metric sources.
5. **Athlete-First Language**: "Recovery" not "Vitals", "Readiness" not "Wellness", "Balance" not "Calorie Tracker".
6. **Dark Mode Friendly**: Muted accent (mint), low-contrast backgrounds, avoid pure white/black.

---

## Rationale Summary

The current app is **feature-complete but presentation-diluted**. All the data exists (sleep, sessions, recovery, food), but it's scattered across screens with inconsistent priority. The athlete has to hunt for answers.

The redesign **reorganizes existing data into decision-centric surfaces**:
- Morning: "Am I ready?" → Readiness score on Today
- Evening: "Did I eat enough?" → Balance on Food/Today
- Post-workout: "How was that?" → Trends on Workouts
- Weekly: "Is my plan working?" → Week grouping + Agon forecast

No flashy animations. No motivational quotes. Just honest, well-organized data that supports an athlete making training and nutrition decisions. The UI becomes a **tool, not a toy**.

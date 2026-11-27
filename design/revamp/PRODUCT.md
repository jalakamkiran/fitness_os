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

---

## Data Placement Rationale

### Why Each Data Group Lives Where It Does

This section explains the reasoning behind the placement of every data group collected from the Huawei Watch GT5 Pro, based on the complete audit in `DATA_INVENTORY.md`.

---

#### **Sleep Data → Sleep Detail Screen**

**Data Fields:**
- TruSleep score, stages (Awake/REM/Light/Deep), efficiency %, latency, deep continuity
- HR/SpO₂/HRV/breathing rate overnight
- Bed/asleep/wake/rising times
- 7/30-day trend charts

**Why Here:**
Sleep is a **foundational recovery input**. Athletes need to understand sleep quality before making training decisions. The detail screen provides the full story:
- **Hero Score**: Immediate answer ("Was last night's sleep good?")
- **Hypnogram**: Visual proof of stage progression (catch interruptions, poor deep sleep)
- **Score Factors**: Actionable contributors (low efficiency = too much awake time; high latency = trouble falling asleep)
- **Vitals Overnight**: Prove recovery quality (low HR = good parasympathetic tone; good SpO₂ = no breathing issues)
- **Trends**: Show consistency or regression over 7/30 days

**Why Not on Today?**
Today's sleep card shows the **summary** (score + duration + key stages). The detail screen is for **investigation** when the score is poor or the athlete wants to optimize.

---

#### **Recovery Time → Recovery Screen + Today Card**

**Data Fields:**
- Session-by-session recovery times (from `WorkoutSummary.recoveryTime`)
- Training load per session (`WorkoutSummary.load`)
- Aerobic/anaerobic TE (`WorkoutSummary.aerobicEffect`, `anaerobicEffect`)
- Overall recovery composition (stacked recovery + sleep/activity modifiers, from `overall_recovery_hours.dart`)

**Why Here:**
Recovery time is the **critical go/no-go decision metric** for hard training. Athletes need to know:
- **Total hours remaining**: Can I do a hard session today? (Hero card on Recovery screen + tile on Today)
- **What contributed**: Which recent sessions are still costing me? (Session list with individual recovery times)
- **7-day training load chart**: Am I overreaching? (Visual spike detection)

**Why Split Between Recovery Screen & Today?**
- **Today Card**: Quick glance answer ("14h remaining")
- **Recovery Screen**: Full context (training load history, session breakdown, modifiers from sleep/activity)

**Why Not Just on Today?**
Recovery is a **complex composition** (not a single sensor reading). The full screen provides the evidence athletes need to trust the number.

---

#### **Workout Data → Workouts List + Detail Screens**

**Data Fields:**
- All sports: Duration, calories, HR zones, training load, aerobic/anaerobic TE, recovery time
- Swim-specific: Laps, strokes, SWOLF, pace, pool length, style
- Run-specific: Distance, pace, splits, cadence
- Badminton: High anaerobic zones, duration
- Strength: Load, TE, recovery

**Why Here:**
Workouts are **performance logs**. Athletes review them to:
- **Track progress**: Am I getting faster? (pace trends)
- **Validate sessions**: Did I hit the prescribed zones? (HR zone distribution)
- **Identify patterns**: Why was this session harder than last week? (compare training load)

**Why Split List + Detail?**
- **List**: Quick scan of recent sessions (date, sport, distance/duration)
- **Detail**: Full session breakdown (laps, splits, HR curve, training effect)

**Why Sport-Specific Detail Screens?**
Each sport has **different key metrics**:
- **Swim**: SWOLF, strokes/lap, pace consistency matter more than absolute speed
- **Run**: Pace splits, cadence, elevation (when available)
- **Badminton**: Anaerobic zones dominate (explosive sport)
- **Strength**: Load, sets/reps estimate, TE (no distance/pace)

Generic "workout detail" would dilute the signal.

---

#### **Activity Totals → Activity Screen + Today Rings**

**Data Fields:**
- Steps, calories, distance (from `FitnessTotalsDay` day rollup)
- 7-day trend charts

**Why Here:**
Activity totals are **baseline movement context** for recovery and nutrition. Athletes need to know:
- **Did I hit my step goal?** (Today rings)
- **Am I consistent week-to-week?** (7-day chart)
- **How much did I burn today?** (for energy balance)

**Why Split Between Activity Screen & Today?**
- **Today Rings**: Quick goal progress (68% of 10,000 steps)
- **Activity Screen**: Trends and comparisons (last 7 days, daily avg)

**Why Not Just on Recovery Screen?**
Activity is a **separate job** from training recovery. Non-workout movement (walking to work, errands) affects energy balance but doesn't require recovery time.

---

#### **Heart Rate → Heart Rate & HRV Screen**

**Data Fields:**
- 24h HR curve (from `DailyHrSample` continuous samples)
- Resting HR (min from `DailyHrDaySummary`)
- 7-day resting HR trend
- Max/min/avg HR

**Why Here:**
Resting HR is a **key recovery marker**. Athletes track it to:
- **Detect overtraining**: Elevated resting HR = insufficient recovery
- **Validate readiness**: Stable resting HR = ready for hard work
- **Understand daily trends**: Catch illness or stress early

**Why Not on Recovery Screen?**
Resting HR is **one input** to recovery, not the full story. The dedicated screen provides:
- **24h context**: See HR spikes (caffeine? stress?)
- **Trend analysis**: 7-day chart catches gradual elevation

**Why Not on Today?**
Today focuses on **actionable decisions** (sleep score, recovery time, today's workouts). HR is a **diagnostic detail** when something feels off.

---

#### **Programs (Agon) → Programs Screen**

**Data Fields:**
- Chore sessions (WU/Main/CD blocks, from `ChoreSession`)
- Due/done/skipped states (`ChoreState`)
- Effort zones, rest intervals (`ChoreBlock.effortBand`, `restGuidanceSec`)
- Auto-linking to completed workouts (`matchedWorkoutNumber`)

**Why Here:**
Programs are **prescribed structure**. Athletes need to:
- **See this week's plan**: What's due today? (Weekly calendar view)
- **Check block details**: What's in the main set? (Session detail with WU/Main/CD)
- **Track completion**: Did I do it? (Done/skipped states)

**Why Not on Today?**
Today is for **what happened** (last night's sleep, today's workouts). Programs are for **what should happen** (structured training plan). Mixing them creates cognitive load.

**Why Under "More" Tab?**
Programs are **not daily decisions** for most athletes. They check the plan once (morning or night before) and execute. Today/Recovery/Workouts are **constant reference** throughout the day.

---

#### **Food → Food Screen + Energy Balance**

**Data Fields:**
- Meal log with photos (`FoodMeal.photoPath`, `kcal`, `slot`)
- Daily calorie sum (computed from meals)
- Energy balance (calories in - calories out from `FitnessTotalsDay.calories`)

**Why Here:**
Food is **fueling context** for training. Athletes need to:
- **Track intake**: Did I eat enough today? (Energy balance card)
- **Log meals**: What did I eat? (Photo log with manual kcal)
- **Understand deficit/surplus**: Am I under-fueling? (Balance: +572 or −300)

**Why Energy Balance is Hero?**
Without context, calorie tracking is **meaningless**. Showing intake alone doesn't answer "Did I eat enough?" Balance (in - out) gives the answer immediately.

**Why Photos?**
Visual log is **faster than manual entry** and more honest (can't forget the snack you photographed).

**Why Not on Recovery Screen?**
Food affects recovery but is a **separate behavior**. Recovery screen focuses on **training inputs** (sessions, sleep). Food screen focuses on **nutrition inputs**.

---

#### **Weight → Weight Screen**

**Data Fields:**
- Current weight (`weightKg`, manual or from future Bluetooth scale)
- 30-day trend chart

**Why Here:**
Weight is a **periodic check**, not a daily metric. Athletes track it to:
- **Monitor trends**: Am I losing/gaining? (30-day chart)
- **Validate energy balance**: Surplus = gain, deficit = loss
- **Adjust nutrition goals**: Trending up? Reduce intake.

**Why Not on Today?**
Weight changes **slowly** (days/weeks, not hours). Daily display would be noise. The dedicated screen shows **trends**, which matter more than single readings.

**Why Under "More" Tab?**
Weight is **not a training decision input**. It's a periodic check (weekly or bi-weekly). Today/Recovery/Workouts are constant reference.

---

#### **Device & Sync → Device & Sync Screen + Today Pill**

**Data Fields:**
- Watch name, MAC, battery level (from `HuaweiSession.kt` CMD_BATTERY)
- Connection status (`LinkState`)
- Last sync time, sync-in-progress indicator
- Auto-tracking feature arm status (TruSleep, Auto-HR, Auto-SpO₂)

**Why Here:**
Device status is **infrastructure context**. Athletes need to:
- **Check battery**: Is my watch going to die overnight? (78% = good)
- **Verify connection**: Why isn't new data showing up? (disconnected)
- **Trigger sync**: Manual sync when data is stale (Sync Now button)

**Why Split Between Today Pill & Detail Screen?**
- **Today Pill**: Quick status ("Synced 2m ago")
- **Detail Screen**: Full diagnostics (battery, connection, feature arm status)

**Why Not Always Visible?**
Device status is **infrastructure**—only relevant when something is wrong. The Today pill provides the quick check; the detail screen is for troubleshooting.

---

#### **Settings & Profile → More Tab**

**Data Fields:**
- User name, photo, biometrics (age, sex, height, weight)
- Goals (daily steps, sleep hours)
- Notifications, theme, about

**Why Here:**
Settings are **configuration**, not daily decisions. Athletes access them:
- **Once per setup**: Set biometrics, goals
- **Rarely**: Change theme, toggle notifications
- **Never during training**: Settings don't inform "What should I do today?"

**Why Under "More" Tab?**
Grouping non-daily tasks under "More" keeps the primary tabs (Today, Workouts, Recovery, Food) focused on **actionable decisions**.

---

#### **State Screens (Loading, Empty, Error, Offline, Syncing)**

**Data Fields:** None (UI states, not data)

**Why Here:**
State screens **explain system status** when normal UI can't display:
- **Loading**: Data fetch in progress (spinner)
- **Empty**: No data yet (onboarding, first sync)
- **Error**: Sync failed (retry button)
- **Offline**: BT off or watch disconnected (reconnect prompt)
- **Syncing**: Manual sync in progress (cancel button)

**Why Not Inline Banners?**
Full-screen states provide **clear feedback** without UI clutter. Athletes know immediately why they're not seeing data, rather than guessing from an empty list.

---

### Summary: Data Placement Philosophy

1. **Today Screen** = **High-frequency decisions** (sleep score, recovery time, today's workouts)
2. **Detail Screens** = **Investigation** when summary isn't enough (sleep factors, workout laps, HR trends)
3. **Recovery Screen** = **Training readiness** (can I train hard today?)
4. **Workouts Screen** = **Performance log** (am I improving?)
5. **Food Screen** = **Fueling context** (did I eat enough?)
6. **Activity Screen** = **Baseline movement** (steps, non-workout calories)
7. **More Tab** = **Periodic checks & config** (weight, programs, device, settings)

**Unplaced Data (Future):**
- Advanced HRV/Stress samples → Heart Rate & HRV screen (when LPv2 exposes)
- SpO₂ continuous samples → Heart Rate & HRV screen (when requested in FitnessDataSync)
- Run cadence → Workout Detail: Run (when parsed from WorkoutData sample pages)
- Menstrual cycle → New "Health" screen under More tab (when synced)

---

**End of Data Placement Rationale**

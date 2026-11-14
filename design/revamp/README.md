# Fathom Design Revamp

This redesign transforms Fathom from a "gimmicky" fitness tracker into a **strategic athlete's decision tool**. Every screen answers a specific question; every metric supports a training or nutrition decision.

## Why the Current UI Feels Gimmicky

### Problems Identified:
1. **Scattered Information**: Key decision metrics (readiness, calorie balance, recovery) require navigating 3+ screens
2. **Inconsistent Priority**: Large "F" brand badge and "Today" chips take space from actual data
3. **Decoration Over Function**: Pills, badges, and chrome that don't communicate state
4. **Invented Hierarchy**: All cards look equal—no clear "hero" information
5. **Missing Context**: Metrics without trends (am I improving?), balances without baselines (is this good?)
6. **Feature Sprawl**: 6+ top-level navigation options dilute focus

### Root Cause:
The app was built feature-first ("let's add sleep tracking, food logging, programs") without a unifying job-to-be-done. Each feature got equal visual weight, creating a "dashboard of dashboards" rather than a decision tool.

---

## How the Redesign Fixes It

### Strategic Shifts:

1. **Decision-Centric Layout**: Every screen starts with the answer, then provides supporting evidence
   - Today: "Are you ready?" → Readiness score + rationale
   - Food: "Did you eat enough?" → Balance card
   - Workouts: "Are you improving?" → Trend chart

2. **Calm Visual Hierarchy**: 
   - One hero element per screen (large, confident)
   - Supporting cards clearly secondary (smaller, muted)
   - Tertiary details below fold or in detail views

3. **Muted Palette**:
   - Reduce accent usage to state communication (ready/not ready, synced/stale)
   - Neutral grays for structure
   - Color only where it means something (green = good, amber = caution, red = action needed)

4. **Honest Gaps**:
   - Show "Not synced yet" rather than placeholder zeros
   - Explain metric sources ("From last night's TruSleep")
   - No fake data, no motivational fluff

5. **Consolidated Navigation**:
   - 5 clear tabs (Today, Workouts, Recovery, Food, More)
   - Agon, Watch, Settings nest under "More"

---

## Design Principles

### 1. Strategic, Not Gimmicky
❌ Badges, pills, brand marks taking prime real estate  
✅ Data that answers "What should I do today?"

### 2. Calm, Not Loud
❌ High-contrast accents everywhere, competing for attention  
✅ Muted tones, generous whitespace, confident typography

### 3. Honest, Not Invented
❌ Placeholder metrics ("Wellness: 73%" with no source)  
✅ Real data with sources, gaps shown clearly

### 4. Athlete Language, Not Consumer Tech
❌ "Vitals", "Activity", "Health"  
✅ "Recovery", "Readiness", "Sessions"

### 5. Decision Support, Not Motivation
❌ "You can do it!" messages, streaks, badges  
✅ Recovery time remaining, calorie balance, training load

---

## Information Architecture

### Before (Current):
```
Home (scattered dashboard)
├─ Sync status
├─ Sleep summary
├─ Recovery time
├─ Sessions today
├─ Totals (calories, steps)
└─ Body HR

Workouts (flat list)
├─ Swim tab
├─ Run tab
└─ Strength tab

Vitals (technical)
├─ Enable tracking
├─ Sync button
└─ HR day panel

Food (isolated)
├─ Today's meals
└─ Export

Programs (Agon)
└─ (well designed, keep)

Device Pairing (dev-focused)
└─ (technical, needs simplification)
```

### After (Redesigned):
```
TODAY (decision dashboard)
├─ Readiness Score (hero) ← NEW
├─ Sleep Summary
├─ Recovery Time
├─ Calorie Balance ← NEW
├─ Training Load Bar ← NEW
├─ Today's Plan
├─ Completed Sessions
└─ (Body HR below fold)

WORKOUTS (performance tracking)
├─ Trend Chart ← NEW
├─ This Week's Sessions ← NEW
├─ Swim tab
├─ Run tab
└─ Strength tab

RECOVERY (sleep optimization)
├─ Last Night Score
├─ Contributors ← NEW
├─ Sleep Debt ← NEW
├─ Timing Chart
└─ Recent Nights

FOOD (nutrition balance)
├─ Daily Balance ← NEW (hero)
├─ Week Trend ← NEW
├─ Today's Meals
└─ Log Meal (FAB)

MORE (secondary features)
├─ Programs (Agon)
├─ Watch & Sync
└─ Settings
    ├─ Profile (weight, BMR) ← NEW
    ├─ Goals (sleep target) ← NEW
    └─ Advanced Tools
```

---

## Design System

### Color Tokens

All colors defined as CSS custom properties, mapped 1:1 to Flutter `FathomColors` class.

#### Light Mode:
```css
--bg: #EEF2F6;           /* App background */
--bg-elev: #FFFFFF;      /* Cards, elevated surfaces */
--ink: #142033;          /* Primary text */
--ink-dim: #5B6B7C;      /* Secondary text */
--ink-faint: #8A97A6;    /* Tertiary text, labels */
--line: rgba(20,32,51,0.08); /* Dividers, borders */

--accent: #19B7B0;       /* Mint - primary actions, positive state */
--accent-ink: #043532;   /* Text on accent fills */
--amber: #D97706;        /* Warning, caution */
--hot: #E85D4C;          /* Error, urgent */
--up: #0F9F6E;           /* Success, improvement */

--pool: #D7F3F1;         /* Soft wash backgrounds */
--pool-line: rgba(25,183,176,0.45); /* Pool borders */
--gauge-track: #D5DEE8;  /* Chart backgrounds, progress tracks */
--spark: #19B7B0;        /* Sparkline strokes */
```

#### Dark Mode:
```css
--bg: #0B0D10;
--bg-elev: #14181E;
--ink: #F3F6F8;
--ink-dim: #A7B2BD;
--ink-faint: #6F7B88;
--line: rgba(243,246,248,0.10);

--accent: #5DFFC4;       /* Brighter mint for dark BG */
--accent-ink: #06281D;
--amber: #F0C75E;
--hot: #FF7A68;
--up: #5DFFC4;

--pool: #0F2428;
--pool-line: rgba(93,255,196,0.28);
--gauge-track: #2A323C;
--spark: #5DFFC4;
```

#### Usage Guidelines:
- **bg**: Screen backgrounds, negative space
- **bg-elev**: Cards, modals, elevated surfaces (1-2dp)
- **ink**: Headings, primary data, key numbers
- **ink-dim**: Body text, supporting data
- **ink-faint**: Labels, meta text, captions
- **line**: Card borders, dividers, hairlines
- **accent**: Primary actions (buttons, FABs), positive indicators (synced, ready)
- **amber**: Warnings (sync pending, recovery low)
- **hot**: Errors (sync failed, overtraining), negative balance
- **up**: Success, improvements (trend up arrows)
- **pool**: Soft highlight areas (selected tab, info cards)
- **gauge-track**: Chart axes, progress bar backgrounds

### Typography Scale

**Font Families**:
- **Sans**: Manrope (display, UI)
- **Mono**: IBM Plex Mono (metrics, data, timestamps)

**Scale** (mapped to Flutter `TextTheme`):
```css
--text-display-xl: 40px/40px, weight 800, -1.2px tracking
--text-display-lg: 32px/34px, weight 800, -1.0px tracking
--text-display-md: 28px/31px, weight 700, -0.8px tracking

--text-headline-lg: 28px, weight 700, -0.6px tracking
--text-headline-md: 24px, weight 700, -0.4px tracking
--text-headline-sm: 20px, weight 700, -0.3px tracking

--text-title-lg: 24px, weight 700, -0.4px tracking
--text-title-md: 18px, weight 600, -0.2px tracking
--text-title-sm: 14px, weight 600

--text-body-lg: 16px/24.8px, weight 400
--text-body-md: 14px/21px, weight 400
--text-body-sm: 12px/16.8px, weight 400

--text-label-lg: 14px, weight 600 (sans)
--text-label-md: 12px, weight 500, +0.6px tracking (mono)
--text-label-sm: 11px, weight 500, +0.8px tracking (mono)
```

**Usage**:
- **Display**: Hero metrics (readiness score, calorie balance)
- **Headline**: Screen titles, card headlines
- **Title**: Section headers, card titles
- **Body**: Descriptive text, explanations
- **Label**: Tags, pills, meta labels

**Negative Tracking**: Large headings use negative tracking (-0.3px to -1.2px) for tighter, more confident appearance. Reduces "tech startup" feel, increases "professional tool" vibe.

**Mono for Data**: All numbers, timestamps, and metrics use IBM Plex Mono for tabular alignment and readability.

### Spacing Scale

8px base grid:

```css
--space-xs: 4px;
--space-sm: 8px;
--space-md: 12px;
--space-lg: 16px;
--space-xl: 20px;
--space-2xl: 24px;
--space-3xl: 32px;
--space-4xl: 48px;
```

**Layout Padding**:
- Screen edges: 16px (--space-lg)
- Card padding: 16px
- Card-to-card gap: 12px (--space-md)
- Section spacing: 24px (--space-2xl)

**Component Spacing**:
- Button padding: 12px vertical, 16px horizontal
- Input padding: 12px
- List item padding: 16px vertical, 16px horizontal
- Icon-to-text gap: 8px (--space-sm)

### Border Radius

```css
--radius-sm: 8px;   /* Small buttons, chips */
--radius-md: 12px;  /* Cards, inputs */
--radius-lg: 18px;  /* Primary cards, hero elements */
--radius-xl: 24px;  /* Full-screen modals */
--radius-full: 999px; /* Pills, circular icons */
```

**Usage**:
- Hero cards (readiness, balance): 18px
- Standard cards: 12px
- Buttons: 12px (standard), 999px (pills)
- Pills, badges: 999px

### Elevation & Shadows

**Elevation Tokens** (via `bg` and `bg-elev` colors, not shadows):
- Level 0: `bg` (screen background)
- Level 1: `bg-elev` (cards, surfaces)
- Level 2: Modals use `bg-elev` + subtle shadow

**Shadow** (sparingly used):
```css
--shadow: rgba(0,0,0,0.08) 0 2px 8px; /* Light mode */
--shadow: rgba(0,0,0,0.45) 0 2px 12px; /* Dark mode */
```

**Philosophy**: Prefer elevation via background color change over shadows. Shadows only for modals/dropdowns to indicate "above content" layer. No drop shadows on cards (keeps UI flat and calm).

### Iconography

**Style**: Material Icons (outlined variant for consistency with Material Flutter)

**Size Scale**:
- Small (inline text): 16px
- Standard (list items): 20px
- Large (hero icons): 24px
- Tab bar: 24px

**Usage**:
- Navigation: home, fitness, moon, utensils, ellipsis
- Actions: sync, share, add, edit, delete
- States: check (success), warning, error, info
- Sports: swim, run, strength icons (custom SVGs in `/assets/icons/swim/`)

**Color**: Icons inherit text color (ink, ink-dim, ink-faint) unless indicating state (accent, amber, hot).

### Chart Style

**Line Charts** (workout trends, sleep timing):
- Stroke width: 2px
- Accent color for primary series
- `gauge-track` for axes
- `ink-faint` for grid lines (optional, only if improves readability)
- No fills, no gradients

**Bar Charts** (training load, sleep stages):
- Accent color for bars
- `gauge-track` for unfilled portions
- 4px gap between bars
- Rounded corners (4px) for visual softness

**Sparklines** (inline trends):
- 1.5px stroke
- Accent or spark color
- No axes, no labels (context in surrounding text)
- Height: 24px (compact), 40px (standard)

**HR Zones** (workout detail):
- Zone 1 (recovery): pool color (muted mint)
- Zone 2-3 (aerobic): accent (mint)
- Zone 4-5 (anaerobic): amber → hot gradient
- Stacked bars, no gaps

### Motion Guidelines

**Philosophy**: Calm, purposeful motion. No bounces, no overshoots.

**Duration**:
- Micro (button press, checkbox): 100ms
- Standard (page transition, modal): 300ms
- Complex (chart animation): 600ms

**Easing**:
- Ease-out (default): Elements entering or growing
- Ease-in: Elements exiting or shrinking
- Ease-in-out: Elements moving within view

**Flutter Curves** (map to Material):
- `Curves.easeOut` (standard)
- `Curves.easeInOut` (page transitions)
- `Curves.fastOutSlowIn` (material standard)

**What NOT to animate**:
- Text changes (jarring)
- Data updates (confusing)
- List reordering (unless user-initiated drag)

**What to animate**:
- Screen transitions (horizontal slide for stack, fade for tabs)
- Modal appearance (fade + slight scale)
- Button press (subtle scale 0.95)
- Loading states (spinner, skeleton shimmer)

---

## Flutter Mapping

### ThemeData Structure

```dart
ThemeData(
  brightness: Brightness.light, // or dark
  colorScheme: FathomColors.light.toColorScheme(Brightness.light),
  textTheme: FathomTextStyles.textTheme(FathomColors.light),
  extensions: [FathomColors.light],
  
  // Component themes
  cardTheme: CardTheme(
    color: FathomColors.light.bgElev,
    elevation: 0, // No shadows, use bg-elev color
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: FathomColors.light.line),
    ),
  ),
  
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: FathomColors.light.accent,
      foregroundColor: FathomColors.light.accentInk,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    ),
  ),
  
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: FathomColors.light.bgElev,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: FathomColors.light.line),
    ),
  ),
  
  // ... other component themes
);
```

### Custom Widget Patterns

**Card Pattern**:
```dart
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: colors.bgElev,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: colors.line),
  ),
  child: child,
);
```

**Hero Metric Pattern**:
```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Label', style: theme.textTheme.labelSmall),
    SizedBox(height: 4),
    Text('72', style: theme.textTheme.displayLarge), // Hero number
    SizedBox(height: 2),
    Text('Rationale', style: theme.textTheme.bodySmall),
  ],
);
```

**Pill Badge Pattern**:
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: colors.bgElev,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: colors.line),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: stateColor, // accent, amber, hot
          shape: BoxShape.circle,
        ),
      ),
      SizedBox(width: 6),
      Text(label, style: FathomTextStyles.mono(fontSize: 11)),
    ],
  ),
);
```

---

## Token-to-Flutter Mapping Table

| CSS Token | Flutter Property | Widget Usage |
|-----------|------------------|--------------|
| `--bg` | `FathomColors.bg` | `Scaffold.backgroundColor` |
| `--bg-elev` | `FathomColors.bgElev` | `Card.color`, `Container.decoration.color` |
| `--ink` | `FathomColors.ink` | `TextTheme.headline*.color` |
| `--ink-dim` | `FathomColors.inkDim` | `TextTheme.body*.color` |
| `--ink-faint` | `FathomColors.inkFaint` | `TextTheme.labelSmall.color` |
| `--line` | `FathomColors.line` | `Border.side.color`, `Divider.color` |
| `--accent` | `FathomColors.accent` | `FilledButton.backgroundColor` |
| `--accent-ink` | `FathomColors.accentInk` | `FilledButton.foregroundColor` |
| `--radius-md` | `12.0` | `BorderRadius.circular(12)` |
| `--radius-lg` | `18.0` | `BorderRadius.circular(18)` |
| `--radius-full` | `999.0` | `BorderRadius.circular(999)` |
| `--space-md` | `12.0` | `SizedBox(height: 12)`, `EdgeInsets.all(12)` |
| `--space-lg` | `16.0` | `EdgeInsets.all(16)` |
| `--text-headline-sm` | `textTheme.headlineSmall` | Screen titles |
| `--text-body-md` | `textTheme.bodyMedium` | Card descriptions |
| `--text-label-sm` | `textTheme.labelSmall` | Pill labels |

---

## Screen-by-Screen Mockup Notes

### 1. Today (Home) — `home.html`
**Why This Layout**:
- Readiness score is hero (largest, top): answers "Am I ready today?"
- Sleep + recovery grouped: both inform readiness
- Calorie balance prominent: evening check-in question
- Training load visible: context for readiness decision
- Today's plan below balance: "what should I do" after assessing readiness
- Completed sessions collapsible: not relevant until after workout
- Body HR demoted: interesting but not decision-critical

**Key Changes from Current**:
- Removed "F" brand badge (ego space)
- Removed "Today" chip (redundant)
- Removed sync pill (now status bar indicator)
- Added readiness composite
- Added calorie balance
- Added training load bar
- Tighter spacing, bolder hierarchy

---

### 2. Workouts — `workouts.html`
**Why This Layout**:
- Trend chart at top: athlete immediately sees "am I improving?"
- This week section: quick adherence check
- Session list below: dive into specifics

**Key Changes**:
- Added trend chart (7/14/30d toggle)
- Added week grouping
- Tabs remain (Swim/Run/Strength work well)
- Export buttons elevated in detail view

---

### 3. Recovery (Sleep) — `recovery.html`
**Why This Layout**:
- Last night score is hero (what happened?)
- Contributors explain the score (why that number?)
- Sleep debt shows trend (am I chronically short?)
- Timing chart shows consistency (pattern issues?)
- Recent nights for comparison

**Key Changes**:
- Renamed "Vitals" → "Recovery"
- Added contributors card
- Added sleep debt
- Demoted enable/sync buttons (moved to settings)
- Inline feel survey (not separate card)

---

### 4. Food — `food.html`
**Why This Layout**:
- Balance card is hero (did I eat enough?)
- Week trend shows pattern (training days deficit, rest days surplus)
- Today's meals below: evidence for balance
- Log meal FAB: primary action

**Key Changes**:
- Added balance card (burn vs. intake)
- Added week trend sparkline
- Elevated balance to top
- Kept meal photo grid (works well)

---

### 5. Workout Detail — `workout-detail.html`
**Why This Layout**:
- Session summary at top (distance/time/pace)
- Recovery cost prominent (how much did this cost me?)
- HR zones/charts below: analysis for engaged user
- Export actions in app bar (quick access)

**Key Changes**:
- Elevated recovery cost
- Added "Add to Agon proof" quick action
- Kept detailed analytics (swim/run athletes want this)
- Better visual hierarchy (hero number → supporting charts)

---

### 6. Programs (Agon) — `programs.html`
**Why This Layout**:
- Keep existing design (well-structured)
- Minor: add week view button
- Minor: elevate proof recording CTA

**Key Changes**:
- Minimal (existing design is good)
- Added week adherence view option

---

### 7. Watch & Sync — `watch.html`
**Why This Layout**:
- Sync status at top (why user visits this screen)
- Manual sync button prominent
- Watch details below: connection state, battery
- Advanced collapsed: R11, Gate A for troubleshooting only

**Key Changes**:
- Simplified from dev-focused pairing screen
- Clearer sync status indicators
- Collapsed advanced features

---

### 8. Settings — `settings.html`
**Why This Layout**:
- Profile data at top (weight, BMR for calorie calc)
- Goals next (sleep target, weekly sessions)
- Preferences below (theme, units)
- Advanced at bottom (diagnostics, export cache)

**Key Changes**:
- Consolidated scattered settings
- Added profile section
- Added goals section
- Moved "Advanced tools" from home

---

### 9. Onboarding — `onboarding.html`
**Why This Layout**:
- Welcome screen explains "decision tool" philosophy
- Pairing wizard simplified (scan → connect → done)
- Setup profile (weight, sleep target) before first sync
- Intro to key features (readiness, balance, programs)

**Key Changes**:
- Simplified onboarding flow
- Set expectations: "honest data, no fluff"
- Collect BMR/weight for calorie balance

---

### 10. Empty States — `empty-*.html`
**Why These Designs**:
- Clear illustration (icon, not generic "no data")
- Explanation of why empty (not yet synced vs. no sessions today)
- Primary action (sync, log meal, start program)
- No fake data, no placeholder zeros

**Key Changes**:
- Honest empty states
- Action-oriented CTAs
- Explain next steps

---

### 11. Error States — `error-*.html`
**Why These Designs**:
- Clear error message (sync failed, not paired)
- Reason explanation (watch too far, Bluetooth off)
- Recovery action (retry, check watch, open settings)
- Use hot color for urgency, not decoration

**Key Changes**:
- Human-readable errors (not "R11_HICHAIN3_REQUIRED")
- Suggested fixes before technical details
- Visual distinction (hot color, warning icon)

---

## Implementation Notes for Developers

### When Building Flutter Screens:

1. **Always Read Product & Design Docs First**: Understand the job-to-be-done before coding.

2. **Use `FathomColors.of(context)`**: Never hardcode colors. Always reference tokens.

3. **Use `theme.textTheme.*`**: Never hardcode text styles. Use defined scales.

4. **Follow Card Pattern**: All elevated surfaces use `bgElev` + `line` border, not shadows.

5. **Hero Elements First**: Build screen top-down: hero metric → supporting cards → tertiary details.

6. **Test Dark Mode**: Every screen must work in both themes without manual tweaks (tokens handle it).

7. **Explain Empty States**: If data is missing, say why and what action fills it.

8. **Respect Spacing Grid**: Use 8px multiples. Avoid arbitrary values like `7px` or `13px`.

9. **Minimize Accent Usage**: Accent color means "action" or "positive state". Don't use for decoration.

10. **Widget Names Match HTML IDs**: Reusable components in mockups map 1:1 to Flutter widgets (e.g., `ReadinessCard`, `BalanceCard`, `TrendChart`).

---

## Next Steps

1. ✅ Product review (PRODUCT.md)
2. ✅ Design system documentation (this README)
3. 🚧 HTML mockups (all screens with tokens.css)
4. 🚧 Screenshot each mockup at 390x844 (phone size)
5. 🚧 Create PR with mockups + screenshots
6. ⏳ Developer handoff: map mockups to Flutter screens
7. ⏳ Iterate based on user feedback

---

## Files in This Directory

```
/design/revamp/
├── README.md (this file)
├── PRODUCT.md (user profile, jobs-to-be-done, IA)
├── tokens.css (design tokens as CSS custom properties)
├── index.html (mockup gallery with links to all screens)
├── home.html (Today dashboard)
├── workouts.html (Workout history with tabs)
├── workout-detail.html (Single session detail)
├── recovery.html (Sleep & recovery tab)
├── food.html (Nutrition & calorie balance)
├── programs.html (Agon programs)
├── watch.html (Watch sync & device)
├── settings.html (App settings & profile)
├── onboarding.html (First-run setup)
├── empty-home.html (Home empty state)
├── empty-workouts.html (No sessions empty state)
├── error-sync.html (Sync failed error state)
└── screenshots/ (PNG exports of all mockups at 390x844)
```

---

## Credits

**Design Philosophy**: Inspired by professional athletic training tools (TrainingPeaks, Strava for coaches, Whoop for recovery) rather than consumer fitness apps (Fitbit, MyFitnessPal). The goal is a **strategic instrument**, not a motivational toy.

**Typography**: Manrope (sans) for display, IBM Plex Mono for data. Both open-source, optimized for screen readability.

**Color Palette**: Mint accent (calming, not aggressive), muted neutrals (reduces eye strain for daily checks), semantic colors only where they mean something (not decoration).

**Methodology**: Jobs-to-be-done product thinking → information architecture → visual design system → implementation. This ensures every design decision traces back to user needs, not aesthetic preference.

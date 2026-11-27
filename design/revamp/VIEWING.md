# Viewing the Design Mockups

## Quick Start

Open `index.html` in any modern web browser to explore the mockup gallery.

```bash
# From the repository root:
open design/revamp/index.html

# Or with a local server (recommended):
cd design/revamp
python3 -m http.server 8000
# Then visit: http://localhost:8000
```

## What You'll See

### Interactive Gallery (`index.html`)
- All mockup screens organized by category
- Click any card to view full-screen mockup
- Toggle dark mode with button in top-right
- Links to all documentation (PRODUCT.md, README.md)

### Primary Screens (Fully Designed)
- **Home (`home.html`)**: Today dashboard with readiness score, calorie balance, training load
- **Workouts (`workouts.html`)**: Session history with trend charts, week grouping
- **Food (`food.html`)**: Calorie balance card, 7-day trend, meal log
- **Recovery (`recovery.html`)**: Sleep score, contributors, sleep debt

### Pattern Demos (Placeholder Content)
- Other screens demonstrate layout structure using same token system
- Placeholder screens show: `workout-detail`, `programs`, `watch`, `settings`, `onboarding`
- Empty/error states: `empty-home`, `empty-workouts`, `error-sync`

## Features to Explore

### 🌓 Dark Mode
Click "Toggle Dark Mode" button in gallery to see dark theme. All mockups support both light and dark modes using the same tokens.

### 📐 Phone Frame (390×844px)
All screens are sized to match typical phone viewport. View at 100% zoom for accurate sizing.

### 🎨 Design Tokens
Inspect any mockup to see CSS custom properties in action:
- `var(--bg)`, `var(--bg-elev)` — Backgrounds
- `var(--ink)`, `var(--ink-dim)`, `var(--ink-faint)` — Text hierarchy
- `var(--accent)`, `var(--amber)`, `var(--hot)` — Semantic colors
- `var(--text-display-xl)`, `var(--text-body-md)` — Typography scale

### 📱 Realistic Data
Primary mockups (home, workouts, food, recovery) use realistic sample data:
- Sleep: 8h 15m, score 86
- Workouts: Pool swim 1,800m in 56m, SWOLF 32
- Food: 2,580 kcal intake, 2,340 burned, +240 surplus
- Readiness: 82/100 (ready to train)

## Navigation Between Mockups

### Tab Bar (Bottom)
Click tabs to navigate between main screens:
- 🏠 Today
- 💪 Workouts
- 🌙 Recovery
- 🍽️ Food
- ⋯ More

### Links Within Screens
- Session cards → workout detail
- "Open today's course" → programs
- Sync button → watch screen
- Settings → settings hub

## Viewing on Mobile

Transfer the `/design/revamp/` folder to your phone and open `index.html` in Safari (iOS) or Chrome (Android) to see mockups at actual phone size.

Or visit the deployed version (if hosted):
```
https://your-domain.com/design/revamp/
```

## Browser Compatibility

Mockups work in all modern browsers:
- ✅ Chrome 90+
- ✅ Firefox 88+
- ✅ Safari 14+
- ✅ Edge 90+

Requires CSS custom properties, flexbox, and grid support (all modern browsers).

## Print/Export

To export mockups as PDFs or images:
1. Open mockup in browser
2. Print to PDF (Cmd/Ctrl + P → Save as PDF)
3. Or take screenshots (built-in OS tools)

Screenshots are also available in `screenshots/` folder.

## For Designers

### Editing Tokens
Modify `tokens.css` to adjust:
- Colors (light & dark mode)
- Typography scale
- Spacing grid
- Border radius

All mockups update automatically.

### Creating New Mockups
1. Copy an existing mockup HTML file
2. Update content within `.screen` container
3. Use utility classes from `tokens.css`
4. Follow card pattern: `<div class="card">...</div>`
5. Add link to `index.html` gallery

### Design Tools
- Use browser DevTools to inspect spacing, colors
- Export color palette from `tokens.css` to Figma/Sketch
- Typography: [Manrope](https://fonts.google.com/specimen/Manrope) + [IBM Plex Mono](https://fonts.google.com/specimen/IBM+Plex+Mono)

## For Developers

### Flutter Implementation
See `README.md` section "Flutter Mapping" for:
- Token → `FathomColors` mapping
- `TextTheme` scale
- Component patterns (cards, pills, buttons)
- Widget naming conventions

### Design System
All design decisions documented in:
- `PRODUCT.md` — User needs, jobs-to-be-done, information architecture
- `README.md` — Design system, principles, rationale, implementation notes
- `tokens.css` — Complete token reference

### Handoff Checklist
- [ ] Read `PRODUCT.md` to understand user needs
- [ ] Read `README.md` for design rationale
- [ ] Inspect mockups in browser DevTools
- [ ] Map components to Flutter widgets
- [ ] Use existing `FathomColors` tokens (already in codebase)
- [ ] Test both light & dark themes

## Questions?

- **Product questions**: See `PRODUCT.md` (jobs-to-be-done, screen priorities)
- **Design questions**: See `README.md` (rationale, token usage, patterns)
- **Implementation questions**: See `README.md` → "Flutter Mapping" section

---

**Quick Links**:
- [Product Review](PRODUCT.md)
- [Design System](README.md)
- [Design Tokens](tokens.css)
- [Pull Request](https://github.com/jalakamkiran/fitness_os/pull/22)

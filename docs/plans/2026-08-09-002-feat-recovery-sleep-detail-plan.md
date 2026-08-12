---
title: "feat: Recovery Sleep detail — stages, windowed HR, FileDownload probe"
type: feat
status: completed
date: 2026-08-09
origin: docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md
---

# feat: Recovery Sleep detail — stages, windowed HR, FileDownload probe

## Summary

Rename the bottom **Vitals** tab to **Recovery** with **Vitals | Sleep** subtabs, persist message-path sleep stages through Sync, window continuous HR onto each session (including overnight two-day spans), ship Sleep list/detail with hypnogram + stage mix + HR, add feel-on-wake survey and month history, and run a **non-blocking** TruSleep FileDownload probe after messages so a TruSleep↔HR toggle appears only when enrich is present.

---

## Problem Frame

Sleep sessions today are begin/end list rows only — stages are parsed in `HuaweiFitnessDataSync` then discarded, there is no session detail route, and overnight BPM must be derived by filtering vitals HR series (not workout samples). Owner Excalidraw + locked requirements demand Recovery IA and dual enrich with honesty guards. (see origin: `docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md`)

---

## Requirements

Trace to origin R-IDs:

- R16. Bottom tab Vitals → Recovery; nested Vitals | Sleep; Enable/Sync/whole-day HR stay on Vitals subtab
- R1–R4, R2, R13. Sleep detail: stages (hypnogram + mix) + windowed continuous HR; honest empty; display both when available
- R6, R11. Message stages SoT; sync order messages → HR window → non-blocking FileDownload
- R7. Auto-HR arm + wear guidance for empty HR
- R8, R14. FileDownload probe + side-file/ref; toggle only when enrich present
- R12, R9. Quality score and advanced/breathing metrics deferred / locked chrome
- R15, R18. Feel-on-wake once per session; month history list (charts deferred)
- R5, R10. Home graph-free; privacy (no PPG blobs in repo logs)

**Origin actors:** A1 owner-athlete, A2 GT5-A07, A3 companion Sync  
**Origin flows:** F1 activity Sync sleep path, F2 post-sync enrich + display, F3 feel-on-wake  
**Origin acceptance examples:** AE1–AE5

---

## Scope Boundaries

- No PPG→BPM product SoT; no PPG gallery/viewer this cut
- No inventing sleep Quality score or advanced metrics
- No Home sleep graphs; no Food under Recovery
- No merge of workout HR into sleep window
- Nap/overnight labeling remains display-only per existing vitals rules

### Deferred to Follow-Up Work

- TAG_PPG decode / waveform UI after night capture promotes wire-spec
- Sleep history charts (list first)
- Catalog score promotion for FileDownload rows (needs `capture:…` / `ABSENT-…`)
- Brand IA doc delta for Home|Recovery|Workouts wording (ship shell first; update `docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md` in same or follow-up PR)

---

## Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sync order | Messages+stages → window HR → FileDownload last, non-blocking | Locked honesty guard; AE1 |
| BPM SoT | Window vitals `hr_series` by `[begin,end]` | Continuous HR path; never workout samples (see `docs/learnings/2026-07-22-community-prior-art.md`) |
| Overnight HR | Load **both** local `dayKey`s covering the span, then filter | Repo research: single-day load misses pre-midnight samples |
| Stage persistence | Prefer side-file under no-backup dir (mirror HR series); session prefs keep begin/end + stage ref | Avoid prefs bloat; Forget wipe already has vitals dir hooks |
| FileDownload | New collaborator SM (`0x0a`/`0x2c`), not FeatureUpload `0x28`; sleep owns skeleton (GPS never landed) | Wire-spec stub + catalog R9b |
| Toggle | Only if FileDownload present/ref for session | Locked R14 |
| Recovery nested tabs | SportTabs-style segmented switcher (`sport_tabs.dart` pattern), not a third bottom destination | Matches Workouts sport switcher |
| Detail nav | Named push route + session args (mirror `workout_detail_route.dart`) | Existing companion pattern |

---

## High-Level Technical Design

*This illustrates the intended approach and is directional guidance for review, not implementation specification.*

```mermaid
sequenceDiagram
  participant UI as Recovery Sleep UI
  participant Repo as VitalsRepository
  participant Native as HuaweiFitnessDataSync
  participant FD as FileDownload collaborator
  UI->>Repo: syncFromWatch
  Repo->>Native: sleep msgs then HR containers
  Native-->>Repo: sessions + stages + dailyHr
  Repo->>Repo: merge sessions/stages; window HR later at read
  Repo->>FD: attempt sleep_state/sleep_data if caps
  FD-->>Repo: present|absent + refs (never blocks merge)
  Repo-->>UI: snapshot
  UI->>UI: detail: hypnogram + HR; toggle iff enrich
```

---

## Implementation Units

### U1. Persist sleep stages through Sync merge

**Goal:** Stages survive native → channel → local store so Flutter can render structure.  
**Requirements:** R2, R6  
**Dependencies:** None  
**Files:**
- Modify: `android/app/src/main/kotlin/com/example/fitness_os/huawei/HuaweiFitnessDataSync.kt`
- Modify: `lib/core/huawei/huawei_link.dart` (`SleepSessionSummary` / stage DTO)
- Modify: `lib/features/vitals/data/repositories/vitals_repository_impl.dart`
- Modify: `lib/features/device_pairing/domain/gate_a_prefs.dart` (side-file dir key if needed)
- Test: `android/app/src/test/.../HuaweiFitnessDataSyncTest.kt`
- Test: `test/features/vitals/vitals_repository_test.dart`
- Test: `test/core/huawei/` (DTO round-trip as needed)

**Approach:** After `aggregateSleepSessions`, also emit ordered stage list (timestamp, durationMin, wireType) per session. Persist stages in side-files keyed by session; keep prefs session list lean. Merge must not drop stages on partial sibling containers. Forget Device clears stage dirs with vitals wipe.

**Execution note:** Characterization-first on current aggregate tests before changing payload shape.

**Test scenarios:**
- Happy path: multi-page stages aggregate into sessions **and** stage lists round-trip to Flutter store
- Edge: gap >45 min splits sessions; each keeps its stages
- Edge: session &lt;15 min dropped with stages
- Error: corrupt stage side-file fail-closed without wiping begin/end prefs siblings
- Integration: Sync completedContainers includes sleep; empty stages with empty sessions keeps prior

**Verification:** Native test asserts stages present in maps; Dart load returns stages for a seeded session.

---

### U2. Window continuous HR onto sleep sessions

**Goal:** Pure helper + repository API to load BPM samples in `[begin,end]`, including overnight.  
**Requirements:** R3, R7  
**Dependencies:** None (can parallel U1)  
**Files:**
- Create: `lib/features/vitals/domain/sleep_hr_window.dart` (or under data/ — prefer domain pure fn)
- Modify: `lib/features/vitals/domain/repositories/vitals_repository.dart`
- Modify: `lib/features/vitals/data/repositories/vitals_repository_impl.dart`
- Test: `test/features/vitals/sleep_hr_window_test.dart`
- Test: `test/features/vitals/vitals_repository_test.dart`

**Approach:** Given begin/end unix, compute local dayKeys covering the span; load each `vitals/hr_series/{dayKey}.json`; filter samples; compute min/avg/max. Never read workout HR. Honest empty list when no series / no overlap.

**Test scenarios:**
- Happy path: samples inside window returned; outside excluded
- Edge: overnight sleep spanning two dayKeys merges both files
- Edge: empty or missing day file → empty window, not throw
- Edge: begin==end or inverted range → empty
- Integration: repository method returns same filter as pure helper for seeded prefs+files

**Verification:** Overnight fixture yields pre- and post-midnight points; workout samples never appear.

---

### U3. Recovery shell — rename + Vitals | Sleep subtabs

**Goal:** Bottom label Recovery; host SportTabs-style Vitals | Sleep; move current VitalsScreen body under Vitals.  
**Requirements:** R16, R5, AE5  
**Dependencies:** None (UI shell; can land before detail)  
**Files:**
- Modify: `lib/app/shell/app_shell.dart`
- Modify: `lib/app/shell/app_shell_route.dart` / `lib/app/routing/route_registry.dart` as needed
- Create: `lib/features/vitals/presentation/view/recovery_tab_host.dart` (name flexible)
- Modify: `lib/features/vitals/presentation/view/vitals_screen.dart` (Become Vitals subtab content or split)
- Create: `lib/features/vitals/presentation/view/sleep_tab_screen.dart` (list shell; detail later)
- Modify: `test/app/shell/app_shell_test.dart`
- Test: widget test for Recovery host tab switch

**Approach:** Mirror `lib/features/workout_history/presentation/widgets/sport_tabs.dart`. Home body rules unchanged (no graphs). Placeholder Sleep list can show existing sessions before U4 polish.

**Test scenarios:**
- Happy path: NavigationBar shows Home | Recovery | Workouts
- Happy path: Recovery shows Vitals | Sleep; Enable/Sync visible on Vitals
- Edge: single NavigationBar (no double chrome)
- Covers AE5. Vitals subtab retains Enable/Sync/HR; Sleep hosts list

**Verification:** Shell tests updated; manual tap Recovery → both subtabs.

---

### U4. Sleep detail UI — stages + windowed HR + conditional toggle stub

**Goal:** Session detail route with hypnogram + stage mix + HR line/stats; toggle slot only when enrich flag/ref set.  
**Requirements:** R1–R4, R13–R14, AE2, AE3  
**Dependencies:** U1, U2, U3  
**Files:**
- Create: `lib/features/vitals/presentation/view/sleep_detail_route.dart` (mirror workout detail)
- Create: `lib/features/vitals/presentation/view/sleep_detail_screen.dart`
- Create: charts/widgets under `lib/features/vitals/presentation/widgets/` as needed (`fl_chart` already in app)
- Modify: Sleep list to push detail
- Modify: bloc/state if needed for selected session + HR window + enrich flag
- Test: `test/features/vitals/presentation/sleep_detail_*_test.dart`

**Approach:** Until U6 lands FileDownload, enrich flag is false → no toggle (AE2). When flag true, toggle switches between continuous-HR emphasis and TruSleep-enrich placeholder (file present copy / ACC summary if available — not PPG→BPM). Quality score not shown.

**Test scenarios:**
- Happy path: stages render timeline + mix; HR stats+line when samples exist
- Covers AE2. No enrich → no toggle
- Covers AE3. Enrich present → toggle visible; both modes reachable
- Edge: empty stages / empty HR → honest copy
- Edge: nap vs overnight display labels if wireType/heuristic available

**Verification:** Tap session opens detail; overnight HR matches window helper.

---

### U5. Feel-on-wake survey + month history

**Goal:** Once-per-session emoji survey; historic month list with prev/next arrows.  
**Requirements:** R15, R18, AE4  
**Dependencies:** U3 (Sleep tab), U1 (session keys)  
**Files:**
- Modify: Sleep tab / detail entry surfaces
- Modify: prefs keys in `gate_a_prefs.dart` for survey answers
- Modify: repository load/save survey + month query helper
- Test: survey once-per-key + month filter tests

**Approach:** Survey on first display of newly synced overnight session if unanswered; key = sleep merge key. History: default current month, arrow navigation, scrollable cards reusing today card shape; charts deferred.

**Test scenarios:**
- Covers AE4. First open prompts; second open does not
- Edge: nap can skip survey or share same once-per-key rule (pick one; document in approach — prefer overnight-only)
- Happy path: month arrows change listed sessions
- Edge: empty month → honest empty

**Verification:** Survey persists across app restart; history lists only that month’s sessions.

---

### U6. Non-blocking TruSleep FileDownload probe + enrich refs

**Goal:** After sleep+HR message path, attempt FileDownload; persist present|absent + refs; never block or wipe message results; feed U4 toggle.  
**Requirements:** R8, R11, R10, AE1, R14  
**Dependencies:** U1 (session identity for refs); U4 toggle consumes flag  
**Files:**
- Create: `android/.../huawei/HuaweiFileDownload.kt` (or equivalent collaborator)
- Modify: `HuaweiFitnessDataSync.kt` / `HuaweiSession.kt` / `HuaweiBtPlugin.kt` — exclusive sub-phase after messages
- Modify: Flutter channel + repository for enrich outcome map
- Modify: `docs/wire-specs/huawei-br-gt5-sleep-files.md` — record probe results only with capture ids (no fake score 4)
- Modify: `docs/experiments/gt5-a07-full-metrics-probe-matrix.md` — night budget checklist
- Test: native lock/busy tests; Dart merge keeps sleep when FD fails
- Test: `android/.../HuaweiSyncLockTest.kt` extended as needed

**Approach:** Service `0x2c` if `truSleepNewSync` else `0x0a`. Request `sleep_state` then `sleep_data`. Log tag+len only. Timeout/absent → enrich absent; overall Sync still ok if messages succeeded (AE1). FeatureUpload hard-off. No PPG decode. Owner night wear + tomorrow analysis is the promotion experiment.

**Execution note:** Stub FileDownload behind feature flag or soft-fail until first on-device probe if needed — but API shape must exist for Sync chain.

**Test scenarios:**
- Covers AE1. FD timeout → sessions/stages/HR retained; enrich absent
- Happy path (synthetic): present files → side-file refs + enrich true for matching sessions
- Error: mid-FD disconnect → no wipe of sleep prefs
- Integration: cannot start FD concurrent with workout Sync (single-flight)

**Verification:** Probe matrix row updatable; UI toggle appears only when refs present.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| FileDownload absent on GT5-A07 | Non-blocking; ABSENT after night budget; UI never depends on it |
| Stage type mapping wrong | Ship raw wireType + provisional labels; lock vs Health after night |
| Prefs bloat from stages | Side-files for stage payloads |
| IA churn vs brand doc | Shell ships Recovery; brand requirements doc update deferred follow-up |
| Overnight HR miss | U2 two-dayKey load mandatory test |

---

## System-Wide Impact

- **Shell / IA:** Bottom tab rename; Recovery host; Home|Workouts unchanged
- **Forget Device:** Must wipe stage + FileDownload side-file dirs with vitals
- **Export:** Prefer allowlist new prefs/dirs in app-data export in follow-up if missed this cut
- **Home vitals snapshot:** May still say “Vitals · now” — copy tweak optional, not blocking
- **Catalog / wire-specs:** Scores unchanged until capture cites

---

## Documentation / Experiment Plan

- Visual flow SoT: `docs/brainstorms/Sleep metrics.excalidraw` (locked callouts)
- **Interactive UI SoT (Flutter craft):** `docs/design/recovery-sleep.html` + `docs/design/recovery-sleep.css` — linked from `docs/design/index.html`
- Origin: `docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md`
- Tonight: TruSleep + auto-HR armed wear
- Tomorrow evening: compare Health vs companion (sessions, HR window, FileDownload present|absent) → update sleep-files stub + probe matrix

---

## Design Prototype Spec

*Appended 2026-08-09 from the HTML owner-review prototype. Prefer this + Excalidraw over inventing Flutter layout. Reuse existing phone chrome (`tokens.css`, `home-prototype/styles.css` patterns → Flutter theme / shell).*

### Prototype files

| Path | Role |
|------|------|
| `docs/design/recovery-sleep.html` | Single-file phone + left state rail; vanilla JS `state` + `render()` |
| `docs/design/recovery-sleep.css` | Screen-specific only (subtabs, hypnogram, mix bars, HR chart, survey, rail) |
| `docs/design/tokens.css` | `--bg`, `--ink`, `--accent`, `--amber`, `--hot`, `--up`, fonts, radii |
| `docs/design/home-prototype/styles.css` | `.phone` (~390×844), `.app-header`, `.card`, `.tabbar`, `.seg`, `.btn` |
| `docs/design/index.html` | Hub card **01b · Recovery · Sleep** |

Fonts: Manrope 400–800 + IBM Plex Mono 400/500. Theme: `html[data-theme=light|dark]` via same toggle pattern as vitals-tab / home-states.

### Brand & IA (locked in chrome)

- Product: **Fathom** — calm instrument / analyst tone. Not coach theater, not Huawei Health clone, not medical alarm UI.
- Lettermark **F** only in chrome (never Discobolus athlete).
- Bottom tabs: **Home | Recovery | Workouts** (Recovery replaces Vitals label); Recovery selected on this surface.
- Recovery hosts top segmented switcher: **Vitals | Sleep** (mirror Workouts `sport_tabs` / vitals period seg).
- Graphs live on Sleep detail / history only — never on Home.
- Avoid AI-slop: no purple gradients, glow, emoji-heavy chrome (emoji OK only inside feel-on-wake), no stacked multi-shadow cards, no rounded-full pill spam.

### Screen inventory

| ID | Route intent | Contents |
|----|--------------|----------|
| **S0** | Recovery · Sleep list | Sync pill; today’s sleep card (date, duration, window — **no Quality number**); optional provisional stage chips if stages present; CTA **View more details**; feel-on-wake survey when `surveyShouldShow && !surveyAnswered`; row **View historic sleep data**; locked chrome **Advanced sleep metrics — unlock soon** (no fake metrics). Empty / syncing / failed variants. |
| **S0b** | Recovery · Vitals stub | Thin stub: Enable / Sync / whole-day HR — existing vitals surface; selectable but secondary in prototype. |
| **S1** | Sleep detail (session) | App-header back; date + local window + duration (+ overnight caption); **both** hypnogram + stage mix when stages present; continuous HR min/avg/max + BPM line when `hrPresent`; honesty empties when absent; TruSleep↔Continuous HR toggle **only if** `truSleepEnrichPresent` (hide entirely otherwise — never disabled-grey fake toggle). Prefer display both; toggle is emphasis/mode. TruSleep mode: honest placeholder, not invented PPG BPM. |
| **S2** | History (month) | Month label + prev/next arrows (no custom calendar); scrollable session cards (same card shape as today); empty month; mono **Charts later · list first**. |
| **S3** | Feel-on-wake | Inline on S0 (not a separate modal in prototype): “How do you feel waking up?” + 5 emoji options; answering sets answered and never re-shows for that session. |

### Copy honesty (required strings / tone)

| Situation | Copy |
|-----------|------|
| Empty sleep / empty month | `No sleep sessions stored yet. Wear overnight (prefer night 2 after pairing), then Sync.` |
| Empty HR with stages | `Stages synced. Overnight HR needs auto-HR armed and wear — Sync again after.` |
| Empty HR guidance meta | `wear → Enable auto-HR → Sync` (mono) |
| Stages absent | `No stage blocks for this session. Message-path stages absent — not invented.` |
| FileDownload absent | Do **not** mention PPG. Toggle hidden. |
| FileDownload present (TruSleep mode) | `TruSleep file on device · enrich preview` + mono `PPG decode deferred · not a BPM claim` |
| Advanced locked | `Advanced sleep metrics — unlock soon` + mono `no fake metrics · quality score deferred` |
| Stage chips / mix caption | `stage labels provisional · message path` / `provisional stage mapping · message path SoT` |
| Overnight HR caption | `window crossed midnight · both dayKeys` |
| Instrument meta | Short, factual, mono — e.g. `GT5 · synced… · 7h 12m`, `23:18 → 06:30 · overnight` |

**Hard lock:** never render a Quality score number (not even as demo).

### Visual / chart craft

- **Hypnogram:** horizontal stage blocks; calm colors from tokens — Light=`--ink-dim`, Deep=`--accent`, REM=`--amber`, Awake=`--hot` (sparingly). Mono legend.
- **Stage mix:** simple horizontal bars + duration + % — not a rainbow dashboard.
- **HR line:** single accent stroke + optional area fill (same approach as `vitals-tab.html` HR chart); min/avg/max as one metric row, not three competing cards.
- **Cards:** existing `.card` patterns; fewer cards; no nested card-in-card clutter.
- **One job per section:** list vs detail vs history clearly separated.

### Interaction (prototype ↔ Flutter)

- Tap **View more details** → push Sleep detail (named route + session args).
- Tap **View historic sleep data** → history month list.
- Back on detail/history → Sleep list.
- Theme toggle in header (light/dark tokens).
- Survey pick → persist once per session key; hide survey thereafter.
- Month prev/next → adjacent calendar months (prototype cycles empty → prior-with-rows → current for demos).

### State matrix (UI must support all combinations)

**Navigation:** `screen`: list | detail | history · `recoverySubtab`: vitals | sleep  

**Sync / data:** `syncStatus`: never_synced | syncing | ok | failed · `sessionsPresent`: none | today_only | today_plus_history · `stagesPresent` · `hrPresent` · `overnightSpan` · `truSleepEnrichPresent` · `detailMode`: continuous_hr | trusleep_enrich (meaningful only if enrich present)  

**Survey:** `surveyShouldShow` · `surveyAnswered` (if answered, never show again)  

**History:** `historyMonth`: current | empty_month | prior_with_rows  

**IA:** `showAdvancedLocked` default true · `showQualityScore` **false hard lock**

**Honesty when combining:** if `sessionsPresent=none`, detail/history must not invent a session — show empty copy. Vitals subtab forces list (no detail chrome). Toggle never appears unless enrich present.

### Named review presets (owner click-through)

1. Happy path — stages+HR, no enrich, no survey  
2. First open survey  
3. Stages only (HR absent)  
4. HR only (stages absent) — rare honesty  
5. TruSleep enrich present (toggle on)  
6. Never synced empty  
7. Sync failed keep prior  
8. History empty month  

### Flutter mapping notes

- **U3** → S0 shell + Recovery tab label + Vitals|Sleep seg (Vitals stub / existing vitals body).  
- **U4** → S1 hypnogram + mix + HR + conditional toggle + honesty empties.  
- **U5** → S0 survey + S2 history.  
- Match sibling surfaces: `docs/design/vitals-tab.html`, `docs/design/swim-analytics.html`, Workouts sport tabs.  
- Excalidraw + this section win if older vitals HTML still says bottom tab “Vitals”.

### Out of scope for design (do not ship in UI)

- Live underwater SpO2 / swim hypoxic  
- Real PPG waveform decode art  
- Sleep Quality score  
- Stress / HRV / PAI / emotions under Sleep  
- Food under Recovery  
- Changing Home contents  

---

## Sources & References

- Origin requirements: `docs/brainstorms/2026-08-09-vitals-sleep-detail-stages-hr-requirements.md`
- Visual flow: `docs/brainstorms/Sleep metrics.excalidraw`
- **UI prototype:** `docs/design/recovery-sleep.html`, `docs/design/recovery-sleep.css`
- Sibling craft: `docs/design/vitals-tab.html`, `docs/design/swim-analytics.html`, `docs/design/home-prototype/styles.css`, `docs/design/tokens.css`
- Prior vitals plan: `docs/plans/2026-07-18-004-feat-vitals-sleep-hr-tab-plan.md`
- Wire: `docs/wire-specs/huawei-br-gt5-fitness-data.md`, `docs/wire-specs/huawei-br-gt5-sleep-files.md`
- Catalog: `docs/catalogs/gt5-a07-full-metrics.md`
- Learnings: `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md`, `docs/learnings/2026-07-22-community-prior-art.md`
- Brand IA (to update): `docs/brainstorms/2026-07-25-fathom-companion-brand-ia-requirements.md`

---

## Deferred to Implementation

- Exact stage side-file schema / filenames
- Provisional wireType → label map constants
- Whether survey applies to naps (plan default: overnight-only)
- Whether FileDownload attempt is soft-skipped when caps lack `truSleepNewSync` / file service

---

## Open Questions

_(none blocking — night probe is execution experiment)_

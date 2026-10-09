---
date: 2026-10-09
topic: home-redesign-reward-dopamine-gamification
status: research-complete
type: research
informs: home redesign brainstorm (open-app reward / Agon–Odyssey on Home)
related:
  - docs/brainstorms/research/2026-10-09-programs-gamification-progress.md
  - docs/brainstorms/2026-10-09-pool-swim-programs-requirements.md
---

# Home: what "dopamine reward" research actually supports

## TL;DR for Fathom Home

1. **Dopamine is anticipation + prediction error, not a pleasure dump on badge receipt.** Schultz-style findings (popularized correctly in habit writing): the cue that *predicts* a reward fires dopamine; expected rewards flatline; withheld expected rewards feel bad. So Home must deliver a **reliable, visible competence cue on open** — and must **never blank** during sync (that is a negative prediction error).
2. **The strongest durable motivator is visible progress on meaningful work** ([Amabile Progress Principle](https://hbr.org/2011/05/the-power-of-small-wins)): small wins beat big rare wins. Home should surface *today's inch of Agon progress* (chore done / streak week / XP receipt / Odyssey step), not a vanity "you opened the app" counter.
3. **Self-Determination Theory is the fitness-app evidence base.** Autonomy + competence (+ relatedness where relevant) sustain motivation; controlling rewards and defeat mechanics erode it ([SDT in behaviour-change tech review](https://academic.oup.com/iwc/advance-article/doi/10.1093/iwc/iwae040/7760010); [fitness GDE taxonomy](https://eprints.qut.edu.au/226850/1/102388641.pdf)). CHI 2026 on Duolingo rewards: **informational** rewards ("you mastered X") predict competence; controlling framing does not help autonomy.
4. **Streaks work, then mutate.** Early: relative gain feels big (2→3 = +50%). Later: loss aversion protects the streak ([Duolingo habit blog](https://blog.duolingo.com/how-duolingo-streak-builds-habit/); Silverman et al. on streak motivation). That matches Fathom's existing split: **forgiving weekly habit layer** + **honest capability clock** — do **not** put daily loss-framed streak pressure on Home.
5. **Lottery / variable-ratio core rewards are not clearly better for mHealth engagement** than fixed/predictable ones in recent trials; gain-streak structures build momentum after success. Prefer **predictable progress feedback** on open, with rare celebration moments (proof pass, level-up), not slot-machine Home.
6. **Ethical line:** rewarding *app open* alone is a dark-pattern misalignment with the user's fitness goal ([habit design without dark patterns](https://morphicagency.com.au/blog/habit-forming-app-design-without-dark-patterns)). Reward the *training habit* (sync that lands sessions, chore attempt, weekly streak floor) and make that progress salient.

## Mapping to Fathom's existing game objects

| Object already built / planned | Research job on Home | Avoid |
|---|---|---|
| **Weekly streak + Rest Passes** | Habit identity cue; early momentum; late protection without shame | Daily streak, "streak will die" banners, Habitica-style HP loss |
| **XP / level / Arête–Depth** | Informational competence receipt for showing up / attempting | XP for meters; negative XP; leagues |
| **Odyssey strip** | Narrative small-win path (Progress Principle + story) | Odyssey as the only reason to open if it hides today's chore |
| **Today's chore / next proof** | Meaningful work the small win is *about* | Extra click into Programs before seeing the pull |
| **Sync freshness** | Must succeed quietly so the reward cue isn't withheld | Full-screen blank / "pulling sync data" that erases Home |

## Implication for Home hero (pending product choice)

Research does **not** say "put a dopamine slot machine on Home." It says:

- Make **progress on the program** the first visible win (competence + Progress Principle).
- Keep **habit chrome** (streak / Odyssey / level) glanceable and warm so opening feels like continuity.
- Keep **sync non-destructive** so the predicted reward actually appears.
- Use **charts** only if they are informational competence feedback (e.g. week adherence dots, block progress to proof) — not decorative noise.

A hybrid that research favors over pure vanity reward: **progress reward as emotional pull + today's training as the action** (see brainstorm dialogue).

## Sources (tiered)

**[Study / peer-reviewed]**
- Amabile & Kramer — Progress Principle / small wins (HBR 2011; diary research base).
- Ryan & Deci — Self-Determination Theory (competence, autonomy, relatedness).
- Villalobos-Zúñiga & Cherubini / related GDE fitness work — control + reward + presentation → autonomy/competence in fitness apps ([QUT eprints](https://eprints.qut.edu.au/226850/1/102388641.pdf)).
- SDT in behaviour-change technologies review — Interacting with Computers ([IWC](https://academic.oup.com/iwc/advance-article/doi/10.1093/iwc/iwae040/7760010)).
- CHI 2026 — virtual rewards as informational vs controlling significance (Duolingo) ([ACM](http://dl.acm.org/doi/10.1145/3772318.3791046)).
- Silverman & Barasch — streak motivation / streak-as-goal risk ([JCR](https://academic.oup.com/jcr/article-lookup/doi/10.1093/jcr/ucac029)).
- mHealth reinforcement schedules — fixed vs variable ratio often similar engagement ([MDPI Electronics](https://www.mdpi.com/2079-9292/10/23/2935)); JMIR cadence lottery vs fixed similar ([JMIR Formative](https://formative.jmir.org/2026/1/e86189)).
- Incentive design / gain-streak vs loss-streak path dependence ([BSE working paper](https://events.bse.eu/live/files/6053-cjbsfullpaperpdf)).

**[Official / first-party product]**
- Duolingo — streak habit design, early gain vs late loss aversion ([blog](https://blog.duolingo.com/how-duolingo-streak-builds-habit/)).
- Strava / MySwimPro / Apple Rings — weekly streaks, late-sync restore, pause (summarized in `docs/brainstorms/research/2026-10-09-programs-gamification-progress.md`).

**[Vendor / synthesis — directional only]**
- Habit-loop / dopamine-as-anticipation popularizations; Hooked ethical application notes.

## What this does *not* prove

- That a prettier Home alone raises open rate without a visible win + next action.
- That more charts = more dopamine (charts help only if they mark competence/progress).
- That loss-framed daily streaks are "industry standard" for swimming (they fight rest days; Fathom already chose weekly + forgiveness).

# Handoff: Recovery v1 — timing + Hooper-4 (product review → feature)

**Date:** 2026-08-20  
**Status:** Ready for **product agent review**, then plan / create feature  
**Requirements:** `docs/brainstorms/2026-08-20-recovery-v1-timing-hooper-requirements.md`  
**Survey detail SoT:** `docs/brainstorms/2026-08-13-hooper4-morning-wellness-requirements.md`  
**Survey implement handoff (if still open):** `docs/handoffs/2026-08-13-hooper4-feel-upgrade-handoff.md`  
**Physio POC (complete — evidence only):** `docs/handoffs/2026-08-13-gt5-physio-dict-file-capture-handoff.md`  
**Plan (complete):** `docs/plans/2026-08-13-001-feat-gt5-physio-dict-file-capture-plan.md`

Paste the requirements doc + this handoff into a product-agent chat. Goal of that chat: **review → lock outstanding product questions → `/ce-plan` → create the feature**. Do not reopen overnight companion HRV/SpO₂/RR as in-scope without new capture evidence.

---

## Goal / done means

Ship **Recovery v1** grounded on what GT5-A07 companion can actually own:

1. Overnight **sleep timing** (TruSleep `sleep_state` SoT — largely already shipped)
2. **Hooper-4** morning wellness (sleep quality, fatigue, soreness, stress)
3. **Honest empties** — no companion overnight HRV / RR / sleep SpO₂ / overnight avg HR

**Exit:** Owner Syncs overnight sleep → sees window/duration → completes Hooper-4 once → never sees invented ANS/physio tiles. No opaque recovery score. No intensity coaching.

---

## Why now (one paragraph)

Physio dict/file capture POC is **complete**. Band-10-style overnight summaries do **not** land on GT5 companion paths. Interval HR does not cover last night’s TruSleep window. Waiting for HRV stalls the product; Saw/Hooper evidence supports shipping subjective + sleep quantity as a real daily recovery loop. This cut is that loop.

---

## Product locks (do not reopen unless owner overrides)

| Lock | Rule |
|------|------|
| Data foundation | Timing + Hooper-4 only |
| Overnight HRV / RR / sleep SpO₂ / avg sleep HR | Companion **ABSENT** — watch tiles ≠ Fathom SoT |
| `0x0B ∩ sleep` overnight HR | Do **not** mint |
| Recovery score | No “Recovery 73” |
| Coaching | No hard / easy / rest |
| Health exclusive bind | Out |
| Physio probe branch | Evidence/docs only — not product UI ship branch |

---

## What the product agent must decide

From requirements **Outstanding Questions**:

1. **Morning explanation card?** Owned sleep hours + Hooper summary, **no** score — include in v1, or survey + sleep UI only?
2. **Packaging?** One “Recovery v1” feature PR (Hooper + honesty/copy), or Hooper-4 first then a thin honesty pass?

After those two answers → plan on the **sleep/feel Recovery product branch** (not `feat/gt5-physio-dict-file-capture`).

---

## Suggested review checklist

- [ ] Confirm R10–R13 honesty locks match go-to-market / support language
- [ ] Confirm Hooper-4 dimensions/scale still match owner intent (1–7, four items)
- [ ] Resolve R16 morning explanation card yes/no
- [ ] Resolve one-PR vs sequenced packaging
- [ ] Confirm no accidental reintroduction of sleep continuous-HR charts as overnight SoT
- [ ] Confirm physio debug probe stays debug-only if present in tree
- [ ] Hand to `/ce-plan` with branch strategy explicit

---

## Evidence pointers (do not re-litigate in product review)

| Doc | Use |
|-----|-----|
| `docs/catalogs/gt5-a07-full-metrics.md` | S4 overnight rows → `ABSENT-overnight-summary` |
| `docs/experiments/gt5-a07-full-metrics-probe-matrix.md` | Capture matrix |
| `docs/learnings/2026-08-13-gt5-overnight-physio-capture-research.md` | Science minimum + why dict path was first |
| Capture id | `POC-2026-08-16-physio-probe` |

---

## Explicit non-goals for the feature chat

- Re-running physio dict probes as acceptance for Recovery v1
- Health SDK / exclusive Health companion architecture
- Keepalive 10-min full Sync Health clone
- P4/P5 composites with ANS or training-load join
- Decoding `sleep_data` PPG into fake `avgHrv`

---

## Next step for product agent

1. Read `docs/brainstorms/2026-08-20-recovery-v1-timing-hooper-requirements.md`  
2. Answer the two Resolve Before Planning questions  
3. Update requirements status → `ready-for-plan`  
4. `/ce-plan` → implement on Recovery sleep/feel line  
5. Link this handoff + physio POC complete note in the plan origin

# Fathom — Swim session analytics · Product Head review

**Status: LOCKED (owner 2026-07-25)**  
**Chat:** [Huawei Watch · Product Head](https://chatgpt.com/g/g-p-6a60ffa173a4819192ab40fb9bce162a-huawei-watch/c/6a64a361-f4a8-83e8-8a05-1748108a94c2)  
**Canonical surface:** `docs/design/swim-analytics.html`  
**Hub:** `docs/design/index.html`

## Verdict

| Authority | Result |
|---|---|
| ChatGPT Product Head | **APPROVED WITH CHANGES** |
| Owner | **LOCKED** — satisfied; Flutter may implement against this package |

## Must-fixes (Product Head) — applied in HTML

1. Default-hide garbage laps from P0 / charts / table + **Include filtered laps** toggle  
2. Overlay 0–1 normalized; pace rising = deterioration (no dual-axis ambiguity)  
3. Interval table stays synchronized with the same lap set as charts/P0  

Also in package: diagnoses → allow-listed recommendations → **Run reasoner** (on demand).

## Nice-to-haves (non-blocking)

- Race execution overlay, DPS×rate scatter, HR×pace drift — post-MVP

## Do not reopen without owner unlock

Chart order, invent-guard default, reasoner-on-tap, Home chart-free.

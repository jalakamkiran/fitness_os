# Swim analytics graphs — research digest (2026-07-25)

Sources: MySwimPro analytics guide, FORM Swim post-swim analysis + tips, Garmin/FORM length breakdowns, industry comparisons.

## What best-in-class apps actually chart

| Graph | MySwimPro | FORM | Garmin Connect | Why it helps |
|-------|-----------|------|----------------|--------------|
| **Lap / length splits** (time per length) | Yes | Yes (length table + graph) | Yes | Speed truth; shows fade within a set |
| **SWOLF per length** | Yes | Yes | Yes | Efficiency composite (time + strokes); fatigue detector |
| **Strokes per lap** | Yes | Yes (stroke stats) | Yes | Distance-per-stroke proxy; technique signal |
| **Stroke rate** | Partial / device | Strong | Often | Tempo vs DPS tradeoff (FORM coaching framing) |
| **Heart rate over time** | Yes | Yes (if available) | Yes | Effort / zone truth — demote if samples missing |
| **Set → rep → length drill-down** | Yes | Yes | Yes | Progressive disclosure (not all on Home) |

## Ranked for Fitness OS (power-user pool, LPv2 intervals)

1. **Pace / split by interval (or length)** — primary “did I fade?” chart  
2. **SWOLF by interval** — primary efficiency / fatigue chart  
3. **Stroke count (or rate) by interval** — technique companion to pace  
4. **Dual overlay: pace + SWOLF** — one glance: fast-but-sloppy vs efficient fade  
5. **HR timeline** — only when sample stream present (else hide, don’t fake)

**Home:** at most one session signal chart (pace area) + pool spatial nodes.  
**Session detail:** full chart stack with tooltip intros.  
**Not on Home:** cohort history, multi-year area charts, equal-weight KPI walls.

## Advanced charts (coach-grade)

Beyond the basic stack, TritonWear / FORM / TrainingPeaks add:

| Chart | Source pattern | Fitness OS note |
|-------|----------------|-----------------|
| **DPS × stroke rate scatter** | TritonWear coupling / FORM sweet spot | Best advanced visual if we can derive DPS (distance/strokes) |
| **Pace vs CSS / target band** | Threshold training | Needs a CSS or goal pace input |
| **Stroke index timeline** | Elite composite (speed × DPS) | Great fatigue-under-load signal |
| **Multi-session overlay** | TrainingPeaks workout compare | For test sets only |
| **Session radar / spider** | TritonWear profile | Summary, not primary evidence |
| **UW / turn / overwater phases** | TritonWear IMU | Deferred until GT5 evidence |

Live gallery: `docs/design/home-prototype/advanced.html`

# Huawei BR / LPv2 wire-spec — GT5-A07 TruSleep FileDownload

**Status: DEFERRED**

No Fitness OS observation of `sleep_state.bin` / `sleep_data.bin` on GT5-A07 yet. Night budget not started (`docs/experiments/gt5-a07-full-metrics-probe-matrix.md`).

**Do not** implement FileDownload parsers from this stub. **Do not** mint catalog score **4** for sleep file rows until a capture or documented-absence id is cited below.

---

## Intent (for later promotion)

| Item | Contract sketch |
|------|-----------------|
| Files | `sleep_state` then `sleep_data` |
| Service | `0x2c` if `truSleepNewSync`, else `0x0a` |
| vs FeatureUpload | Distinct SM — FeatureUpload is `0x28` pair-finalize only |
| ACC | ~1/min activity bytes (TAG_ACC) — **not** high-rate IMU (R11) |
| PPG | Compressed TAG_PPG — limited-rate; not raw dump |
| Ownership (R9b) | If U4 never saw GPS, U6 owns FileDownload collaborator skeleton |
| Privacy | Never commit PPG/ACC blobs; lengths + presence only |

---

## Promotion gate

Promote this document from stub → normative when U2 records:

1. File `present` after night budget → cite `capture:…` and fill SS/CC/tag tables, **or**
2. File `absent-in-observed-sessions` after max 2 TruSleep ON nights → cite `ABSENT-…` and keep catalog scores on oracle/claim axis (≤3), observation absent.

Until then: catalog S4 file rows stay score **3** / observation `unobserved`.

---

## Related

- Catalog S4: `docs/catalogs/gt5-a07-full-metrics.md`
- FitnessData messages: `docs/wire-specs/huawei-br-gt5-fitness-data.md`
- Gate A base: `docs/wire-specs/huawei-br-gt5-gate-a.md`

# GT5-A07 companion feasibility (U8)

**Date:** 2026-07-17  
**Device:** Huawei Watch GT5-A07  
**App:** Fitness OS Gate A cut (`feat/huawei-gt5-companion-gate-a`)  
**Secrets:** redacted — do not commit account IDs or auth material

## Recommendation: **PIVOT** (interim)

Gate A transport + framing + pairing UI + reconnect/unlock policy are implemented in-app. **HiChain crypto is not yet clean-room complete** (see wire-spec crypto inventory). On-device authenticated session therefore remains blocked until owner HCI captures unlock challenge→response vectors. Do **not** treat current builds as Gate A passed.

| Gate | Status | Evidence |
|------|--------|----------|
| Gate A transport (U1) | Code complete; on-device smoke pending | Dual-radio FE86→SDP channel |
| Gate A framing (U2) | Complete with public LPv2 docs | `docs/wire-specs/huawei-br-gt5-gate-a.md` |
| Gate A auth (U3) | Fail-closed pending crypto | Session sends link-params; auth_failed + R11 hints |
| Gate A UI / reconnect / unlock (U4–U6) | Code complete | Unit tests for AE1/AE2/AE5 prefs contracts |
| Gate B (U7) | Not started | Blocked until `gate_a_passed` on-device |
| R12 | Interim **PIVOT** | Resume after HCI capture → complete crypto inventory → re-run AE1–AE4 |

## R11 recovery (AE7)

Winning path on-device: **pending** (no successful Fitness OS auth yet).

Record when known:

- [ ] no-vendor pair (no account ID)
- [ ] account ID (17-digit `userId`) — value **not** stored in this doc
- [ ] factory reset / unlink then first-time pair

## Auth mode observed

Pending HCI: HiChain / HiChain Lite / Normal — see capture notes.

## Interrupt matrix

See `docs/experiments/gate-a-interrupt-matrix.md` (pending on-device fill).

## HCI capture inventory

See `docs/experiments/2026-07-17-hci-capture-notes.md`. Raw snoops stay off-repo.

## Next actions to flip PIVOT → GO/STOP

1. Capture short labeled `gb_pair` / `fos_pair` HCI sessions; redact fixtures into `test/fixtures/huawei/`
2. Complete clean-room crypto inventory (or STOP if only AGPL paste would unlock it)
3. Re-run AE1–AE4; credit U6 checklist only on authenticated reconnects
4. Optionally start U7 after `gate_a_passed`

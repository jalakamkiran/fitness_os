# HCI capture notes — Huawei GT5-A07 Gate A

**Date:** 2026-07-17  
**Device:** Huawei Watch GT5-A07  
**Phone:** (owner — fill)  
**Status:** Captures pending on-device

Raw Bluetooth HCI snoops stay **off-repo**. Commit only redacted notes and redacted binary fixtures under `test/fixtures/huawei/`. Enable snoop only for short labeled sessions, then disable — captures may include non-Huawei traffic.

Reference: [Gadgetbridge Bluetooth HCI snoop guide](https://gadgetbridge.org/internals/development/bluetooth/).

---

## Capture inventory

| Label | Purpose | Precondition | Local path (off-repo) | Redacted fixture / notes | Auth branch seen | Status |
|-------|---------|--------------|------------------------|---------------------------|------------------|--------|
| `gb_pair` | First-pair oracle (GB) | Health stopped; GB pairing | | | HiChain / Lite / Normal / unknown | **pending** |
| `gb_reconnect` | Reconnect oracle (GB) | After successful `gb_pair` | | | | **pending** |
| `fos_pair` | Fitness OS first pair | Health + GB stopped; FOS build | | | | **pending** |
| `fos_reconnect` | Fitness OS reconnect | After FOS pair + secrets | | | | **pending** |
| `fos_auth_fail` | Fail-closed / R11 path | Deliberate missing key | | | | **pending** |

Add rows as needed (`fos_bt_toggle`, `fos_post_reboot`, …).

---

## Session checklist (each capture)

1. Label the session before enabling snoop (`gb_pair`, …).
2. Force-stop Huawei Health; for FOS tests also force-stop Gadgetbridge.
3. Record watch firmware string and phone Android / BT stack version.
4. Keep session short; disable snoop immediately after.
5. Extract only Huawei SDP / LPv2 frames for redaction; strip MACs / account material from committed notes.
6. Never commit: full btsnoop logs, Health account IDs, raw bonding keys.

---

## Redaction rules

- Replace phone/watch MACs with `AA:BB:CC:DD:EE:FF`-style placeholders in notes.
- Mask any 17-digit `userId` as `***************`.
- Prefer hex excerpts of framing/auth TLVs in this file or under `test/fixtures/huawei/` — no full session dumps in git.

---

## Observed auth branch (fill after `gb_pair`)

| Field | Value |
|-------|--------|
| Link-params response hints | *pending* |
| Branch taken | **pending owner HCI capture** |
| Optional `userId` required? | *pending* |
| Winning R11 recovery path | *pending* |

---

## Crypto fixture targets (post-capture)

Once captures exist, add redacted vectors for:

1. Link-params request/response (complete).
2. At least one challenge → response pair for the observed branch.
3. First post-auth bonded command (optional).

Until then: framing unit tests use **synthetic** hex only; U3 auth fails closed.

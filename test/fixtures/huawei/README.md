# Huawei fixtures

Owner-captured or redacted LPv2 frames for Fitness OS tests.

## Rules

- Fixtures must be **owner-captured** (HCI / on-device) or **synthetic** (hand-crafted for framing tests).
- **Never** extract golden bytes from Gadgetbridge jars or AGPL sources.
- Raw HCI snoops (`.log`, btsnoop, full pcaps) stay **off-repo**.
- Redact MACs, account `userId`, and key material before committing.
- Prefer documenting synthetic vectors as hex inside Android unit tests when a binary file is unnecessary.

## Layout

| Path | Purpose |
|------|---------|
| `*.bin` | Optional redacted/synthetic frame bytes |
| Companion notes | `docs/experiments/2026-07-17-hci-capture-notes.md` |

Framing round-trips currently use hex in `HuaweiFramingTest` (synthetic, owner-style — not from GB).

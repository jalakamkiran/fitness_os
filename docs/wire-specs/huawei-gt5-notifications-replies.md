# Huawei GT5 — Notifications service `0x02` and reply events

Fitness OS clean-room wire-spec for on-watch notification push and quick-reply capture during strength sessions.

**Sources (public / behavioral only):**

- Public LPv2 wire docs and community LPv2 captures (notification TLV shapes, reply cmd `0x10`)
- Existing Gate A framing: `docs/wire-specs/huawei-br-gt5-gate-a.md`
- **No AGPL source.** Gadgetbridge is reference-only for capability bit indices and P2P module names.

---

## Transport

All frames use `HuaweiFraming` (TLV, slicing) and post-bind `HuaweiPacketCrypto` session encryption (`0x7C` / `0x7D` / `0x7E`). Outbound: `sendEncryptedNoWait`. Inbound async dispatch: `publishFrame` (frames not awaited are dropped elsewhere).

Service **Notifications** = `0x02`.

| Cmd | Direction | Role |
|-----|-----------|------|
| `0x01` | Phone → watch | Send notification |
| `0x02` | Phone → watch | Constraints request |
| `0x04` | Phone → watch | Notification master switches (`0x81` → `0x02`/`0x03` enable) |
| `0x05` | Phone → watch | Capabilities request (`0x01` empty) |
| `0x06` | Phone → watch | Remove notification |
| `0x08` | Phone → watch | Wear message push (`0x01` = `0x00` when push enabled) |
| `0x10` | Watch → phone | Reply event (phone ACKs `0x07`) |
| `0x07` | Watch → phone | Possible dismiss/read (log for ack-only path) |

---

## ExpandCapability bits (DeviceConfig `0x01:0x37`, tag `0x01` bitmap)

| Bit | Meaning for lift |
|-----|------------------|
| 73 | Notification reply actions (watch emits reply events) |
| 77 | Notification carries timestamp tag `0x15` |
| 82 | Canned replies configurable via P2P module `hw.unitedevice.smsquick` |
| 89 | Send reply key string tag `0x18` on notify |
| 94 | Keyed notifications (`0x19` / `0x1A` / `0x1B`) |
| 120 | Remove single notification (`0x06`) |

Probe `0x02` supported commands via DeviceConfig `0x01:0x03`. When lift flag is on, probe includes `0x02` constraints and `0x10` reply.

---

## GT5 hardware finding (0.1.0+28)

Direct bond **without Huawei Health** paired first: ExpandCapability bits looked fine, but every `0x02:0x01` send was answered with TLV `0x7F` **error 4** and **no wrist notification**. Capabilities dump showed **`svc02Commands: []`** — notification service was never configured on the link.

Interpretation (behavioral oracle, not AGPL): error **4** on send usually means notifications are disabled at the protocol/wear layer (master switch off, wear-message-push off, DND, or **source package not on the Health per-app allowlist**). Huawei Health’s “which apps notify the watch” list is **not** a separate Fathom API today; users must allow packages in Health **or** we pick a commonly allowed `0x11` package (e.g. `com.google.android.apps.messaging` for SMS-shaped tests).

---

## Enable sequence (Fathom, after auth, `FATHOM_LIFT_WATCH`)

Run once per session (auto) or from **Lift watch debug → Enable watch notifications**:

1. Re-probe supported commands for svc `0x02` (adds `0x02`, `0x10` to probe map).
2. `0x02:0x05` notification capabilities (tag `0x01` empty).
3. `0x02:0x02` constraints (tag `0x01` empty) — cache body max length.
4. `0x02:0x04` notification state **on** — nested `0x81` with tags `0x02` and `0x03` = `0x01`.
5. `0x02:0x08` wear message push **on** — tag `0x01` = `0x00` (inverted boolean on wire).
6. `0x01:0x21` DeviceConfig default-switch query (tag `0x01` empty) — log TLVs for future allowlist work.

Each step logs request/response TLV hex on the debug screen (`lift_enable_step` events).

---

## Result TLV `0x7F`

Many svc `0x02` responses echo `0x7F`:

| Code | Meaning (Fathom) |
|------|------------------|
| `0` / `100000` | Success |
| `4` | Send rejected — notify path disabled or package not allowlisted |
| `100004` | System busy |

On `0x7F` after a send, Fathom logs `lift_notify_error` with **decoded label**, **full request TLVs**, and response hex.

---

## Constraints `0x02:0x02`

Request: TLV `0x01` empty.

Response: nested `0x81 > 0x82 > 0x90 > (repeated 0x91)`. Each `0x91`: `0x12` kind, `0x13` format, `0x14` max length (u16 BE). Kind `0x01` = body content → **max UTF-8 body length** (truncate minus 3 for ellipsis).

---

## Send notification `0x02:0x01`

TLV order:

1. `0x01` — message id (u16 BE); Fathom counter from `0x4C00`
2. `0x02` — type byte (`0x7F` generic; debug may try `0x02` SMS)
3. `0x03` — vibrate `0x01`
4. `0x84 > 0x8C > 0x8D*` — text elements: `0x0E` type (`0x03` title, `0x02` sender, `0x01` body), `0x0F` encoding (from constraints, default `0x02`), `0x10` UTF-8 text
5. `0x11` — source app id `com.example.fitness_os`
6. If bit 89: `0x18` reply key `lift:<sessionId>:<setIndex>` (≤64 chars)
7. If bit 77: `0x15` u32 unix seconds
8. If bit 94 or 120: `0x19` key, `0x1A` notification id (u32), `0x1B` channel `fathom_lift`

**Source app id (`0x11`):** use `com.example.fitness_os` for Fathom-branded tests, or `com.google.android.apps.messaging` when probing SMS type `0x02` if Health has Messages allowed.

### Plain test send (debug)

`0x02:0x01` with only `0x01` msgId, `0x02` type (`0x01`/`0x7F`/`0x02`), `0x84` title+body, `0x11` package — **no** `0x03` vibrate, reply key, or keyed tags. Used to separate “notify disabled” from “reply TLV rejected”.

---

## Remove `0x02:0x06` (bit 120)

`0x01` type, `0x02` app id, `0x03` key, `0x04` id u32, `0x05` channel, optional `0x06` category.

---

## Reply event `0x02:0x10` (watch → phone)

| Tag | Field |
|-----|-------|
| `0x01` | Reply type (`2` = by notification key) |
| `0x02` | Encoding (`3` = UTF-16 body) |
| `0x03` | Subscription id |
| `0x04` | Key string |
| `0x05` | Extra data |
| `0x06` | Reply text |

Phone ACK: same cmd `0x10`, TLV `0x07` result (`0x00` success). Do not ACK on decrypt failure.

---

## P2P quick replies (svc `0x34`, cmd `0x01`)

Module `hw.unitedevice.smsquick`. Payload TLV: `0x01` command int (`7001` query, `7002` update). Update: `0x82 > 0x83 > 0x04` per reply string.

Fathom canned replies (≤5): `Done`, `-1 rep`, `-2 reps`, `+2.5 kg`, `Failed`.

---

## Phase 0 decision table

| Observation | Path |
|-------------|------|
| Reply `0x02:0x10` with text | **A: full MVP** (`LiftCaptureMode.reply`) |
| Dismiss/read on svc `0x02`, no reply UI | **B: ack-only** (`LiftCaptureMode.ackOnly`) |
| Notification shows, nothing returns | **C: STOP** — planner follow-up |
| Notification does not show during workout | **STOP** |

Owner validates on GT5 with `FATHOM_LIFT_WATCH=true` debug build (see PR test script).
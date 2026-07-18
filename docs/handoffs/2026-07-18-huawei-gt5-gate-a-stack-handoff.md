# Handoff: Huawei GT5-A07 Gate A communication stack

**Date:** 2026-07-18  
**Device:** Huawei Watch GT 5-A07 (HarmonyOS / VLI-B19)  
**Phone:** Pixel 8a (Android)  
**Branch context:** `feat/huawei-gt5-companion-gate-a`  
**Status:** Gate A first-pair + reconnect proven. Gate B Count→Totals proven on-device (2026-07-18 strength session → list row). `gate_a_passed` unlocked by owner.

**Full POC learning doc (flowcharts + achievements):** `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md`

---

## 1. What “done” means

| Signal | Meaning |
|--------|---------|
| Android BT “connected” | Classic RFCOMM only — **not** Gate A |
| App `session_ready` / `LinkState.gateAIncomplete` | HiChain3 bind + encrypted configure finished on the phone |
| **Watch pairing UI clears** | Real pair success (Gate A product bar for first pair) |
| `gate_a_passed=true` | Owner checklist after kill + reboot + BT-toggle reconnects |

Gadgetbridge is a **behavioral oracle only** (local study tree `_study_gadgetbridge`, Codeberg master). Do not paste AGPL. Implement from this handoff + `docs/wire-specs/huawei-br-gt5-gate-a.md`.

---

## 2. Stack architecture (how layers are built)

```text
┌─────────────────────────────────────────────────────────────┐
│ Flutter UI — features/device_pairing (BLoC)                 │
│  scan / select / auth-key / Forget / Gate A checklist       │
└────────────────────────────┬────────────────────────────────┘
                             │ HuaweiLink (lib/core/huawei/)
                             │ LinkState machine + prefs identity
┌────────────────────────────▼────────────────────────────────┐
│ MethodChannel + EventChannel — HuaweiBtChannel / Plugin     │
│  startBleDiscovery, connect, authenticate, setAuthKey, …    │
└────────────────────────────┬────────────────────────────────┘
                             │ Kotlin native (android/.../huawei/)
┌────────────────────────────▼────────────────────────────────┐
│ RfcommTransport                                             │
│  BLE FE86 discover → cancelDiscovery → Classic SDP RFCOMM   │
│  duplex byte stream + generation-guarded connect            │
├─────────────────────────────────────────────────────────────┤
│ HuaweiFraming                                               │
│  0x5A packets, TLV/VarInt, CRC-16/XMODEM, slice reassembly  │
├─────────────────────────────────────────────────────────────┤
│ HuaweiSession                                               │
│  auth orchestration + post-bind configure + async handlers  │
├──────────────┬──────────────────┬───────────────────────────┤
│ HuaweiHiChain│ HuaweiPacketCrypto│ HuaweiFeatureUpload      │
│ ISO 0x28     │ AES-GCM 7C/7D/7E  │ DataSync + FileUpload 0x28│
├──────────────┴──────────────────┴───────────────────────────┤
│ HuaweiSecretStore — EncryptedSharedPreferences (auth key,   │
│   phone MAC override for privacy-MAC phones)                │
└─────────────────────────────────────────────────────────────┘
```

### Layer responsibilities

| Layer | Owns | Must not own |
|-------|------|----------------|
| Dart `HuaweiLink` | LinkState, scan/connect UX sequencing, remembered MAC/name, Gate A bits | Crypto, framing, RFCOMM |
| `HuaweiBtPlugin` | Permissions, channel bridge, session lifetime on socket | Protocol decisions |
| `RfcommTransport` | BLE filter, SDP UUID connect, read loop → session | Auth TLVs |
| `HuaweiFraming` | Encode/parse packets | Business meaning of SS/CC |
| `HuaweiSession` | Ordered wire dialogue + async multiplex | Flutter prefs |
| `HuaweiHiChain` | Clean-room HiChain3 ISO JSON + HKDF/AES-GCM | AGPL ports |
| `HuaweiFeatureUpload` | Features file SM after DataSync action=2 | Other DataSync modules |

---

## 3. End-to-end communication flow

### 3.1 Discovery → transport

1. BLE scan: advertise UUID `0000FE86-…` and/or name contains `huawei` + `gt 5`.
2. Stop BLE; `cancelDiscovery`.
3. Classic `createRfcommSocketToServiceRecord(82FF3820-8411-400C-B85A-55BDB32CF060)`.
4. Secure RFCOMM duplex; all LPv2 frames on this socket.

**Pixel privacy MAC:** adapter address may be `02:00:00:00:00:00`. Store a real phone MAC override in `HuaweiSecretStore` (entered with auth key) or HiChain/security-nego fails with opaque errors.

### 3.2 Auth (GT5-A07 = HiChain3)

Mode selector is link-params tag **`0x07` = deviceSupportType**, not ServerNonce.

| Tag / field | Observed | Meaning |
|-------------|----------|---------|
| `t=7:04` | Always on this watch | HiChain3 |
| ServerNonce | V1 crypto version | Not “use Normal auth” |
| Normal `0x13` | Returns `100004` | Wrong branch — watch UI “pairing failed” while BT still connected |

**HiChain3 sequence:**

```text
link-params 0x01:0x01
  → device-status 0x01:0x16
  → security-nego 0x01:0x33 (authMode=4)
  → PIN 0x01:0x2C
  → HiChain ISO 0x01:0x28  op=1 (authenticate) then op=2 (bind)
  → session key 32B, AES-GCM (supportType=4)
```

Confirm on watch if prompted (`r11_confirm_on_watch`). Bind result step numbering matters (skip-step uses message id `0x13`, not `0x14`).

### 3.3 Post-bind configure (encrypted)

After bind, Fitness OS runs a GB-shaped configure (mask/cmd gated). Working order on GT5-A07:

```text
product-info          0x01:0x07
set-time              0x01:0x05
battery               0x01:0x08
supported-services    0x01:0x02
supported-commands    0x01:0x03   (batched; see known bug §5)
timezone-id           0x01:0x32
expand-capability     0x01:0x37   (DeviceConfig — NOT DataSync)
extended-account      0x1A:0x05   (empty account t=1:00; optional pair-opt t=3:01)
setting-related       0x01:0x31
locale                0x0C:0x01
date-format           0x01:0x04
setup-device-status   0x01:0x3E   (fire-and-forget; watch name)
accept-agreement      0x01:0x30
reverse-capabilities  0x01:0x3F
connect-status        0x01:0x35
music-info            0x25:0x04
music-extended        0x25:0x0D
country-code          0x1A:0x0A   (late — matches GB master)
```

Then emit `session_ready` → Dart `LinkState.gateAIncomplete` until checklist unlock.

### 3.4 Async finalize (watch-driven, concurrent with configure)

These arrive on the same RFCOMM while configure waits. Session must **skip unrelated frames** when awaiting a specific SS/CC.

| Inbound | Required phone behavior |
|---------|-------------------------|
| PhoneInfo `0x01:0x10` empty-tag probe | Reply with phone fields (incl. app-version tag `0x11`); watch ACKs `t=7f:000186A0` |
| DataSync `0x37` `featureManager` configAction=**2** | ConfigCommand `"01"` (configId `900100007`) then **FileUpload** — not bare OK |
| FileUpload `0x28` | info → hash → consult → chunk(s) → result → complete → DataSync action=**1** notify |
| P2P `0x34:0x01` cmdId 1/2 | Ack cmdId=3 + int `0xca` in tag `0x08` |
| Music `0x25:0x01` / real `0x25:0x03` | ACK only (do not flood on decrypt failure) |
| Other DataSync modules | **Ignore** (golf, emotion, wechat, remindText, …) |

**FeatureUpload deferral:** start FileUpload only after Extended Account has been attempted (GB registers FeatureManager early but account comes first in dynamic init).

---

## 4. Easy-to-confuse IDs

| Wire | Meaning |
|------|---------|
| `svc=0x01` cmd `0x37` | ExpandCapability (DeviceConfig) |
| `svc=0x37` | DataSync / UniteDevice |
| `svc=0x01` cmd `0x28` | HiChain ISO |
| `svc=0x28` | FileUpload (post-bind features file) |
| `svc=0x25` cmd `0x03` | MusicControl |
| `svc=0x1A` | AccountRelated (extended account + country) |

---

## 5. Hard-won learnings (anti-patterns)

| Failure mode | Root cause | Fix |
|--------------|------------|-----|
| Watch “pairing failed”, BT still connected | Normal auth on HiChain3 watch | Branch on `t=7:04` → HiChain3 |
| Bind hangs / timeout | Wrong bind result message step; unrelated `0x25` frames block wait | Correct step id; `awaitFrame` skip others |
| `session_ready` but watch UI fails | Configure incomplete (missing PhoneInfo / FeatureManager / account / …) | Full dynamic-init-shaped configure + async |
| GCM MAC fail after music-params OK | Blanket DataSync `t=7f:100000` | Never blanket-ACK DataSync |
| FeatureManager handshake alone | Watch retries then tears down session | FileUpload `feature_<CC>_device.txt` + action=1 notify |
| FeatureUpload OK, UI still fails | Missing Extended Account / SettingRelated / ReverseCapabilities / SupportedCommands | Send GB-ordered steps |
| Privacy MAC / HiChain weirdness | Pixel `02:00:00:00:00:00` | Phone MAC override in secret store |
| Music decrypt fail late | Usually **session already poisoned** — not wrong HiChain key | Fix prior DataSync/account path |

### Known code quirk (non-blocking)

Log line `supported-commands ok services=0` can appear even when the watch returns a full `t=81` payload. Response nesting uses a command-bitmap tag shape our parser does not fully merge (`0x04` vs expected `0x03` pairs). Fallback: when the map is empty, Extended Account still runs if svc `0x1A` is in the services mask. **Fix later** — reconnect still succeeds.

Country Code may log `no country-code response` on reconnect when the socket is busy with DataSync/FileUpload; soft-continue is OK if first-pair already set region.

---

## 6. Source file map

### Native (`android/app/src/main/kotlin/com/example/fitness_os/huawei/`)

| File | Role |
|------|------|
| `HuaweiBtPlugin.kt` | Flutter Method/Event channel |
| `RfcommTransport.kt` | BLE + Classic SDP + read loop |
| `HuaweiFraming.kt` | Packet/TLV/CRC/slice |
| `HuaweiSession.kt` | Auth + configure + async multiplex |
| `HuaweiHiChain.kt` | HiChain3 ISO exchange |
| `HuaweiNormalAuth.kt` | Normal LPv2 (wrong for this GT5; keep for other modes) |
| `HuaweiPacketCrypto.kt` | Session AES-GCM/CBC, IV, encryptRaw for chunks |
| `HuaweiFeatureUpload.kt` | Features FileUpload state machine |
| `HuaweiSecretStore.kt` | Auth key + phone MAC override |

### Dart

| File | Role |
|------|------|
| `lib/core/huawei/huawei_link.dart` | LinkState + reconnect |
| `lib/core/huawei/huawei_bt_channel.dart` | Channel API |
| `lib/features/device_pairing/…` | Pairing UI + Gate A checklist |

### Docs

| Doc | Role |
|-----|------|
| `docs/wire-specs/huawei-br-gt5-gate-a.md` | Owned wire facts (normative for implement) |
| `docs/experiments/gt5-a07-companion-feasibility.md` | On-device GO/PIVOT evidence |
| `docs/plans/2026-07-17-001-feat-huawei-gt5-companion-mvp-plan.md` | Product plan (Gate A/B) |
| `docs/plans/2026-07-18-001-feat-gadgetbridge-gt5-code-map-plan.md` | GB study-map plan (docs-only) |
| Sibling `_study_gadgetbridge` | AGPL oracle checkout — **outside** this repo |

---

## 7. Log cheat-sheet (success path)

```text
discovery HIT … GT 5-A07
RFCOMM connected
link-params ok … supportType=4(HiChain3)
security-nego ok
HiChain authenticate complete
HiChain bind complete
session crypto on keyLen=32 gcm=true
post-bind: product-info / set-time / battery / supported-services ok
post-bind: supported-commands ok
post-bind: extended-account ok
post-bind: setting-related ok
post-bind: reverse-capabilities ok
post-bind: music-*-ok
feature-upload start … action=1 notify
authenticate → Ready
session_state=session_ready
```

Reconnect (remembered):

```text
remembered=true
reconnect mac=…
reconnect auth outcome=Ready
```

---

## 8. Gate B — Workout sync (added 2026-07-18)

GB oracle path (behavioral): `0x17:0x07` Count → per-id `0x17:0x08` Totals. Data/Pace/Swim/GPS deferred. List needs type (`0x14`), start/end (`0x04`/`0x05`), duration (`0x12`).

Fitness OS:

| Piece | Role |
|-------|------|
| `WorkoutSync.kt` | Count→Totals parse + DTO maps |
| `HuaweiSession.syncWorkouts` | Encrypted exchange after session ready |
| Channel `syncWorkouts` | `{startUnix,endUnix}` → `{status,workouts}` |
| `workout_history` feature | Gate check, persist JSON, offline list, Sync CTA |

Sync stays blocked until `gate_a_passed`. See wire-spec Gate B section.

## 9. Next work for the incoming agent

1. **Gate A unlock (U6):** Owner completes kill / reboot / BT-toggle checklist → `gate_a_passed` (required before Sync works).
2. **Gate B enrichment (optional):** WorkoutData / Pace / Swim / GPS — list path is done.
3. **SupportedCommands parser:** Parse watch response bitmap tags so `acct05/06` gates are real.
4. **Country on reconnect:** Don’t block `session_ready` on late Country timeout; optionally fire-and-forget.
5. **Study-map package** (`docs/study-maps/gadgetbridge-huawei-gt5/`): still planned docs-only.

---

## 10. Clean-room rules (carry forward)

- GB / `_study_gadgetbridge` = behavioral oracle (class names, SS/CC, order). No method-body paste.
- Normative implement source = this handoff + owned wire-spec + owner HCI notes.
- Never commit auth keys, phone MAC secrets, or raw HCI pcaps.
- Prefer logging redaction already used (`FOS_HUAWEI`, MAC `••:••:••`).

---

## 11. Quick retest recipe

1. Forget watch in Android BT + in-app Forget (or use remembered path for reconnect).
2. Enter auth key + phone MAC override if needed.
3. Scan → select GT5 → confirm on watch.
4. Success = **watch pairing UI clears** + logs reach FeatureUpload notify + `session_ready`.
5. Kill app → relaunch → auto-reconnect → `reconnect auth outcome=Ready`.

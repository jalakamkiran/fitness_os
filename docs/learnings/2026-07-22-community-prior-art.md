# Community prior art: Huawei GT / GT5 / LPv2 companion

**Date:** 2026-07-22  
**Scope:** Workout sync enrichment, TLV framing, vitals/HR series, pool swim (SWOLF/laps).  
**Constraint:** Gadgetbridge = behavioral oracle only; no AGPL paste.

## Sources (independent of GB code)

| Resource | Link | License / role |
|----------|------|----------------|
| Easterhegg 2019 (SBA Research) | [slides PDF](https://www.sba-research.org/wp-content/uploads/2019/04/easterhegg19.pdf), [talk](https://media.ccc.de/v/eh19-186-all-your-fitness-data-belongs-to-you-reverse-engineering-the-huawei-health-android-app) | Academic; first public LPv2 handshake + TLV examples (svc 0x01 cmd 0x01 link params) |
| `huawei-lpv2` | [wiki Wire protocol](https://github.com/zyv/huawei-lpv2/wiki/Wire-protocol), [protocol.py](https://github.com/zyv/huawei-lpv2/blob/master/huawei/protocol.py) | **MIT** — 0x5A framing, CRC-CCITT, VarInt TLV, nested tags (MSB), slice flags 0x1–0x3 |
| psolyca RE gist (Honor Band 4 era) | [Honor Band 4 RE](https://gist.github.com/psolyca/68fdfee0960737c1234f8d7f7a6c143a) | Notes LPv2/LPv3 coexistence; 4-step bond handshake (svc1 cmd 1/19/15/14); AES + nonce IV rules |
| D2Explorer / vendor lock-in writeup | [bdteo.com](https://bdteo.com/huawei-watch-d2-proprietary-protocol-vendor-lockin/) | C++ LPv2 on Linux/macOS; cites parallel RE (Easterhegg, huawei-lpv2, Gadgetbridge) |
| Stack Overflow (Watch GT) | [64659988](https://stackoverflow.com/questions/64659988/how-to-read-a-bmp-packet-from-huawei-watch-gt-dee-by-gatttool) | Standard GATT HR (0x180d) absent; Health app uses Huawei-specific characteristics |
| Huawei Health Kit (official, cloud) | [exercise sequence](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/health-exercisesequence-manage-V5), [watch sampling](https://developer.huawei.com/consumer/en/doc/hmscore-guides/obtain-smart-watch-data-0000001365189921) | Documents **post-sync** models (HR/speed/altitude time series); not LPv2 wire format |

## What others observed

- **Transport:** BLE custom GATT + (on GT-class) Classic RFCOMM; no usable standard HR/workout GATT. App-level crypto after HiChain-style bond ([Easterhegg](https://media.ccc.de/v/eh19-186-all-your-fitness-data-belongs-to-you-reverse-engineering-the-huawei-health-android-app), [gist](https://gist.github.com/psolyca/68fdfee0960737c1234f8d7f7a6c143a)).
- **TLV framing:** Body = `service_id | command_id | TLV*`. Tags use VarInt length; tag bit7 = nested command. Outer packet: magic, length, CRC ([wiki](https://github.com/zyv/huawei-lpv2/wiki/Wire-protocol)).
- **Large payloads:** Sliced packets reassemble SLICE-BODY; only first slice carries SS/CC. Multi-package lower-level fragmentation also noted; **huawei-lpv2 author: library historically single non-sliced only** ([issue #11](https://github.com/zyv/huawei-lpv2/issues/11)).
- **Workout sync (behavioral, GB docs):** Huawei syncs all workouts since last full sync; activity vs workout sync mutually excluded; raw blobs kept for later reparse. Per-type fields include HR, speed, cadence, GPS, cycling power; swim **per-segment** pace table columns: style, distance, duration, stroke count, SWOLF, pace (s/100m) ([GB specifics](https://gadgetbridge.org/internals/topics/huawei-honor-specifics/), [features list](https://gadgetbridge.org/basics/topics/huawei-honor/)).
- **GT5:** Gadgetbridge added device ID via [PR #4155](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/4155); “mostly supported,” workout sync listed — no public wire spec beyond device support matrix.
- **Vitals / HR series:** GB supports HR/SpO2/stress **sync on some devices** but documents **HR data sharing export as unsupported**; ~1 sample/min activity path mentioned in changelog. Continuous HR availability depends on Health app monitoring settings ([official watch data doc](https://developer.huawei.com/consumer/en/doc/hmscore-guides/obtain-smart-watch-data-0000001365189921)).
- **Pool swim UX (vendor):** Laps from turn detection; pool length 15–60 m; stroke auto-ID on select models; SWOLF shown in Health UI — algorithm opaque ([Huawei support](https://consumer.huawei.com/en/support/content/en-us15837935/)).
- **RE methodology:** Frida on `BluetoothGatt` / app JNI for ciphertext before/after bond ([Easterhegg PDF](https://www.sba-research.org/wp-content/uploads/2019/04/easterhegg19.pdf)); HCI snoop as alternative ([Pen Test Partners](https://www.pentestpartners.com/security-blog/reverse-engineering-ble-from-android-apps-with-frida/)).

## Still unknown (publicly)

- GT5-A07 **exact** service/command IDs and TLV tag map for workout **detail** (samples, pace zones, swim segments) vs Gate B totals-only path.
- Binary layout of swim pace rows and running pace zones per firmware; whether GT5 uses LPv2-only or LPv2+LPv3 hybrid.
- Reliable sliced/multi-packet reassembly rules on HarmonyOS GT5 firmware (huawei-lpv2 + author caveat).
- On-device HR time-series pull command sequence vs cloud `exerciseHeartRate` arrays in Health Kit.
- Whether SWOLF/lap fields in sync blob match Health app UI 1:1 or are derived client-side.

## Implications for Fitness OS

1. **Safe references:** Treat [huawei-lpv2 MIT wiki/code](https://github.com/zyv/huawei-lpv2/wiki/Wire-protocol) + Easterhegg/gist as primary framing/auth bibliography; re-derive tag semantics from GT5 captures, not GB Java.
2. **Gate B → enrichment:** Next increment is detail sync after Count/Totals; use GB swim pace column order and workout field checklist only as **test vectors**, validate against Frida/HCI traces on GT5.
3. **Framing layer:** Implement slice reassembly + async multiplex (huawei-lpv2 issue #11 warns newer devices interleave responses); align with existing `HuaweiFraming` in POC.
4. **Swim MVP:** Target per-lap style, distance, duration, strokes, SWOLF, pace; defer stroke-type accuracy disputes to vendor docs (turn/barometer edge cases).
5. **Vitals:** Treat daily HR series as separate service from workout HR samples; expect permission/monitoring gating mirroring official Health Kit behavior.
6. **No AGPL dependency:** Independent Kotlin implementation already validated Gate A/B; continue capture-driven spec in `docs/wire-specs/`.

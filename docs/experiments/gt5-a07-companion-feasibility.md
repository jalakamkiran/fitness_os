# GT5-A07 companion feasibility (U8)

**Date:** 2026-07-17  
**Device:** Huawei Watch GT5-A07  
**App:** Fitness OS Gate A cut (`feat/huawei-gt5-companion-gate-a`)

## Recommendation: **GO** (first-pair + reconnect proven)

Owner capture confirmed **HiChain3** (`t=7:04`) and successful **security-nego** (`1:0x33`). Fitness OS implements clean-room HiChain ISO exchange (HMAC/HKDF/AES-GCM + observed JSON wire format).

**2026-07-18 outcome:** Full GB-shaped configure + FeatureUpload cleared the **watch pairing UI**. App-kill relaunch reconnect also reached `session_ready` / `reconnect auth outcome=Ready`. Owner unlocked `gate_a_passed`. Gate B Count→Totals listed a strength workout on-device. **POC complete — GO.**

**POC learning doc (flowcharts + achievements):** `docs/learnings/2026-07-18-huawei-gt5-companion-poc.md`  
**Stack handoff:** `docs/handoffs/2026-07-18-huawei-gt5-gate-a-stack-handoff.md`.

**Hard rules retained:** Bare DataSync `t=7f:100000` poisons GCM — never blanket-ACK. Mode from link-params `t=7` (deviceSupportType), not ServerNonce. Phone MAC override required on privacy-MAC phones (Pixel).

| Step | Status |
|------|--------|
| HiChain3 auth+bind + product/time/battery/services | On-device OK |
| Async PhoneInfo `1:0x10` reply | On-device OK (watch ACK) |
| Accept-agreement `0x30` + connect-status `0x35` | On-device OK |
| Music params `0x25:0x04` + `0x0D` | On-device OK |
| DataSync featureManager action=2 + FileUpload + action=1 | On-device OK |
| Extended Account `0x1A:0x05` + Country `0x1A:0x0A` (late) | On-device OK (Country may soft-timeout on reconnect) |
| SupportedCommands / SettingRelated / ReverseCapabilities | On-device OK (SupportedCommands response parse still incomplete) |
| Watch pairing UI clear | Proven |
| Gate A passed (`gate_a_passed`) | Proven (owner checklist) |
| Gate B Count→Totals + local list | **On-device OK** (2026-07-18): strength ~112s → `count=1` totals `#2 type=140` listed |

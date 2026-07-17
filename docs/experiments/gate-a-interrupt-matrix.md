# Gate A interrupt matrix (U5)

Evidence log for AE2–AE4. **U5 does not write Gate A unlock prefs** — credits are owner checklist in U6 after authenticated reconnects only.

## Preconditions

- Huawei Health force-stopped / permissions stripped
- Gadgetbridge force-stopped
- Device remembered in Fitness OS (MAC + secrets)
- Test phone: _(fill)_
- Watch firmware: _(fill)_

## Matrix

| Interrupt | Acceptance | Authenticated `connected` / `gate_a_incomplete`? | `reconnect_failed` retained memory? | Notes | Pass/Fail |
|-----------|------------|--------------------------------------------------|-------------------------------------|-------|-----------|
| App force-stop → reopen (AE2) | R5 / AE2 | pending | pending | | pending |
| Bluetooth off → on (AE3) | R5 / AE3 | pending | pending | | pending |
| Phone reboot → open app (AE4) | R5 / AE4 | pending | pending | | pending |

## Failure-accept rule

A `reconnect_failed` outcome with device still remembered and a clear next action **counts as AE failure-accept** for that interrupt, but **must not** credit a U6 unlock bit.

## Secure vs insecure RFCOMM

Recorded during U1/U3 on-device runs: _(pending)_

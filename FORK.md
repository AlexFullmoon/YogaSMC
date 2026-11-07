# Fork notes

Technical details for changes in this fork. See the top of [README.md](README.md) for a summary.

## YogaISH: tablet mode via Intel Sensor Hub

### Problem

ThinkPad X1 Yoga Gen 5 reports the hinge posture through EC field `CMMD`. ThinkVPC reads it with `GMMS` when HKEY event `0x60C0` arrives (sent by EC query `_Q2E`). On macOS `CMMD` was stuck at 1 (laptop) in every posture, so no event was ever sent and keyboard and touchpad stayed enabled in tablet mode.

The posture is calculated by the Intel Integrated Sensor Hub (ISH) firmware, which passes it to EC only while a host driver is talking to it. Checked on Linux: `/sys/devices/platform/thinkpad_acpi/hotkey_tablet_mode` follows the posture with `intel_ish_ipc` and `intel_ishtp` loaded, keeps working after `intel_ishtp_hid` is unloaded, and stops updating once `intel_ish_ipc` is unloaded. So the sensor HID part is not needed, only the transport.

There is no other source of posture in the ACPI tables: `_Q2E`, `HIDD.VGBS` and `_WAK` all derive it from `CMMD`. Spoofing OS version does not help either.

### What YogaISH does

`YogaSMC/YogaISH.cpp` attaches to the ISH PCI device and repeats what Linux `intel_ish_ipc` + `intel_ishtp` do on probe (`drivers/hid/intel-ish-hid`), without any HID client:

1. Put the device into D0, enable memory decoding and bus mastering, disable legacy INTx. The driver polls every 10 ms instead of using interrupts (macOS assigns no interrupt to this device without a driver anyway).
2. IPC start (`ish_hw_start`): set host ready in `HOST_COMM`, enable DMA in `RMP2`, ring an empty doorbell to wake FW.
3. FW-initiated reset: FW sends `MNG_RESET_NOTIFY`, host answers `MNG_RESET_NOTIFY_ACK` with the same reset id and waits for `ILUP` and `ISHTP_READY` in `FWSTS`. If FW does not start the reset within 3 s, the host sends `MNG_RESET_NOTIFY` itself (`_ish_ipc_reset`).
4. HBM (ISHTP bus): `HOST_START_REQ`, `HOST_ENUM_REQ`, then `HOST_CLIENT_PROPERTIES_REQ` for every enumerated client (5 on this machine).
5. System state fixed client (address 13): `SYSTEM_STATE_QUERY_SUBSCRIBERS`, and on `SYSTEM_STATE_SUBSCRIBE` a status with nothing suspended (`ishtp_send_resume`).
6. `MNG_SYNC_FW_CLOCK` once the link is up and every 20 s afterwards.

After that the posture appears in `CMMD`, EC raises `_Q2E`, and the existing ThinkVPC code does the rest. `GMMS` returns type 4 on this machine: 1 Laptop, 3 Tablet, 4 Stand, 5 Tent.

FW also sends messages to fixed client 14 every few seconds. Linux ignores them, so does YogaISH.

### Sleep

Before sleep: send the suspend status to the system state client (`ishtp_send_suspend`) and disable DMA (`ish_disable_dma`), otherwise FW resets on its own in D3. After wake: put the device back into D0 and run the whole sequence again. After S3 the FW reboots and starts the reset flow itself. If it was kept alive, the 3 s host reset fallback handles it.

Polling and power transitions run on the same work loop, so they never overlap.

### Matching

Only `8086:02FC` (Comet Lake-LP), the only device tested. Register layout is the one Linux uses for all ISH generations except Cherry Trail, so other IDs from `ipc/hw-ish.h` might work, but some machines might not need ISH for posture at all.

### Diagnostics

`ioreg -l -c YogaISH` shows `State`: `WaitDevice`, `WaitReset`, `WaitFwReady`, `HbmStart`, `HbmEnum`, `HbmProps`, `Running`, `Suspended` or `Failed`. Debug builds also publish `FWSTS`, `Clients`, `ResetCount` and `WakeCount`, and log every step as `YSMC - Debug: ISHD::YogaISH ...`.

Release builds log only errors. To read them in zsh, call `/usr/bin/log` by full path: `log` is a zsh builtin and shadows it, returning nothing.

`YogaISH` must not run together with any other ISH driver. In particular, remove the standalone test kext (`ISHTest.kext`) from OpenCore if it was used.

## Fn keys

HKEY events on X1 Yoga Gen 5 (all enabled by the default hotkey mask, sent from EC queries `_Q63`, `_Q65`, `_Q66`, `_Q60`):

| Key | Event | Action |
| ---- | ---- | ---- |
| Fn-F7 | `0x1007` | Toggle mirroring of all displays to the main one (`mirrorHelper`) |
| Fn-F9 | `0x1317` | Open Notification Center by clicking the menu bar clock |
| Fn-F10 | `0x1318` | Custom (phone pickup on Windows) |
| Fn-F11 | `0x1319` | Custom (phone hangup on Windows) |
| Fn-F12 | `0x1311` | Custom, by default opens YogaSMCPane (Option: System Settings) |
| Fn-PrtSc | `0x1312` | Launch Screenshot.app |
| Fn-Tab | `0x1014` | Custom (zoom on Windows) |

The Notification Center script finds the clock by `AXIdentifier` `com.apple.menuextra.clock`, because its name is localized. It needs Accessibility and Automation (System Events) permissions for YogaSMCNC.

### Custom actions

Stored in `org.zhen.YogaSMC` as `CustomHotkeys`:

```
CustomHotkeys = { "1014" = { action = launchapp; option = "/Applications/Calculator.app"; }; }
```

`action` is `launchapp` (app name or path) or `script` (AppleScript source; for a long script use `run script POSIX file "/path/x.scpt"`). YogaSMCNC reads it on every press, so changes apply without a restart, and a custom action takes priority over the `Events` table. The Hotkeys tab in YogaSMCPane is built in code (`ThinkSMCPane.swift`) and appears only for ThinkVPC.

Because the pane now has more than one Swift class, `NSPrincipalClass` is module-qualified (`YogaSMCPane.YogaSMCPane`); otherwise the loader picks the first class in the binary and fails.

### Saved events

YogaSMCNC used to save the whole event table into `Events` on quit, and saved entries override built-in ones on launch, so changed defaults never reached existing installs. Now only entries that differ from the built-in table are saved. An old full copy can be removed with "Clear events" in the prefpane or `defaults delete org.zhen.YogaSMC Events` while YogaSMCNC is not running.

### Permissions and signing

macOS ties Accessibility and Automation grants to the code signature. An unsigned or ad-hoc signed build gets a new identity on every rebuild, so the grants silently stop working. Sign YogaSMCNC with a stable certificate (a self-signed code signing certificate is enough) after each build:

```
codesign --force --deep -s "<certificate name>" /Applications/YogaSMCNC.app
```

To use the same identity on another Mac, export the certificate with its private key as `.p12`.

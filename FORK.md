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

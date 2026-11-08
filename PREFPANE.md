# YogaSMCPane reference

What each control in the preference pane does, for ThinkPad (ThinkVPC) unless noted. Every control also has a tooltip. Settings either go to the driver (applied at once, stored by the driver, EC or firmware) or to `org.zhen.YogaSMC` preferences read by YogaSMCNC (the pane restarts YogaSMCNC to apply them).

The pane shows the General tab, the tab for the detected class (Think or Idea) and, on ThinkPad, Hotkeys. Rows for features the driver does not report on this machine are hidden or disabled.

All tabs are built in code (`buildGeneralTab`, `buildThinkTab`, `buildIdeaTab`, `addHotkeysTab`); the xib only provides the tab view.

## General

### Keyboard

| Control | Meaning |
| ---- | ---- |
| Backlight | Keyboard backlight level, same as Fn-Space. |
| Turn off after | Seconds without key presses after which the keyboard backlight turns off; the next key press restores it. `0` disables. Key presses are reported by VoodooPS2, so this does nothing with other keyboard drivers. |
| Restore backlight after wake | The driver saves the backlight level before sleep and sets it again on wake. The EC turns the backlight off during sleep by itself; this only matters if it stays off after wake. Driver bit `AutoBacklight` 0, previously labelled AutoSleep. |
| Top row keys | Fn Lock, same as Fn-Esc: F1–F12 or special functions without Fn. Shown when the driver reports Fn Lock state. |

### Thermal mode

DYTC is Lenovo's thermal mode interface, the same one Windows uses for "Intelligent Cooling" and Linux exposes as `platform_profile`.

| Control | Meaning |
| ---- | ---- |
| Mode | Quiet / Balance / Performance (MMC, desk mode). Disabled while the active function is one the driver cannot map to these modes. |
| Active function | `Standard` (default balance), `Desk` (mode set here), `Lap` (lap mode, the firmware limits power while it thinks the machine is on a lap), `Controlled` (PSC), `Other (0xe)` (a function the driver does not handle, `CSC` in `DYTC.h`), followed by the DYTC revision. |
| Use PSC levels | Switches the slider to 9 raw PSC levels instead of the three modes. Shown when the firmware lists both MMC and PSC. Linux uses PSC only on AMD machines, so on Intel models leave it off. |

### Menu bar and notifications (YogaSMCNC settings)

| Control | Meaning |
| ---- | ---- |
| Hide menu bar icon | Run YogaSMCNC without a menu bar item. Hotkeys and notifications keep working; fan controls are not shown. |
| Custom icon | Text shown in the menu bar instead of the icon, for example `⌘`. Empty restores the icon. Applied on Enter. |
| Hide Caps Lock notification | Do not show the Caps Lock OSD. It does not change Caps Lock itself. |
| Clear saved events | Removes the saved `Events` table, so YogaSMCNC uses the built-in actions again. Custom hotkeys are kept. |

### Special modes

**Clamshell mode** keeps the machine usable with the lid closed or the keyboard folded away: the lid open event is ignored, and ThinkVPC keeps the keyboard and touchpad enabled in tablet-like modes and skips Yoga mode notifications. The driver turns it off when it stops.

It needs two ACPI methods next to the VPC device, `GCSM` (get) and `SCSM` (set), plus a patched lid open EC query. They are not in any stock firmware, so the checkbox stays disabled, with a note, until an SSDT like `YogaSMC/SSDTSample/SSDT-RCSM.dsl` is added. That sample is written for IdeaPad (`VPC0`, `_Q0D`); on ThinkPad the methods go into `HKEY` and the lid query has to be found in the DSDT.

**Turn off keyboard backlight in tablet mode** (IdeaPad only, hidden elsewhere): driver bit `AutoBacklight` 1. On ThinkPad the keyboard is disabled in tablet-like modes anyway.

### Driver

Class and version of the driver, and EC access: whether it can read and write EC fields (`RW`, `RO` or none). EC access needs EC read/write methods in ACPI, see `SSDT-ECRW.dsl`.

## Think

### Charge thresholds

Charge start and stop thresholds, as on Linux `charge_control_start_threshold` / `charge_control_end_threshold`. Stored by the EC, so they survive reboots and apply in every OS. Rows: both batteries at once, primary, secondary; only the ones the firmware supports are shown (primary only on X1 Yoga Gen 5).

Charging starts when the level drops below `start` and stops at `stop`. Start 0 means the firmware default, stop 100 means no limit. Enter or leaving either field writes both values of the row; an invalid pair (start above stop, out of range) turns red and is not written. The fields show what the EC actually stored.

### LEDs, automatic

| Control | Meaning |
| ---- | ---- |
| Blink the lid logo dot while asleep | Show sleep state on the lid logo dot and power LED like Windows does: through the firmware method `CSSI` if present, otherwise by setting the LEDs directly before sleep and after wake. Driver bit `AutoBacklight` 2. |
| Turn off the mic mute LED while asleep | Driver bit 4: off before sleep, restored on wake. |
| Turn off the mute LED while asleep | Driver bit 3, the same for the speaker mute LED. Hidden in release builds, as the original code disabled it there without a stated reason. |
| Keep the mute LED in sync with system mute | YogaSMCNC sets the speaker mute LED whenever macOS output is muted or unmuted. |

### LEDs, manual

Sets a LED once through the `LED` ACPI method: Power button, Standby, Lid logo dot, or any LED picked in the list, each Off, On, Pulse or Blink. The driver cannot read LED state, so the sliders do not show it. Nothing is saved; the automatic options above, sleep and the firmware may change the LED again. Most list entries do not exist on a given model.

The difference from the automatic options: those react to sleep and wake, these only set a LED when you move the slider.

### Fan (YogaSMCNC menu)

Fan control itself is in the YogaSMCNC menu: a slider for the fan level and an Auto button.

| Control | Meaning |
| ---- | ---- |
| Allow stopping the fan | Let the slider go down to 0 (fan off). Off by default, so the lowest manual level is 1. |
| Remember manual fan level | Set the last manual level again when YogaSMCNC starts. |
| Hide fan controls in the menu | Do not show fan controls in the menu. |
| Show second fan | Models with two fans only, hidden elsewhere. |

## Hotkeys (ThinkPad only)

Custom actions for Fn-Tab, Fn-F10, Fn-F11 and Fn-F12: Default (built-in action), Launch app (name or path, Choose… picks one) or AppleScript. Applied on the next key press. See [FORK.md](FORK.md#custom-actions) for the storage format.

## Idea

Shown only on IdeaPad (and in debug builds). Not tested on real IdeaPad hardware in this fork.

| Control | Meaning |
| ---- | ---- |
| Conservation mode | Keep the battery charged to about 60% to extend its life. |
| Rapid charge | Charge faster at the cost of battery wear. The checkbox was display-only before; it now sets `RapidChargeMode` in the driver. |
| ID, Cycle count, Temperature, Manufacture date | Battery information from the firmware. |
| Keep USB powered while asleep or off | Always On USB: the marked USB port keeps supplying power. |
| Hardware reported by firmware | Camera, Bluetooth, wireless, WWAN and graphics: green when present and on, gray otherwise. Graphics is colored by vendor, the tooltip shows its name. |

Fn lock (Top row keys) is on the General tab; on IdeaPad the second option is named after the key type the driver reports.

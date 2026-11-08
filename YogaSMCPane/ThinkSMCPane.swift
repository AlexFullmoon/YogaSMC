//
//  ThinkSMCPane.swift
//  YogaSMCPane
//
//  Created by Zhen on 12/9/20.
//  Copyright © 2020 Zhen. All rights reserved.
//

import AppKit
import Foundation
import os.log

extension YogaSMCPane {
    // Either field applies the pair of its battery, so editing one field is enough
    @IBAction func vChargeThresholdStartSet(_ sender: NSTextField) {
        applyThinkThresholds(sender.tag)
    }

    @IBAction func vChargeThresholdStopSet(_ sender: NSTextField) {
        applyThinkThresholds(sender.tag)
    }

    func thinkThresholdFields(_ index: Int) -> (start: NSTextField, stop: NSTextField)? {
        switch index {
        case 0:
            return (vChargeThresholdStart, vChargeThresholdStop)
        case 1:
            return (vPrimaryChargeThresholdStart, vPrimaryChargeThresholdStop)
        case 2:
            return (vSecondaryChargeThresholdStart, vSecondaryChargeThresholdStop)
        default:
            return nil
        }
    }

    // Select the battery in the driver and read its thresholds, stop 0 is reported as 100
    func readThinkThresholds(_ index: Int) -> (start: Int, stop: Int)? {
        guard index >= 0, index < thinkBatteryName.count,
              sendNumber("Battery", index, service),
              let dict = getDictionary(thinkBatteryName[index], service),
              let vStart = dict["BCTG"] as? NSNumber,
              let vStop = dict["BCSG"] as? NSNumber,
              vStart.int32Value >= 0,
              vStop.int32Value >= 0 else { return nil }
        let stop = vStop.intValue & 0xff
        return (vStart.intValue & 0xff, stop == 0 ? 100 : stop)
    }

    func applyThinkThresholds(_ index: Int) {
        guard let fields = thinkThresholdFields(index),
              let current = readThinkThresholds(index) else {
            if #available(macOS 10.12, *) {
                os_log("Failed to update battery %d", type: .error, index)
            }
            return
        }
        let start = fields.start.integerValue
        let stop = fields.stop.integerValue

        // Same limits as Linux thinkpad_acpi; keep the input until the pair is valid
        guard (0...99).contains(start), (1...100).contains(stop), start <= stop else {
            fields.start.textColor = .systemRed
            fields.stop.textColor = .systemRed
            return
        }
        fields.start.textColor = .controlTextColor
        fields.stop.textColor = .controlTextColor

        // EC stores stop 100 as 0, older drivers pass the value as is
        let stopArg = stop == 100 ? 0 : stop

        // Write in the order that keeps start <= stop in EC between the two writes
        if start > current.stop {
            if stop != current.stop { _ = sendNumber("setCMstop", stopArg, service) }
            if start != current.start { _ = sendNumber("setCMstart", start, service) }
        } else {
            if start != current.start { _ = sendNumber("setCMstart", start, service) }
            if stop != current.stop { _ = sendNumber("setCMstop", stopArg, service) }
        }

        // Show what EC actually stored
        _ = updateThinkBattery(fields.start, fields.stop)
    }

    @IBAction func vPowerLEDSet(_ sender: NSSlider) {
        if !sendNumber("LED", thinkLEDCommand[vPowerLEDSlider.integerValue] + 0x00, service) {
            return
        }
    }
    @IBAction func vStandbyLEDSet(_ sender: NSSlider) {
        if !sendNumber("LED", thinkLEDCommand[vStandbyLEDSlider.integerValue] + 0x07, service) {
            return
        }
    }

    @IBAction func vThinkDotSet(_ sender: NSSlider) {
        if !sendNumber("LED", thinkLEDCommand[vThinkDotSlider.integerValue] + 0x0A, service) {
            return
        }
    }

    @IBAction func vCustomLEDSet(_ sender: NSSlider) {
        let value = thinkLEDCommand[vCustomLEDSlider.integerValue] + vCustomLEDList.indexOfSelectedItem
        #if DEBUG
        showOSD(String(format: "LED 0x%02X", value))
        #endif
        if !sendNumber("LED", value, service) {
            return
        }
    }

    @IBAction func vSecondFanSet(_ sender: NSButton) {
        defaults.setValue((vSecondFan.state == .on), forKey: "SecondThinkFan")
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }
    @IBAction func vFanStopSet(_ sender: NSButton) {
        defaults.setValue((vFanStop.state == .on), forKey: "AllowFanStop")
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }
    @IBAction func vDisableFanSet(_ sender: NSButton) {
        defaults.setValue((vDisableFan.state == .on), forKey: "DisableFan")
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }

    @IBAction func vSaveFanLevelSet(_ sender: NSButton) {
        defaults.setValue((vSaveFanLevel.state == .on), forKey: "SaveFanLevel")
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }

    @IBAction func vMuteLEDFixupSet(_ sender: NSButton) {
        defaults.setValue((vMuteLEDFixup.state == .on), forKey: "ThinkMuteLEDFixup")
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }

    func updateThinkBattery(_ startThreshold: NSTextField, _ stopThreshold: NSTextField) -> Bool {
        guard startThreshold.tag == stopThreshold.tag,
              let current = readThinkThresholds(startThreshold.tag) else { return false }

        // Enabled even with out-of-range values, so they can be fixed from here
        startThreshold.isEnabled = true
        stopThreshold.isEnabled = true
        startThreshold.integerValue = current.start
        stopThreshold.integerValue = current.stop
        return true
    }

    func updateThink(_ props: NSDictionary) {
        _ = updateThinkBattery(vChargeThresholdStart, vChargeThresholdStop)
        _ = updateThinkBattery(vPrimaryChargeThresholdStart, vPrimaryChargeThresholdStop)
        _ = updateThinkBattery(vSecondaryChargeThresholdStart, vSecondaryChargeThresholdStop)

        if let val = props["FnlockMode"] as? Bool {
            vFnKeyRadio.isEnabled = true
            vFxKeyRadio.isEnabled = true
            if val {
                vFnKeyRadio.state = .on
            } else {
                vFxKeyRadio.state = .on
            }
        }
        #if DEBUG
        if let val = props["Dual fan"] as? Bool,
           val == true {
            vSecondFan.isEnabled = true
            vSecondFan.state = defaults.bool(forKey: "SecondThinkFan") ? .on : .off
        }
        #endif
        vFanStop.state = defaults.bool(forKey: "AllowFanStop") ? .on : .off
        if let val = props["LEDSupport"] as? Bool,
           val == true {
            vPowerLEDSlider.isEnabled = true
            vStandbyLEDSlider.isEnabled = true
            vThinkDotSlider.isEnabled = true
            vCustomLEDSlider.isEnabled = true
        }
        vDisableFan.state = defaults.bool(forKey: "DisableFan") ? .on : .off
        vSaveFanLevel.state = defaults.bool(forKey: "SaveFanLevel") ? .on : .off
        vMuteLEDFixup.state = defaults.bool(forKey: "ThinkMuteLEDFixup") ? .on : .off
    }
}

// One row of the Hotkeys tab: action type, app or AppleScript, app picker
private class HotkeyRow: NSObject {
    let event: UInt32
    let defaults: UserDefaults
    let type = NSPopUpButton(frame: .zero, pullsDown: false)
    let option = NSTextField(frame: .zero)
    let choose = NSButton(frame: .zero)

    init(_ event: UInt32, _ defaults: UserDefaults) {
        self.event = event
        self.defaults = defaults
        super.init()

        type.addItems(withTitles: ["Default", "Launch app", "AppleScript"])
        type.target = self
        type.action = #selector(typeChanged)
        type.toolTip = "Default keeps the built-in action of the key."

        option.target = self
        option.action = #selector(save)
        option.lineBreakMode = .byTruncatingMiddle
        option.cell?.sendsActionOnEndEditing = true
        option.toolTip = "App name or path, or AppleScript source. For a long script use run script POSIX file \"/path/x.scpt\"."
        option.widthAnchor.constraint(equalToConstant: 230).isActive = true

        choose.title = "Choose…"
        choose.bezelStyle = .rounded
        choose.target = self
        choose.action = #selector(chooseApp)
        choose.toolTip = "Pick an application."

        if let entry = entries[key] as? [String: String] {
            switch entry["action"] {
            case "launchapp": type.selectItem(at: 1)
            case "script": type.selectItem(at: 2)
            default: break
            }
            option.stringValue = entry["option"] ?? ""
        }
        updateControls()
    }

    var key: String { String(event, radix: 16) }
    var entries: [String: Any] { defaults.dictionary(forKey: customHotkeysKey) ?? [:] }

    func updateControls() {
        option.isEnabled = type.indexOfSelectedItem != 0
        choose.isEnabled = type.indexOfSelectedItem == 1
        switch type.indexOfSelectedItem {
        case 1: option.placeholderString = "App name or path"
        case 2: option.placeholderString = "tell application \"Finder\" to activate"
        default: option.placeholderString = nil
        }
    }

    @objc func typeChanged() {
        updateControls()
        save()
    }

    @objc func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedFileTypes = ["app"]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        option.stringValue = url.path
        save()
    }

    @objc func save() {
        var dict = entries
        switch type.indexOfSelectedItem {
        case 1: dict[key] = ["action": "launchapp", "option": option.stringValue]
        case 2: dict[key] = ["action": "script", "option": option.stringValue]
        default: dict.removeValue(forKey: key)
        }
        defaults.setValue(dict, forKey: customHotkeysKey)
    }
}

private var hotkeyRows: [HotkeyRow] = []

extension YogaSMCPane {
    func addHotkeysTab() {
        guard mainTabView.indexOfTabViewItem(withIdentifier: "Hotkeys") == NSNotFound else { return }
        let item = NSTabViewItem(identifier: "Hotkeys")
        item.label = "Hotkeys"
        var rows: [[NSView]] = []
        for hotkey in customHotkeys {
            let row = HotkeyRow(hotkey.event, defaults)
            hotkeyRows.append(row)
            rows.append([NSTextField(labelWithString: hotkey.name + ":"), makeRow([row.type, row.option, row.choose])])
        }
        rows.append([makeNote("Changes apply on the next key press. AppleScript actions need Accessibility " +
                              "and Automation permissions for YogaSMCNC.")])
        let section = makeSection("Custom key actions", rows)
        (section.contentView?.subviews.first as? NSGridView)?.column(at: 0).width = 60
        item.view = makeTabContent([section])
        mainTabView.addTabViewItem(item)
    }
}

// MARK: - Layout

extension YogaSMCPane {
    func buildThinkTab() {
        // Charge thresholds
        func thresholdRow(_ name: String, _ tag: Int) -> (NSTextField, NSTextField, [NSView]) {
            let start = makeNumberField(100, #selector(vChargeThresholdStartSet),
                "Start charging when the level drops below this. 0 = firmware default.", tag: tag)
            let stop = makeNumberField(100, #selector(vChargeThresholdStopSet),
                "Stop charging at this level. 100 = no limit.", tag: tag)
            start.isEnabled = false
            stop.isEnabled = false
            return (start, stop, [NSTextField(labelWithString: name),
                    makeRow([NSTextField(labelWithString: "start"), start, NSTextField(labelWithString: "%   stop"),
                             stop, NSTextField(labelWithString: "%")])])
        }
        let any = thresholdRow("Both batteries:", 0)
        let primary = thresholdRow("Primary battery:", 1)
        let secondary = thresholdRow("Secondary battery:", 2)
        (vChargeThresholdStart, vChargeThresholdStop) = (any.0, any.1)
        (vPrimaryChargeThresholdStart, vPrimaryChargeThresholdStop) = (primary.0, primary.1)
        (vSecondaryChargeThresholdStart, vSecondaryChargeThresholdStop) = (secondary.0, secondary.1)
        let charge = makeSection("Charge thresholds", [
            any.2, primary.2, secondary.2,
            [makeNote("Stored by the EC, so they apply in every OS. Press Enter or leave the field to save; " +
                      "red means the pair is invalid and was not saved.")]
        ])

        // LEDs
        indicatorCheck = makeCheckbox("Blink the lid logo dot while asleep", #selector(autoBacklightSet),
            "Show sleep state on the ThinkPad logo dot and power LED, like Windows does.")
        micMuteCheck = makeCheckbox("Turn off the mic mute LED while asleep", #selector(autoBacklightSet),
            "Turn the mic mute LED off before sleep and restore it on wake.")
        muteCheck = makeCheckbox("Turn off the mute LED while asleep", #selector(autoBacklightSet),
            "Turn the speaker mute LED off before sleep and restore it on wake. Experimental.")
        vMuteLEDFixup = makeCheckbox("Keep the mute LED in sync with system mute", #selector(vMuteLEDFixupSet),
            "YogaSMCNC sets the speaker mute LED whenever macOS output is muted or unmuted.")
        let automation = makeSection("LEDs, automatic", [[indicatorCheck], [micMuteCheck], [muteCheck], [vMuteLEDFixup]])

        let modes = ["Off", "On", "Pulse", "Blink"]
        vPowerLEDSlider = makeSlider(3, #selector(vPowerLEDSet), "Power button LED.", width: 160)
        vStandbyLEDSlider = makeSlider(3, #selector(vStandbyLEDSet), "Standby LED, on models that have one.", width: 160)
        let thinkDot = makeSlider(3, #selector(vThinkDotSet), "ThinkPad logo dot on the lid.", width: 160)
        vThinkDotSlider = thinkDot.cell as? NSSliderCell
        vCustomLEDSlider = makeSlider(3, #selector(vCustomLEDSet), "LED selected in the list.", width: 160)
        for slider in [vPowerLEDSlider, vStandbyLEDSlider, thinkDot, vCustomLEDSlider] {
            slider?.isEnabled = false
        }
        vCustomLEDList = NSPopUpButton(frame: .zero, pullsDown: false)
        vCustomLEDList.addItems(withTitles: ["power", "orange:batt", "green:batt", "dock_active", "bay_active",
                                             "dock_batt", "fnlock", "standby", "dock_status1", "dock_status2",
                                             "thinkdot", "unknown_led3", "thinkvantage", "caps_lock", "mic_mute",
                                             "unknown_led6"])
        vCustomLEDList.toolTip = "LED number for the slider on the right. Most of them do not exist on a given model."
        let manual = makeSection("LEDs, manual", [
            [makeNote("Sets the LED right away. The sliders do not show the current state; " +
                      "nothing is saved, sleep and other events may change the LED again.")],
            [NSTextField(labelWithString: "Power button:"), captionedSlider(vPowerLEDSlider, modes).0],
            [NSTextField(labelWithString: "Standby:"), captionedSlider(vStandbyLEDSlider, modes).0],
            [NSTextField(labelWithString: "Lid logo dot:"), captionedSlider(thinkDot, modes).0],
            [vCustomLEDList, captionedSlider(vCustomLEDSlider, modes).0]
        ])

        // Fan
        vFanStop = makeCheckbox("Allow stopping the fan", #selector(vFanStopSet),
            "Let the fan slider in the menu go down to 0. Off by default, the lowest manual level is 1.")
        vSaveFanLevel = makeCheckbox("Remember manual fan level", #selector(vSaveFanLevelSet),
            "Set the last manual fan level again when YogaSMCNC starts.")
        vDisableFan = makeCheckbox("Hide fan controls in the menu", #selector(vDisableFanSet),
            "Do not show the fan slider and Auto button in the YogaSMCNC menu.")
        vSecondFan = makeCheckbox("Show second fan", #selector(vSecondFanSet),
            "Control the second fan on models that have two.")
        vSecondFan.isEnabled = false
        let fan = makeSection("Fan (YogaSMCNC menu)", [[vFanStop], [vSaveFanLevel], [vDisableFan], [vSecondFan]])

        thinkViewItem.view = makeTabContent([charge, automation, manual, fan])
    }

    func updateThinkLayout() {
        setRowHidden(vChargeThresholdStart, !vChargeThresholdStart.isEnabled)
        setRowHidden(vSecondaryChargeThresholdStart, !vSecondaryChargeThresholdStart.isEnabled)
        setRowHidden(vSecondFan, !vSecondFan.isEnabled)
        #if !DEBUG
        setRowHidden(muteCheck, true)
        #endif
    }
}

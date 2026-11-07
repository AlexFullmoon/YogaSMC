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
            vFnKeyRadio.title = "FnKey"
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

    init(_ event: UInt32, _ name: String, _ defaults: UserDefaults, _ view: NSView, _ y: CGFloat) {
        self.event = event
        self.defaults = defaults
        super.init()

        let label = NSTextField(labelWithString: name)
        label.frame = NSRect(x: 20, y: y + 3, width: 60, height: 17)
        view.addSubview(label)

        type.frame = NSRect(x: 85, y: y, width: 130, height: 25)
        type.addItems(withTitles: ["Default", "Launch app", "AppleScript"])
        type.target = self
        type.action = #selector(typeChanged)
        view.addSubview(type)

        option.frame = NSRect(x: 222, y: y + 2, width: 290, height: 22)
        option.target = self
        option.action = #selector(save)
        option.lineBreakMode = .byTruncatingMiddle
        option.cell?.sendsActionOnEndEditing = true
        view.addSubview(option)

        choose.frame = NSRect(x: 515, y: y - 2, width: 90, height: 32)
        choose.title = "Choose…"
        choose.bezelStyle = .rounded
        choose.target = self
        choose.action = #selector(chooseApp)
        view.addSubview(choose)

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
        let view = NSView(frame: mainTabView.contentRect)
        var y = view.frame.height - 45
        for hotkey in customHotkeys {
            hotkeyRows.append(HotkeyRow(hotkey.event, hotkey.name, defaults, view, y))
            y -= 35
        }
        let note = NSTextField(wrappingLabelWithString:
            "Default keeps the built-in action. Changes apply immediately. " +
            "AppleScript actions need Accessibility and Automation permissions for YogaSMCNC.")
        note.frame = NSRect(x: 20, y: y - 30, width: 585, height: 40)
        note.textColor = .secondaryLabelColor
        view.addSubview(note)
        item.view = view
        mainTabView.addTabViewItem(item)
    }
}

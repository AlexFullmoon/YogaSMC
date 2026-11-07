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
    @IBAction func vChargeThresholdStartSet(_ sender: NSTextField) {
        let target = sender.integerValue
        #if DEBUG
        showOSD(String(format: "Start %d", target))
        #endif

        if thinkBatteryNumber != sender.tag, !updateThinkBatteryIndex(sender.tag) {
            if #available(macOS 10.12, *) {
                os_log("Failed to update battery %d", type: .error, sender.tag)
            }
            sender.isEnabled = false
            return
        }

        if target == sender.integerValue { return }
        _ = sendNumber("setCMstart", target, service)
        sender.integerValue = target
    }

    @IBAction func vChargeThresholdStopSet(_ sender: NSTextField) {
        let target = sender.integerValue

        if thinkBatteryNumber != sender.tag, !updateThinkBatteryIndex(sender.tag) {
            if #available(macOS 10.12, *) {
                os_log("Failed to update battery %d", type: .error, sender.tag)
            }
            return
        }

        if target == sender.integerValue { return }
        #if DEBUG
        showOSD(String(format: "Stop %d", target))
        #endif
        _ = sendNumber("setCMstop", target == 100 ? 0 : target, service)
        sender.integerValue = target
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

    func updateThinkBatteryIndex(_ index: Int) -> Bool {
        if !sendNumber("Battery", index, service) { return false }

        switch index {
        case 0:
            return updateThinkBattery(vChargeThresholdStart, vChargeThresholdStop)
        case 1:
            return updateThinkBattery(vPrimaryChargeThresholdStart, vPrimaryChargeThresholdStop)
        case 2:
            return updateThinkBattery(vSecondaryChargeThresholdStart, vSecondaryChargeThresholdStop)
        default:
            return false
        }
    }

    func updateThinkBattery(_ startThreshold: NSTextField, _ stopThreshold: NSTextField) -> Bool {
        guard startThreshold.tag == stopThreshold.tag else { return false}
        let index = startThreshold.tag

        guard let dict = getDictionary(thinkBatteryName[index], service),
              let vStart = dict["BCTG"] as? NSNumber,
              let vStop = dict["BCSG"] as? NSNumber,
              vStart.int32Value >= 0,
              vStart.int32Value & 0xff < 100,
              vStop.int32Value >= 0,
              vStop.int32Value & 0xff < 100 else { return false }

        startThreshold.isEnabled = true
        stopThreshold.isEnabled = true
        startThreshold.integerValue = vStart.intValue & 0xff
        stopThreshold.integerValue = (vStop.intValue & 0xff) == 0 ? 100 : vStop.intValue & 0xff

        thinkBatteryNumber = index
        return true
    }

    func updateThink(_ props: NSDictionary) {
        _ = updateThinkBatteryIndex(0)
        _ = updateThinkBatteryIndex(1)
        _ = updateThinkBatteryIndex(2)

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

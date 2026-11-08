//
//  YogaSMCPane.swift
//  YogaSMCPane
//
//  Created by Zhen on 9/17/20.
//  Copyright © 2020 Zhen. All rights reserved.
//

import AppKit
import Foundation
import IOKit
import PreferencePanes
import os.log

let DYTCCommand = ["L", "M", "H"]
let thinkLEDCommand = [0, 0x80, 0xA0, 0xC0]
let thinkBatteryName = ["BAT_ANY", "BAT_PRIMARY", "BAT_SECONDARY"]

class YogaSMCPane: NSPreferencePane {
    let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("YogaVPC"))
    let defaults = UserDefaults(suiteName: "org.zhen.YogaSMC")!

    @IBOutlet var vVersion: NSTextField!
    @IBOutlet var vClass: NSTextField!
    @IBOutlet var vECRead: NSTextField!
    @IBOutlet var vHideMenubarIcon: NSButton!
    @IBAction func toggleMenubarIcon(_ sender: NSButton) {
        if vHideMenubarIcon.state == .on {
            defaults.setValue(true, forKey: "HideIcon")
            vMenubarIcon.isEnabled = false
        } else {
            defaults.setValue(false, forKey: "HideIcon")
            vMenubarIcon.isEnabled = true
        }
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }

    @IBOutlet var vMenubarIcon: NSTextField!
    @IBAction func setMenubarIcon(_ sender: NSTextField) {
        if vMenubarIcon.stringValue == "" {
            guard defaults.value(forKey: "Title") != nil else { return }
            defaults.removeObject(forKey: "Title")
        } else {
            if defaults.string(forKey: "Title") == vMenubarIcon.stringValue { return }
            defaults.setValue(vMenubarIcon.stringValue, forKey: "Title")
        }
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }

    @IBOutlet var vHideCapsLock: NSButton!
    @IBAction func toggleHideCapsLock(_ sender: NSButton) {
        defaults.setValue(vHideCapsLock.state == .on, forKey: "HideCapsLock")
        _ = scriptHelper(reloadAS, "Reload YogaSMCNC")
    }

    @IBAction func vClearEvents(_ sender: NSButton) {
        _ = scriptHelper(stopAS, "Stop YogaSMCNC")
        defaults.removeObject(forKey: "Events")
        _ = scriptHelper(startAS, "Start YogaSMCNC")
    }

    // Idea
    @IBOutlet var vFnKeyRadio: NSButton!
    @IBOutlet var vFxKeyRadio: NSButton!

    @IBOutlet var vBatteryID: NSTextField!
    @IBOutlet var vBatteryTemperature: NSTextField!
    @IBOutlet var vCycleCount: NSTextField!
    @IBOutlet var vMfgDate: NSTextField!

    @IBOutlet var vAlwaysOnUSBMode: NSButton!
    @IBOutlet var vConservationMode: NSButton!
    @IBOutlet var vRapidChargeMode: NSButton!

    @IBOutlet var vCamera: NSTextField!
    @IBOutlet var vBluetooth: NSTextField!
    @IBOutlet var vWireless: NSTextField!
    @IBOutlet var vWWAN: NSTextField!
    @IBOutlet var vGraphics: NSTextField!

    // Think

    @IBOutlet var vChargeThresholdStart: NSTextField!
    @IBOutlet var vChargeThresholdStop: NSTextField!
    @IBOutlet var vPrimaryChargeThresholdStart: NSTextField!
    @IBOutlet var vPrimaryChargeThresholdStop: NSTextField!
    @IBOutlet var vSecondaryChargeThresholdStart: NSTextField!
    @IBOutlet var vSecondaryChargeThresholdStop: NSTextField!

    @IBOutlet var vPowerLEDSlider: NSSlider!
    @IBOutlet var vStandbyLEDSlider: NSSlider!
    @IBOutlet var vThinkDotSlider: NSSliderCell!
    @IBOutlet var vCustomLEDSlider: NSSlider!
    @IBOutlet var vCustomLEDList: NSPopUpButton!

    @IBOutlet var vSecondFan: NSButton!
    @IBOutlet var vFanStop: NSButton!
    @IBOutlet var vDisableFan: NSButton!
    @IBOutlet var vSaveFanLevel: NSButton!

    @IBOutlet var vMuteLEDFixup: NSButton!

    // Main

    @IBOutlet var mainTabView: NSTabView!
    // strong, removed items are released by the tab view and willSelect runs on every reopen
    @IBOutlet var ideaViewItem: NSTabViewItem!
    @IBOutlet var thinkViewItem: NSTabViewItem!

    func removeTab(_ item: NSTabViewItem) {
        if mainTabView.tabViewItems.contains(item) {
            mainTabView.removeTabViewItem(item)
        }
    }

    @IBOutlet var vDYTCRevision: NSTextField!
    @IBOutlet var vDYTCFuncMode: NSTextField!
    @IBOutlet var DYTCSlider: NSSlider!
    @IBOutlet var DYTCPSCCheck: NSButton!

    @IBOutlet var backlightSlider: NSSlider!
    @IBOutlet var vBackLightTimeout: NSTextField!

    @IBOutlet var autoSleepCheck: NSButton!
    @IBOutlet var yogaModeCheck: NSButton!
    @IBOutlet var indicatorCheck: NSButton!
    @IBOutlet var muteCheck: NSButton!
    @IBOutlet var micMuteCheck: NSButton!

    @IBOutlet var vClamshellMode: NSButton!

    override func mainViewDidLoad() {
        super.mainViewDidLoad()
        if #available(macOS 10.12, *) {
            os_log(#function, type: .info)
        }
        // Use the height System Settings gives to panes, the tabs scroll if needed
        mainView.setFrameSize(NSSize(width: mainView.frame.width, height: 560))
        mainTabView.frame = NSRect(x: 13, y: 2, width: mainView.frame.width - 26, height: 546)
        buildGeneralTab()
        buildThinkTab()
        buildIdeaTab()
    }

    override func willSelect() {
        guard service != 0, sendBoolean("Update", true, service) else { return }

        guard let props = getProperties(service) else {
            if #available(macOS 10.12, *) {
                os_log("Unable to acquire driver properties!", type: .fault)
            }
            return
        }

        if let val = props["VersionInfo"] as? NSString {
            vVersion.stringValue = val as String
        } else {
            if #available(macOS 10.12, *) {
                os_log("Unable to identify driver version!", type: .fault)
            }
            return
        }

        if let val = props["EC Capability"] as? NSString {
            vECRead.stringValue = val as String
        } else {
            if #available(macOS 10.12, *) {
                os_log("Unable to identify EC capability!", type: .fault)
            }
            return
        }

        updateMain(props)

        switch props["IOClass"] as? NSString {
        case "IdeaVPC":
            vClass.stringValue = "Idea"
            updateIdea(props)
            #if !DEBUG
            removeTab(thinkViewItem)
            #endif
        case "ThinkVPC":
            vClass.stringValue = "Think"
            updateThink(props)
            updateThinkLayout()
            addHotkeysTab()
            #if !DEBUG
            removeTab(ideaViewItem)
            #endif
        case "YogaHIDD":
            vClass.stringValue = "HIDD"
            removeTab(ideaViewItem)
            removeTab(thinkViewItem)
        default:
            vClass.stringValue = "Unsupported"
            removeTab(ideaViewItem)
            removeTab(thinkViewItem)
        }
        updateGeneralLayout(props)
    }
}

//
//  IdeaSMCPane.swift
//  YogaSMCPane
//
//  Created by Zhen on 12/9/20.
//  Copyright © 2020 Zhen. All rights reserved.
//

import AppKit
import Foundation

extension YogaSMCPane {
    @IBAction func vFnKeySet(_ sender: NSButton) {
        if !sendBoolean("FnlockMode", vFnKeyRadio.state == .on, service) {
            vFnKeyRadio.state = getBoolean("FnlockMode", service) ? .on : .off
        }
    }

    @IBAction func vAlwaysOnUSBModeSet(_ sender: NSButton) {
        if !sendBoolean("AlwaysOnUSBMode", vAlwaysOnUSBMode.state == .on, service) {
            vAlwaysOnUSBMode.state = getBoolean("AlwaysOnUSBMode", service) ? .on : .off
        }
    }

    @IBAction func vConservationModeSet(_ sender: NSButton) {
        if !sendBoolean("ConservationMode", vConservationMode.state == .on, service) {
            vConservationMode.state = getBoolean("ConservationMode", service) ? .on : .off
        }
    }

    @IBAction func vRapidChargeModeSet(_ sender: NSButton) {
        if !sendBoolean("RapidChargeMode", vRapidChargeMode.state == .on, service) {
            vRapidChargeMode.state = getBoolean("RapidChargeMode", service) ? .on : .off
        }
    }

    func updateIdeaBattery(_ dict: NSDictionary) {
        vBatteryID.stringValue = dict["ID"] as? String ?? "Unknown"
        vCycleCount.stringValue = dict["Cycle count"] as? String ?? "Unknown"
        vBatteryTemperature.stringValue = dict["Temperature"] as? String ?? "Unknown"
        vMfgDate.stringValue = dict["Manufacture date"] as? String ?? "Unknown"
    }

    func updateIdeaCap(_ dict: NSDictionary) {
        if let val = dict["Camera"] as? Bool {
            vCamera.textColor = val ? NSColor.systemGreen : NSColor.systemGray
        }
        if let val = dict["Bluetooth"] as? Bool {
            vBluetooth.textColor = val ? NSColor.systemGreen : NSColor.systemGray
        }
        if let val = dict["Wireless"] as? Bool {
            vWireless.textColor = val ? NSColor.systemGreen : NSColor.systemGray
        }
        if let val = dict["3G"] as? Bool {
            vWWAN.textColor = val ? NSColor.systemGreen : NSColor.systemGray
        }
        if let val = dict["Graphics"] as? NSString {
            vGraphics.toolTip = val as String
            switch val {
            case "Intel":
                vGraphics.textColor = NSColor(red: 0/0xff, green: 0x71/0xff, blue: 0xc5/0xff, alpha: 1)
            case "ATI", "Intel and ATI":
                vGraphics.textColor = NSColor(red: 0x97/0xff, green: 0x0a/0xff, blue: 0x1b/0xff, alpha: 1)
            case "Nvidia", "Intel and Nvidia":
                vGraphics.textColor = NSColor(red: 0x76/0xff, green: 0xb9/0xff, blue: 0/0xff, alpha: 1)
            default: break
            }
        }
    }

    func updateIdea(_ props: NSDictionary) {
        if let val = props["PrimeKeyType"] as? NSString {
            vFnKeyRadio.title = val as String
            if let val = props["FnlockMode"] as? Bool {
                vFnKeyRadio.isEnabled = true
                vFxKeyRadio.isEnabled = true
                if val {
                    vFnKeyRadio.state = .on
                } else {
                    vFxKeyRadio.state = .on
                }
            }
        } else {
            vFnKeyRadio.title = "Unknown"
        }

        if let val = props["AlwaysOnUSBMode"] as? Bool {
            vAlwaysOnUSBMode.state = val ? .on : .off
            vAlwaysOnUSBMode.isEnabled = true
        }

        if let val = props["ConservationMode"] as? Bool {
            vConservationMode.state = val ? .on : .off
            vConservationMode.isEnabled = true
        }

        if let val = props["RapidChargeMode"] as? Bool {
            vRapidChargeMode.state = val ? .on : .off
            vRapidChargeMode.isEnabled = true
        }

        if let dict = props["Battery 0"] as? NSDictionary {
            updateIdeaBattery(dict)
        }

        if let dict = props["Capability"] as? NSDictionary {
            updateIdeaCap(dict)
        }
    }

    func buildIdeaTab() {
        vConservationMode = makeCheckbox("Conservation mode", #selector(vConservationModeSet),
            "Keep the battery charged to about 60% to extend its life, for a machine that stays on AC.")
        vRapidChargeMode = makeCheckbox("Rapid charge", #selector(vRapidChargeModeSet),
            "Charge faster at the cost of battery wear. Usually cannot be combined with conservation mode.")
        vAlwaysOnUSBMode = makeCheckbox("Keep USB powered while asleep or off", #selector(vAlwaysOnUSBModeSet),
            "Always On USB: the yellow USB port keeps supplying power, for charging devices.")
        for box in [vConservationMode, vRapidChargeMode, vAlwaysOnUSBMode] {
            box?.isEnabled = false
        }
        vBatteryID = NSTextField(labelWithString: "Unknown")
        vCycleCount = NSTextField(labelWithString: "Unknown")
        vBatteryTemperature = NSTextField(labelWithString: "Unknown")
        vMfgDate = NSTextField(labelWithString: "Unknown")
        let battery = makeSection("Battery", [
            [vConservationMode], [vRapidChargeMode],
            [NSTextField(labelWithString: "ID:"), vBatteryID],
            [NSTextField(labelWithString: "Cycle count:"), vCycleCount],
            [NSTextField(labelWithString: "Temperature:"), vBatteryTemperature],
            [NSTextField(labelWithString: "Manufacture date:"), vMfgDate]
        ])
        let usb = makeSection("USB", [[vAlwaysOnUSBMode]])

        vCamera = NSTextField(labelWithString: "Camera")
        vBluetooth = NSTextField(labelWithString: "Bluetooth")
        vWireless = NSTextField(labelWithString: "Wireless")
        vWWAN = NSTextField(labelWithString: "WWAN")
        vGraphics = NSTextField(labelWithString: "Graphics")
        for label in [vCamera, vBluetooth, vWireless, vWWAN, vGraphics] {
            label?.textColor = .systemGray
            label?.toolTip = "Green: present and on, gray: off or missing."
        }
        let hardware = makeSection("Hardware reported by firmware", [
            [makeRow([vCamera, vBluetooth, vWireless, vWWAN, vGraphics])],
            [makeNote("Green: present and on, gray: off or missing. Graphics color shows the vendor, " +
                      "hover for the name.")]
        ])

        ideaViewItem.view = makeTabContent([battery, usb, hardware])
    }
}

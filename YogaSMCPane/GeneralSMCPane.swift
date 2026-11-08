//
//  GeneralSMCPane.swift
//  YogaSMCPane
//
//  Created by Zhen on 12/21/20.
//  Copyright © 2020 Zhen. All rights reserved.
//

import AppKit
import Foundation

extension YogaSMCPane {
    @IBAction func DYTCset(_ sender: NSSlider) {
        if DYTCSlider.maxValue == 2 {
            _ = sendString("DYTCMode", DYTCCommand[DYTCSlider.integerValue], service)
        } else {
            _ = sendNumber("DYTCPSCMode", (DYTCSlider.integerValue != 0) ? DYTCSlider.integerValue : 0xf, service)
        }
        if let dict = getDictionary("DYTC", service) {
            updateDYTC(dict)
        }
    }

    @IBAction func backlightSet(_ sender: NSSlider) {
        if !sendNumber("BacklightLevel", backlightSlider.integerValue, service) {
            let backlightLevel = getNumber("BacklightLevel", service)
            if backlightLevel != -1 {
                backlightSlider.integerValue = backlightLevel
            } else {
                backlightSlider.isEnabled = false
            }
        }
    }

    @IBAction func backlightTimeoutSet(_ sender: NSTextField) {
        _ = sendNumber("BacklightTimeout", sender.integerValue, service)
    }

    @IBAction func vClamshellModeSet(_ sender: NSButton) {
        _ = sendBoolean("ClamshellMode", (sender.state == .on), service)
    }

    @IBAction func autoBacklightSet(_ sender: NSButton) {
        let val = ((autoSleepCheck.state == .on) ? 1 << 0 : 0) +
                ((yogaModeCheck.state == .on) ? 1 << 1 : 0) +
                ((indicatorCheck.state == .on) ? 1 << 2 : 0) +
                ((muteCheck.state == .on) ? 1 << 3 : 0) +
                ((micMuteCheck.state == .on) ? 1 << 4 : 0)
        if !sendNumber("AutoBacklight", val, service) {
            let autoBacklight = getNumber("AutoBacklight", service)
            if autoBacklight != -1 {
                autoSleepCheck.state = ((autoBacklight & (1 << 0)) != 0) ? .on : .off
                yogaModeCheck.state =  ((autoBacklight & (1 << 1)) != 0) ? .on : .off
                indicatorCheck.state =  ((autoBacklight & (1 << 2)) != 0) ? .on : .off
                muteCheck.state =  ((autoBacklight & (1 << 3)) != 0) ? .on : .off
                micMuteCheck.state =  ((autoBacklight & (1 << 4)) != 0) ? .on : .off
            } else {
                autoSleepCheck.isEnabled = false
                yogaModeCheck.isEnabled = false
                indicatorCheck.isEnabled = false
                muteCheck.isEnabled = false
                micMuteCheck.isEnabled = false
            }
        }
    }

    @IBAction func DYTCPSCSupport(_ sender: NSButton) {
        defaults.setValue(sender.state == .on, forKey: "DYTCPSC")
        if sender.state == .on {
            DYTCSlider.numberOfTickMarks = 9
            DYTCSlider.maxValue = 8
            DYTCSlider.integerValue = 0
        } else {
            DYTCSlider.numberOfTickMarks = 3
            DYTCSlider.maxValue = 2
            DYTCSlider.integerValue = 1
        }
        dytcCaptions?.isHidden = DYTCSlider.maxValue != 2
    }

    func updateDYTC(_ dict: NSDictionary) {
        if let ver = dict["Revision"] as? NSNumber,
           let subver = dict["SubRevision"] as? NSNumber {
            vDYTCRevision.stringValue = "\(ver.intValue).\(subver.intValue)"
        } else {
            vDYTCRevision.stringValue = "Unknown"
        }
        if let funcMode = dict["FuncMode"] as? String {
            // e.g. UnknownFunc:0xe, a function the driver does not handle
            vDYTCFuncMode.stringValue = funcMode.hasPrefix("UnknownFunc:") ?
                "Other (" + funcMode.dropFirst("UnknownFunc:".count) + ")" : funcMode
        } else {
            vDYTCFuncMode.stringValue = "Unknown"
        }
        if let capabilities = dict["Function Status"] as? NSDictionary {
            let hasMMC = (capabilities["MMC"] != nil)
            let hasPSC = (capabilities["PSC"] != nil)
            DYTCPSCCheck.isHidden = !(hasPSC && hasMMC)
            DYTCSlider.isEnabled = hasPSC || hasMMC
            if hasPSC, !hasMMC {
                DYTCSlider.numberOfTickMarks = 9
                DYTCSlider.maxValue = 8
                DYTCSlider.integerValue = 0
            }
            if !DYTCPSCCheck.isHidden {
                DYTCPSCCheck.state = defaults.bool(forKey: "DYTCPSC") ? .on : .off
                DYTCPSCSupport(DYTCPSCCheck)
            }
        }
        if let perfMode = dict["PerfMode"] as? String {
            DYTCSlider.toolTip = perfMode
            switch perfMode {
            case "Quiet":
                DYTCSlider.integerValue = 0
            case "Balance":
                if DYTCSlider.maxValue == 2 {
                    DYTCSlider.integerValue = 1
                } else {
                    DYTCSlider.integerValue = 0
                }
            case "Performance":
                DYTCSlider.integerValue = 2
            case "Performance (Reduced as lapmode active)":
                DYTCSlider.integerValue = 2
            default:
                DYTCSlider.isEnabled = false
            }
        } else if let perfMode = dict["PerfMode"] as? NSNumber {
            DYTCSlider.toolTip = "\(perfMode.intValue)"
            DYTCSlider.integerValue = perfMode.intValue
        } else {
            DYTCSlider.isEnabled = false
        }
    }

    func updateMain(_ props: NSDictionary) {
        if let val = props["AutoBacklight"] as? NSNumber {
            let autoBacklight = val.intValue
            autoSleepCheck.state = ((autoBacklight & (1 << 0)) != 0) ? .on : .off
            yogaModeCheck.state =  ((autoBacklight & (1 << 1)) != 0) ? .on : .off
            indicatorCheck.state =  ((autoBacklight & (1 << 2)) != 0) ? .on : .off
            muteCheck.state =  ((autoBacklight & (1 << 3)) != 0) ? .on : .off
            micMuteCheck.state =  ((autoBacklight & (1 << 4)) != 0) ? .on : .off
        } else {
            autoSleepCheck.isEnabled = false
            yogaModeCheck.isEnabled = false
            indicatorCheck.isEnabled = false
            micMuteCheck.isEnabled = false
        }
        #if !DEBUG
        if muteCheck.state == .on {
            muteCheck.state = .off
            autoBacklightSet(muteCheck)
        }
        #endif

        if let val = props["BacklightLevel"] as? NSNumber {
            backlightSlider.integerValue = val.intValue
        } else {
            backlightSlider.isEnabled = false
        }

        if let val = props["BacklightTimeout"] as? NSNumber {
            vBackLightTimeout.integerValue = val.intValue
        } else {
            vBackLightTimeout.isEnabled = false
        }

        if let dict = props["DYTC"]  as? NSDictionary {
            updateDYTC(dict)
        } else {
            vDYTCRevision.stringValue = "Unsupported"
        }

        if defaults.bool(forKey: "HideIcon") {
            vHideMenubarIcon.state = .on
        } else {
            vHideMenubarIcon.state = .off
            vMenubarIcon.isEnabled = true
        }
        vMenubarIcon.stringValue = defaults.string(forKey: "Title") ?? ""

        vHideCapsLock.state = defaults.bool(forKey: "HideCapsLock") ? .on : .off

        if let val = props["ClamshellMode"] as? Bool {
            vClamshellMode.isEnabled = true
            vClamshellMode.state = val ? .on : .off
        }
    }
}

// MARK: - Layout

// Document view of a scrollable tab, laid out from the top
private class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}

// Views shown or hidden depending on driver state
private var dytcCaptions: NSView?
private var clamshellNote: NSView?

extension YogaSMCPane {
    func makeNote(_ text: String) -> NSTextField {
        let note = NSTextField(wrappingLabelWithString: text)
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 400
        return note
    }

    func makeCheckbox(_ title: String, _ action: Selector, _ tip: String) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: self, action: action)
        box.toolTip = tip
        return box
    }

    func makeRadio(_ title: String, _ action: Selector, _ tip: String) -> NSButton {
        let radio = NSButton(radioButtonWithTitle: title, target: self, action: action)
        radio.toolTip = tip
        return radio
    }

    func makeSlider(_ max: Int, _ action: Selector, _ tip: String, width: CGFloat = 200) -> NSSlider {
        let slider = NSSlider(value: 0, minValue: 0, maxValue: Double(max), target: self, action: action)
        slider.numberOfTickMarks = max + 1
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.toolTip = tip
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        return slider
    }

    // Slider with captions under the first and last tick marks (and the middle ones if they fit)
    func captionedSlider(_ slider: NSSlider, _ captions: [String]) -> (NSView, NSView) {
        let labels = captions.map { caption -> NSTextField in
            let label = NSTextField(labelWithString: caption)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            return label
        }
        let row = NSStackView(views: labels)
        row.distribution = .equalSpacing
        let column = NSStackView(views: [slider, row])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        row.widthAnchor.constraint(equalTo: slider.widthAnchor).isActive = true
        return (column, row)
    }

    func makeNumberField(_ max: Int, _ action: Selector, _ tip: String, tag: Int = 0) -> NSTextField {
        let field = NSTextField()
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = NSNumber(value: max)
        formatter.allowsFloats = false
        field.formatter = formatter
        field.target = self
        field.action = action
        field.tag = tag
        field.alignment = .right
        field.cell?.sendsActionOnEndEditing = true
        field.toolTip = tip
        field.widthAnchor.constraint(equalToConstant: 50).isActive = true
        return field
    }

    func makeRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    // Titled group of rows: [label, control] or [control] placed under the controls
    func makeSection(_ title: String, _ rows: [[NSView]]) -> NSBox {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 150
        for row in rows {
            let gridRow = grid.addRow(with: row.count == 1 ? [NSGridCell.emptyContentView, row[0]] : row)
            gridRow.yPlacement = .center
        }
        grid.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.title = title
        box.titleFont = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8)
        ])
        box.contentView = content
        return box
    }

    // Hide the grid row that holds the view
    func setRowHidden(_ view: NSView, _ hidden: Bool) {
        var parent = view.superview
        while let current = parent, !(current is NSGridView) {
            parent = current.superview
        }
        var cellView: NSView = view
        while let superview = cellView.superview, !(superview is NSGridView) {
            cellView = superview
        }
        (parent as? NSGridView)?.cell(for: cellView)?.row?.isHidden = hidden
    }

    func makeTabContent(_ sections: [NSView]) -> NSView {
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for section in sections {
            section.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor)
        ])

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        return scroll
    }

    func buildGeneralTab() {
        // Keyboard
        backlightSlider = makeSlider(2, #selector(backlightSet), "Keyboard backlight level, same as Fn-Space.")
        let (backlight, _) = captionedSlider(backlightSlider, ["Off", "Low", "High"])
        vBackLightTimeout = makeNumberField(3600, #selector(backlightTimeoutSet),
            "Turn the keyboard backlight off after this many seconds without typing; " +
            "the next key press turns it back on. 0 disables. Needs VoodooPS2 keyboard driver.")
        autoSleepCheck = makeCheckbox("Restore backlight after wake", #selector(autoBacklightSet),
            "The driver saves the backlight level before sleep and sets it again on wake. " +
            "Turn on if the backlight stays off after wake.")
        vFxKeyRadio = makeRadio("F1–F12", #selector(vFnKeySet),
            "Top row keys act as F1–F12, special functions need Fn. Same as Fn Lock (Fn-Esc).")
        vFnKeyRadio = makeRadio("Special functions", #selector(vFnKeySet),
            "Top row keys act as volume, brightness and so on, F1–F12 need Fn. Same as Fn Lock (Fn-Esc).")
        vFnKeyRadio.isEnabled = false
        vFxKeyRadio.isEnabled = false
        let keyboard = makeSection("Keyboard", [
            [NSTextField(labelWithString: "Backlight:"), backlight],
            [NSTextField(labelWithString: "Turn off after:"),
             makeRow([vBackLightTimeout, NSTextField(labelWithString: "seconds without typing (0 = never)")])],
            [autoSleepCheck],
            [NSTextField(labelWithString: "Top row keys:"), makeRow([vFxKeyRadio, vFnKeyRadio])]
        ])

        // Thermal
        DYTCSlider = makeSlider(2, #selector(DYTCset),
            "Thermal mode set through Lenovo DYTC, like Intelligent Cooling on Windows.")
        DYTCSlider.isEnabled = false
        let (thermal, captions) = captionedSlider(DYTCSlider, ["Quiet", "Balance", "Performance"])
        dytcCaptions = captions
        vDYTCFuncMode = NSTextField(labelWithString: "Unknown")
        vDYTCFuncMode.toolTip = "Standard: default balance. Desk: mode set here. " +
            "Lap: the firmware limits power while it thinks the laptop is on a lap. Controlled: PSC level. " +
            "CSC: on / off function enabled by firmware, replaced by the mode chosen here."
        vDYTCRevision = NSTextField(labelWithString: "Unknown")
        vDYTCRevision.textColor = .secondaryLabelColor
        vDYTCRevision.toolTip = "DYTC interface version."
        DYTCPSCCheck = makeCheckbox("Use PSC levels", #selector(DYTCPSCSupport),
            "Use 9 raw PSC levels instead of the three modes. Linux uses PSC only on AMD machines.")
        DYTCPSCCheck.isHidden = true
        let thermalSection = makeSection("Thermal mode", [
            [NSTextField(labelWithString: "Mode:"), thermal],
            [NSTextField(labelWithString: "Active function:"),
             makeRow([vDYTCFuncMode, NSTextField(labelWithString: "·"), vDYTCRevision])],
            [DYTCPSCCheck]
        ])

        // Menu bar
        vHideMenubarIcon = makeCheckbox("Hide menu bar icon", #selector(toggleMenubarIcon),
            "Run YogaSMCNC without a menu bar item. Hotkeys and notifications keep working, fan controls are hidden.")
        vMenubarIcon = NSTextField()
        vMenubarIcon.target = self
        vMenubarIcon.action = #selector(setMenubarIcon)
        vMenubarIcon.placeholderString = "default"
        vMenubarIcon.isEnabled = false
        vMenubarIcon.toolTip = "Text shown in the menu bar instead of the icon, for example ⌘. Empty restores the icon."
        vMenubarIcon.widthAnchor.constraint(equalToConstant: 80).isActive = true
        vHideCapsLock = makeCheckbox("Hide Caps Lock notification", #selector(toggleHideCapsLock),
            "Do not show the on-screen notification when Caps Lock is toggled. Does not change Caps Lock itself.")
        let clear = NSButton(title: "Clear saved events", target: self, action: #selector(vClearEvents))
        clear.toolTip = "Forget hotkey actions saved by YogaSMCNC and use the built-in ones. Custom hotkeys are kept."
        let menubar = makeSection("Menu bar and notifications", [
            [vHideMenubarIcon],
            [NSTextField(labelWithString: "Custom icon:"),
             makeRow([vMenubarIcon, makeNote("text instead of the icon, applied on Enter")])],
            [vHideCapsLock],
            [clear]
        ])

        // Special modes
        vClamshellMode = makeCheckbox("Clamshell mode", #selector(vClamshellModeSet),
            "Ignore lid opening and keep the keyboard enabled in tablet-like modes.")
        vClamshellMode.isEnabled = false
        let note = makeNote("Not available: needs GCSM / SCSM ACPI methods, see SSDT-RCSM.dsl and PREFPANE.md.")
        clamshellNote = note
        yogaModeCheck = makeCheckbox("Turn off keyboard backlight in tablet mode", #selector(autoBacklightSet),
            "IdeaPad only. On ThinkPad the keyboard is disabled in tablet-like modes anyway.")
        let modes = makeSection("Special modes", [
            [vClamshellMode],
            [note],
            [yogaModeCheck]
        ])

        // Driver
        vClass = NSTextField(labelWithString: "Unknown")
        vVersion = NSTextField(labelWithString: "Unknown")
        vVersion.textColor = .secondaryLabelColor
        vECRead = NSTextField(labelWithString: "Unknown")
        vECRead.toolTip = "Whether the driver can read (R) and write (W) EC fields. Needs EC access methods in ACPI, see SSDT-ECRW.dsl."
        let driver = makeSection("Driver", [
            [NSTextField(labelWithString: "Class:"), makeRow([vClass, vVersion])],
            [NSTextField(labelWithString: "EC access:"), vECRead]
        ])

        mainTabView.tabViewItem(at: 0).view = makeTabContent([keyboard, thermalSection, menubar, modes, driver])
    }

    func updateGeneralLayout(_ props: NSDictionary) {
        dytcCaptions?.isHidden = DYTCSlider.maxValue != 2
        clamshellNote.map { setRowHidden($0, vClamshellMode.isEnabled) }
        setRowHidden(yogaModeCheck, (props["IOClass"] as? String) != "IdeaVPC")
        setRowHidden(vFnKeyRadio.superview ?? vFnKeyRadio, !vFnKeyRadio.isEnabled)
    }
}

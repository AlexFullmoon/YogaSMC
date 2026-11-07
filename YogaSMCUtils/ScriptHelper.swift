//
//  ScriptHelper.swift
//  YogaSMC
//
//  Created by Zhen on 10/14/20.
//  Copyright © 2020 Zhen. All rights reserved.
//

import AppKit
import Foundation
import ScriptingBridge
import os.log

let prefpaneAS = """
                    tell application "System Preferences"
                        reveal pane "org.zhen.YogaSMCPane"
                        activate
                    end tell
                 """

let sleepAS = "tell application \"System Events\" to sleep"

let searchAS = "tell application \"System Events\" to keystroke space using {command down, option down}"
let spotlightAS = "tell application \"System Events\" to keystroke space using command down"
let siriAS = """
                tell application "System Events" to tell the front menu bar of process "SystemUIServer"
                  tell (first menu bar item whose description is "Siri")
                     perform action "AXPress"
                  end tell
                end tell
             """
// macOS 13+, the clock opens Notification Center; match by identifier, the name is localized
let notificationCenterAS = """
                              tell application "System Events" to tell process "ControlCenter"
                                  repeat with mbi in menu bar items of menu bar 1
                                      if value of attribute "AXIdentifier" of mbi is "com.apple.menuextra.clock" then
                                          click mbi
                                          exit repeat
                                      end if
                                  end repeat
                              end tell
                           """
// Fn keys with a user-assigned action, shared by YogaSMCNC and YogaSMCPane.
// Stored as CustomHotkeys = { "<event hex>": { action: launchapp | script, option: <app or AppleScript> } }
let customHotkeysKey = "CustomHotkeys"
let customHotkeys: [(event: UInt32, name: String)] = [
    (TP_HKEY_EV_ZOOM.rawValue, "Fn-Tab"),
    (TP_HKEY_EV_PICKUP_PHONE.rawValue, "Fn-F10"),
    (TP_HKEY_EV_HANGUP_PHONE.rawValue, "Fn-F11"),
    (TP_HKEY_EV_STAR.rawValue, "Fn-F12")
]

let reloadAS = """
                  tell application "YogaSMCNC" to quit
                  tell application "YogaSMCNC" to activate
               """
let stopAS = "tell application \"YogaSMCNC\" to quit"
let startAS = "tell application \"YogaSMCNC\" to activate"

let getAudioMutedAS = "output muted of (get volume settings)"
let setAudioMuteAS = "set volume with output muted"
let setAudioUnmuteAS = "set volume without output muted"

let getMicVolumeAS = "input volume of (get volume settings)"
let setMicVolumeAS = "set volume input volume %d"

// based on https://medium.com/macoclock/1ba82537f7c3
func scriptHelper(_ source: String, _ name: String, _ image: NSString? = nil) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    if let scpt = NSAppleScript(source: source) {
        let ret = scpt.executeAndReturnError(&error)
        if error == nil {
            if let img = image {
                showOSD(name, img)
            }
            return ret
        }
    }
    if #available(macOS 10.12, *) {
        // e.g. -1719 / -25211 when Accessibility permission is missing
        let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
        let message = error?[NSAppleScript.errorMessage] as? String ?? "unknown error"
        os_log("%{public}s: failed to execute script (%d): %{public}s", type: .error, name, code, message)
    }
    return nil
}

// Toggle mirroring of all active displays to the main one
func mirrorHelper(_ name: String, _ display: Bool) {
    var count: UInt32 = 0
    // online list also contains displays already mirrored
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return }

    if count < 2 {
        if #available(macOS 10.12, *) {
            os_log("%s: no second display", type: .info, name)
        }
        if display { showOSD(name) }
        return
    }

    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { return }
    let main = CGMainDisplayID()
    let mirrored = CGDisplayIsInMirrorSet(main) != 0
    for id in displays[..<Int(count)] where id != main {
        CGConfigureDisplayMirrorOfDisplay(config, id, mirrored ? kCGNullDirectDisplay : main)
    }
    CGCompleteDisplayConfiguration(config, .permanently)
    if display { showOSD(name) }
}

func prefpaneHelper() {
    
    let homeDir = NSHomeDirectory()
    let path = "\(homeDir)/Library/PreferencePanes/"
    let path2 = "/Library/PreferencePanes/"
    let url = NSURL(fileURLWithPath: path)
    let url2 = NSURL(fileURLWithPath: path2)
    
    if let pathComponent = url.appendingPathComponent("YogaSMCPane.prefPane"), let pathComponent2 = url2.appendingPathComponent("YogaSMCPane.prefPane") {
            let filePath = pathComponent.path
            let filePath2 = pathComponent2.path
            let fileManager = FileManager.default
        
            if fileManager.fileExists(atPath: filePath ) || fileManager.fileExists(atPath: filePath2 )  {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference")!)
                NSWorkspace.shared.open(URL(fileURLWithPath: "\(homeDir)/Library/PreferencePanes/YogaSMCPane.prefPane"))
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Library/PreferencePanes/YogaSMCPane.prefPane"))
                return
            } else {
                let alert = NSAlert()
                            alert.messageText = "Failed to open Preferences/Settings"
                            alert.informativeText = "Please install YogaSMCPane"
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
            }
        }
    
}

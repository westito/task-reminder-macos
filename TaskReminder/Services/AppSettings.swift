//
//  AppSettings.swift
//  TaskReminder
//

import AppKit
import Foundation
import Observation
import ServiceManagement
import os

/// User preferences, persisted to `UserDefaults` on every write.
///
/// Each preference is a computed property over a tracked private store.
/// `@Observable` does not reliably allow a `didSet` that touches `self`, so
/// the write-through to `UserDefaults` lives in the setter instead.
@Observable
final class AppSettings {
    private enum Key {
        static let alwaysOnTop = "alwaysOnTop"
        static let showPanelOnLaunch = "showPanelOnLaunch"
        static let blinkOnAlert = "blinkOnAlert"
        static let soundOnAlert = "soundOnAlert"
        static let panelOpacity = "panelOpacity"
        static let launchAtLogin = "launchAtLogin"
        static let defaultIntervalMinutes = "defaultIntervalMinutes"
        static let defaultSnoozeMinutes = "defaultSnoozeMinutes"
        static let defaultSoundName = "defaultSoundName"
        static let quarterHourChime = "quarterHourChime"
    }

    static let minimumPanelOpacity: Double = 0.4
    static let maximumPanelOpacity: Double = 1.0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TaskReminder",
        category: "AppSettings"
    )

    private var storedAlwaysOnTop: Bool
    private var storedShowPanelOnLaunch: Bool
    private var storedBlinkOnAlert: Bool
    private var storedSoundOnAlert: Bool
    private var storedPanelOpacity: Double
    private var storedLaunchAtLogin: Bool
    private var storedDefaultIntervalMinutes: Int
    private var storedDefaultSnoozeMinutes: Int
    private var storedDefaultSoundName: String
    private var storedQuarterHourChime: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedAlwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        storedShowPanelOnLaunch = defaults.object(forKey: Key.showPanelOnLaunch) as? Bool ?? true
        storedBlinkOnAlert = defaults.object(forKey: Key.blinkOnAlert) as? Bool ?? true
        storedSoundOnAlert = defaults.object(forKey: Key.soundOnAlert) as? Bool ?? true
        storedPanelOpacity = AppSettings.clampOpacity(
            defaults.object(forKey: Key.panelOpacity) as? Double ?? 1.0
        )
        storedLaunchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        // Must be one of `TaskItem.intervalOptionMinutes`, or the settings
        // picker has no matching row to select.
        storedDefaultIntervalMinutes = defaults.object(forKey: Key.defaultIntervalMinutes) as? Int ?? 30
        storedDefaultSnoozeMinutes = defaults.object(forKey: Key.defaultSnoozeMinutes) as? Int ?? 5
        storedDefaultSoundName = defaults.object(forKey: Key.defaultSoundName) as? String
            ?? SoundLibrary.defaultSoundName
        storedQuarterHourChime = defaults.object(forKey: Key.quarterHourChime) as? Bool ?? false
    }

    // MARK: - New task defaults

    /// Seed values for a freshly added task, so a user who always works in
    /// the same rhythm does not retype them every time.
    var defaultIntervalMinutes: Int {
        get { storedDefaultIntervalMinutes }
        set {
            storedDefaultIntervalMinutes = newValue
            defaults.set(newValue, forKey: Key.defaultIntervalMinutes)
        }
    }

    var defaultSnoozeMinutes: Int {
        get { storedDefaultSnoozeMinutes }
        set {
            storedDefaultSnoozeMinutes = newValue
            defaults.set(newValue, forKey: Key.defaultSnoozeMinutes)
        }
    }

    var defaultSoundName: String {
        get { storedDefaultSoundName }
        set {
            storedDefaultSoundName = newValue
            defaults.set(newValue, forKey: Key.defaultSoundName)
        }
    }

    /// Owned by `QuarterHourChime`; set it through that service so enabling
    /// the chime also plays its confirmation.
    var quarterHourChime: Bool {
        get { storedQuarterHourChime }
        set {
            storedQuarterHourChime = newValue
            defaults.set(newValue, forKey: Key.quarterHourChime)
        }
    }

    var alwaysOnTop: Bool {
        get { storedAlwaysOnTop }
        set {
            storedAlwaysOnTop = newValue
            defaults.set(newValue, forKey: Key.alwaysOnTop)
        }
    }

    var showPanelOnLaunch: Bool {
        get { storedShowPanelOnLaunch }
        set {
            storedShowPanelOnLaunch = newValue
            defaults.set(newValue, forKey: Key.showPanelOnLaunch)
        }
    }

    var blinkOnAlert: Bool {
        get { storedBlinkOnAlert }
        set {
            storedBlinkOnAlert = newValue
            defaults.set(newValue, forKey: Key.blinkOnAlert)
        }
    }

    var soundOnAlert: Bool {
        get { storedSoundOnAlert }
        set {
            storedSoundOnAlert = newValue
            defaults.set(newValue, forKey: Key.soundOnAlert)
        }
    }

    var panelOpacity: Double {
        get { storedPanelOpacity }
        set {
            let clamped = AppSettings.clampOpacity(newValue)
            storedPanelOpacity = clamped
            defaults.set(clamped, forKey: Key.panelOpacity)
        }
    }

    /// Backed by `SMAppService`. Registration is allowed to fail — the app is
    /// ad-hoc signed and may run outside `/Applications` — so a failure only
    /// logs and reverts the stored value rather than propagating.
    var launchAtLogin: Bool {
        get { storedLaunchAtLogin }
        set {
            let previous = storedLaunchAtLogin
            storedLaunchAtLogin = newValue
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                defaults.set(newValue, forKey: Key.launchAtLogin)
            } catch {
                let action = newValue ? "register" : "unregister"
                logger.error("Launch at login \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                storedLaunchAtLogin = previous
            }
        }
    }

    /// Views fall back to a static highlight instead of a pulse when this is
    /// true. Read live rather than cached so a mid-session change applies.
    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func clampOpacity(_ value: Double) -> Double {
        min(max(value, minimumPanelOpacity), maximumPanelOpacity)
    }
}

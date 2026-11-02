//
//  AlertCoordinator.swift
//  TaskReminder
//

import Foundation
import Observation

/// Turns the scheduler's "these tasks are overdue" signal into the in-app
/// alert: sound, blink, and raising the floating panel. Alerting is
/// deliberately in-app only — no system notifications.
///
/// The sound repeats every couple of seconds for as long as a task stays
/// overdue. It stops only when the user acknowledges the task — done,
/// snoozed or disabled — so an alert cannot be missed by looking away.
@Observable
final class AlertCoordinator {
    /// Raises the panel without activating the app. Wired up by `AppServices`.
    @ObservationIgnored var raisePanel: (() -> Void)?

    /// The tasks that are overdue right now. Derived state — nothing about
    /// alerting is persisted.
    private(set) var overdueTaskIDs: Set<UUID> = []

    /// The blink phase views read to drive their highlight.
    private(set) var isBlinking = false

    var hasActiveAlert: Bool { !overdueTaskIDs.isEmpty }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var blinkTimer: Timer?
    @ObservationIgnored private var soundTimer: Timer?

    /// Resolved sound name per overdue task, so the repeat can replay them
    /// without retaining SwiftData models across timer ticks.
    @ObservationIgnored private var alertSounds: [UUID: String] = [:]

    private static let blinkInterval: TimeInterval = 0.6
    private static let soundRepeatInterval: TimeInterval = 2

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Called on every scheduler evaluation with the *full* current set of
    /// overdue tasks. The panel is raised only for tasks that were not
    /// already overdue, so an unattended alert does not fight the user for
    /// window order every second — but the sound keeps repeating.
    func handleOverdue(_ tasks: [TaskItem]) {
        let newlyOverdue = tasks.filter { !overdueTaskIDs.contains($0.id) }
        overdueTaskIDs = Set(tasks.map(\.id))

        var sounds: [UUID: String] = [:]
        for task in tasks {
            sounds[task.id] = task.soundName.isEmpty ? SoundLibrary.defaultSoundName : task.soundName
        }
        alertSounds = sounds

        if !newlyOverdue.isEmpty {
            play(soundsFor: newlyOverdue.map(\.id))
            raisePanel?()
        }

        updateBlink()
        updateSoundRepeat()
    }

    /// Drops one task out of the alert, after it was handled, snoozed or
    /// disabled. This is the acknowledgement that silences the repeat.
    func clear(taskID: UUID) {
        guard overdueTaskIDs.remove(taskID) != nil else { return }
        alertSounds.removeValue(forKey: taskID)
        updateBlink()
        updateSoundRepeat()
    }

    /// Drops every alert at once, for when the countdowns are rescheduled
    /// wholesale and nothing is overdue any more.
    func clearAll() {
        guard hasActiveAlert else { return }
        overdueTaskIDs.removeAll()
        alertSounds.removeAll()
        updateBlink()
        updateSoundRepeat()
    }

    // MARK: - Sound

    /// Plays each distinct sound once. Two tasks sharing a sound must not
    /// stack it into a double beep.
    private func play(soundsFor taskIDs: [UUID]) {
        guard settings.soundOnAlert else { return }
        for name in Set(taskIDs.compactMap { alertSounds[$0] }) {
            SoundLibrary.play(name)
        }
    }

    private func updateSoundRepeat() {
        guard hasActiveAlert, settings.soundOnAlert else {
            stopSoundTimer()
            return
        }
        guard soundTimer == nil else { return }

        let timer = Timer(timeInterval: Self.soundRepeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Re-checked every tick so switching the sound off in
                // Settings silences an alert that is already running.
                guard self.settings.soundOnAlert else {
                    self.stopSoundTimer()
                    return
                }
                self.play(soundsFor: Array(self.overdueTaskIDs))
            }
        }
        // `.common` so the beep keeps going while a menu is open or the panel
        // is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        soundTimer = timer
    }

    private func stopSoundTimer() {
        soundTimer?.invalidate()
        soundTimer = nil
    }

    // MARK: - Blink

    private func updateBlink() {
        guard hasActiveAlert else {
            stopBlinking()
            return
        }

        // Blink switched off, or reduce motion: hold the highlight on instead
        // of pulsing it. Views read `isBlinking` as the highlight strength, so
        // leaving it false here would strand an overdue row in the dim phase.
        guard settings.blinkOnAlert, !settings.reduceMotion else {
            stopBlinkTimer()
            isBlinking = true
            return
        }

        guard blinkTimer == nil else { return }
        isBlinking = true
        let timer = Timer(timeInterval: Self.blinkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isBlinking.toggle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func stopBlinking() {
        stopBlinkTimer()
        isBlinking = false
    }

    private func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }
}

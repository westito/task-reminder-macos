//
//  QuarterHourChime.swift
//  TaskReminder
//

import Foundation
import Observation

/// Sounds a single signal on every quarter hour — :00, :15, :30 and :45.
///
/// Deliberately audio only: no countdown, no badge, nothing on screen. It is
/// a background sense of time passing, not another thing to look at.
///
/// It owns no timer. The scheduler's existing 1 Hz pass drives it, because
/// one poll loop for the whole app is what keeps clock changes, sleep and
/// wake correct without any bookkeeping.
@Observable
final class QuarterHourChime {
    private(set) var isEnabled: Bool

    @ObservationIgnored private let settings: AppSettings

    /// The quarter-hour slot that has already sounded. Comparing slots
    /// instead of counting down is what makes sleep correct: a Mac that
    /// slept through several quarters chimes once on wake, not once per
    /// missed quarter. In memory only — after a relaunch the next boundary
    /// is the right place to resume.
    @ObservationIgnored private var lastChimedSlot: Date?

    init(settings: AppSettings) {
        self.settings = settings
        self.isEnabled = settings.quarterHourChime
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        settings.quarterHourChime = enabled

        guard enabled else { return }
        // Arm against the current slot so switching on at, say, :14 does not
        // chime instantly, then confirm audibly that it is working.
        lastChimedSlot = Self.slot(for: .now)
        SoundLibrary.playFrog()
    }

    /// One evaluation pass, called from the scheduler tick.
    func evaluate(at now: Date) {
        guard isEnabled else { return }

        let current = Self.slot(for: now)
        guard let lastChimedSlot else {
            // First pass after launch: adopt the current slot rather than
            // chiming for a boundary that already went by.
            self.lastChimedSlot = current
            return
        }
        guard current != lastChimedSlot else { return }

        self.lastChimedSlot = current
        SoundLibrary.playFrog()
    }

    /// Truncates an instant to the quarter hour containing it. Resolved
    /// through `Calendar` on each call, so DST and timezone changes behave.
    private static func slot(for date: Date) -> Date {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        parts.minute = ((parts.minute ?? 0) / 15) * 15
        parts.second = 0
        return calendar.date(from: parts) ?? date
    }
}

//
//  TaskItem.swift
//  TaskReminder
//

import Foundation
import SwiftData

/// One project the user rotates between. Every enabled task counts down
/// independently and simultaneously; there is no single "active" task.
///
/// All scheduling is absolute-`Date` arithmetic: `nextFireAt` is a stored
/// instant, never a decrementing remaining-seconds counter. That is what
/// makes sleep/wake correct — a task whose interval elapsed while the Mac
/// was asleep fires exactly once on wake, not once per missed interval.
@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    /// Enabled tasks tick. Disabled tasks do not, and are never overdue.
    var isEnabled: Bool = true

    /// Repeating trigger: how long a work stretch lasts before the task asks
    /// for attention again.
    var intervalSeconds: Double = TaskItem.defaultInterval

    /// The instant this task next becomes overdue. In the past means it is
    /// overdue right now.
    var nextFireAt: Date = Date.now

    var snoozeSeconds: Double = TaskItem.defaultSnooze
    var soundName: String = ""

    /// Optional absolute wall-clock trigger, in minutes since midnight.
    /// `nil` disables the daily reminder.
    var dailyReminderMinutes: Int?

    /// Date-only marker of the last day the daily reminder fired, so it
    /// fires at most once per day.
    var lastDailyReminderDay: Date?

    var glyphKind: String = TaskGlyph.Kind.symbol.rawValue
    var symbolName: String?
    var textGlyph: String?
    var colorHex: String = TaskPalette.defaultHex

    @Relationship(deleteRule: .cascade, inverse: \SubtaskItem.parent)
    var subtasks: [SubtaskItem] = []

    init(
        title: String,
        sortIndex: Int = 0,
        intervalSeconds: Double = TaskItem.defaultInterval,
        snoozeSeconds: Double = TaskItem.defaultSnooze,
        soundName: String,
        glyph: TaskGlyph = .fallback,
        colorHex: String = TaskPalette.defaultHex,
        isEnabled: Bool = true,
        now: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.sortIndex = sortIndex
        self.createdAt = now
        self.isEnabled = isEnabled
        self.intervalSeconds = intervalSeconds
        self.nextFireAt = now.addingTimeInterval(intervalSeconds)
        self.snoozeSeconds = snoozeSeconds
        self.soundName = soundName
        self.glyphKind = glyph.kind.rawValue
        self.symbolName = glyph.symbolName
        self.textGlyph = glyph.textGlyph
        self.colorHex = colorHex
        self.subtasks = []
    }
}

// MARK: - Derived state

extension TaskItem {
    static let defaultInterval: Double = 30 * 60
    static let defaultSnooze: Double = 5 * 60

    /// The interval choices offered anywhere a task's interval is set — the
    /// row's quick picker, the editor and the new-task defaults. Kept in one
    /// place so the lists cannot drift apart.
    static let intervalOptionMinutes = [5, 10, 15, 30, 60]

    /// Composed view of the decomposed glyph fields.
    var glyph: TaskGlyph {
        get { TaskGlyph.make(kind: glyphKind, symbolName: symbolName, textGlyph: textGlyph) }
        set {
            glyphKind = newValue.kind.rawValue
            symbolName = newValue.symbolName
            textGlyph = newValue.textGlyph
        }
    }

    /// Overdue is derived from the stored fire date, never stored itself —
    /// so it survives relaunch and sleep without any bookkeeping.
    func isOverdue(at now: Date = .now) -> Bool {
        isEnabled && nextFireAt <= now
    }

    /// Seconds until the task fires. Negative once it is overdue.
    func remainingSeconds(at now: Date = .now) -> TimeInterval {
        nextFireAt.timeIntervalSince(now)
    }

    /// Progress through the current interval, 0 at the start and 1 when due.
    /// Clamped, so an overdue task reads as a full ring.
    func progress(at now: Date = .now) -> Double {
        guard intervalSeconds > 0 else { return 1 }
        let elapsed = intervalSeconds - remainingSeconds(at: now)
        return min(max(elapsed / intervalSeconds, 0), 1)
    }

    /// The daily reminder time resolved against today's calendar, or `nil`
    /// when the daily trigger is off. Resolved fresh on each evaluation so
    /// DST shifts and timezone changes behave.
    func dailyReminderDate(on day: Date, calendar: Calendar = .current) -> Date? {
        guard let dailyReminderMinutes else { return nil }
        return calendar.date(
            bySettingHour: dailyReminderMinutes / 60,
            minute: dailyReminderMinutes % 60,
            second: 0,
            of: day
        )
    }
}

// MARK: - Scheduler transitions

extension TaskItem {
    /// The user handled the task: start the next interval.
    ///
    /// However late the acknowledgement is, that overtime is taken off the
    /// next interval. Answering a 15-minute task 4 minutes late therefore
    /// fires the next one in 11 minutes, keeping the original cadence
    /// instead of walking the whole schedule later on every round.
    func markHandled(at now: Date = .now) {
        nextFireAt = now.addingTimeInterval(intervalSeconds - recoverableOvertime(at: now))
    }

    /// How overdue the task is, but only while that is still absorbable by
    /// one interval.
    ///
    /// Once the overtime reaches a full interval the cadence is past saving:
    /// subtracting it would land the next fire at or before `now`, so the
    /// task would alert again instantly and every acknowledgement after it
    /// would too. At that point the cycle restarts clean from now, which is
    /// what returning zero here does.
    private func recoverableOvertime(at now: Date) -> TimeInterval {
        guard intervalSeconds > 0 else { return 0 }
        let overtime = now.timeIntervalSince(nextFireAt)
        guard overtime > 0, overtime < intervalSeconds else { return 0 }
        return overtime
    }

    /// Push the task out by its snooze duration.
    func snooze(at now: Date = .now) {
        nextFireAt = now.addingTimeInterval(snoozeSeconds)
    }

    /// Make the task overdue right now, used by the daily wall-clock trigger.
    func fireNow(at now: Date = .now) {
        nextFireAt = now
    }

    /// Turning a task off clears its countdown; turning it on restarts a
    /// fresh interval rather than resuming a stale one.
    func setEnabled(_ enabled: Bool, at now: Date = .now) {
        isEnabled = enabled
        if enabled {
            nextFireAt = now.addingTimeInterval(intervalSeconds)
        }
    }
}

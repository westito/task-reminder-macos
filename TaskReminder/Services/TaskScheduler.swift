//
//  TaskScheduler.swift
//  TaskReminder
//

import Foundation
import Observation
import SwiftData
import os

/// The single tick loop for every task. Polling once a second is chosen over
/// precisely scheduled wake-ups on purpose: it absorbs clock changes, sleep,
/// wake and edits without any bookkeeping.
///
/// The tick itself never writes to SwiftData. It only reads the stored
/// `nextFireAt` dates to detect threshold crossings; the UI derives its live
/// countdown from the same dates inside a `TimelineView`. Persistence happens
/// on real transitions only — a fired daily reminder, handled, snoozed,
/// enabled or disabled.
@Observable
final class TaskScheduler {
    private(set) var isRunning = false

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let alerts: AlertCoordinator
    @ObservationIgnored private let chime: QuarterHourChime
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var activityRecordedAt: Date?
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TaskReminder",
        category: "TaskScheduler"
    )

    /// The last moment the app was known to be running. Read once at launch
    /// to work out how long it was gone.
    private static let lastActiveKey = "schedulerLastActiveAt"
    /// How often the running app refreshes that marker. A crash or a power
    /// cut therefore mis-accounts at most this much downtime.
    private static let activityRecordInterval: TimeInterval = 15

    init(
        modelContext: ModelContext,
        alerts: AlertCoordinator,
        chime: QuarterHourChime,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.alerts = alerts
        self.chime = chime
        self.defaults = defaults
    }

    // MARK: - Suspending across launches

    /// Shifts every enabled task forward by however long the app was not
    /// running, so quitting pauses the countdowns rather than letting them
    /// drain while the app is closed.
    ///
    /// Deliberately applied only at launch. Sleep and wake must *not* do
    /// this: a task whose interval elapsed while the Mac slept still has to
    /// fire on wake, which is why the wake observer only re-evaluates.
    ///
    /// This does not break absolute-`Date` scheduling. `nextFireAt` stays the
    /// single source of truth and no remaining-seconds counter is stored —
    /// the downtime is applied once, as a one-off shift of those dates.
    func resumeFromLastRun() {
        defer { recordActivity(at: .now) }

        guard let lastActive = defaults.object(forKey: Self.lastActiveKey) as? Date else { return }
        let downtime = Date.now.timeIntervalSince(lastActive)
        // A system clock that moved backwards must never pull tasks forward.
        guard downtime > 0 else { return }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { $0.isEnabled }
        )
        guard let tasks = try? modelContext.fetch(descriptor), !tasks.isEmpty else { return }

        for task in tasks {
            task.nextFireAt = task.nextFireAt.addingTimeInterval(downtime)
        }
        save()

        logger.info("Resumed after \(downtime, format: .fixed(precision: 0), privacy: .public)s of downtime")
    }

    private func recordActivity(at now: Date) {
        activityRecordedAt = now
        defaults.set(now, forKey: Self.lastActiveKey)
    }

    /// Throttled so the marker costs one small write every few seconds
    /// rather than one per tick.
    private func recordActivityIfDue(at now: Date) {
        if let activityRecordedAt,
           now.timeIntervalSince(activityRecordedAt) < Self.activityRecordInterval {
            return
        }
        recordActivity(at: now)
    }

    // MARK: - Tick loop

    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateNow()
            }
        }
        // Tolerance lets the system coalesce the wake-up; `.common` keeps the
        // timer firing while a menu is open or the panel is being dragged.
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true

        evaluateNow()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        // Called on termination, so this is the accurate shutdown marker the
        // next launch measures its downtime against.
        recordActivity(at: .now)
    }

    // MARK: - Evaluation

    /// One evaluation pass. Also called directly from the wake observer, so a
    /// Mac that slept through several intervals alerts once on wake rather
    /// than once per missed interval.
    func evaluateNow() {
        let now = Date.now
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { $0.isEnabled }
        )

        let tasks: [TaskItem]
        do {
            tasks = try modelContext.fetch(descriptor)
        } catch {
            logger.error("Task fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Separation between alerts is the user's to arrange, via the
        // uniform-interval action that spreads every task evenly. The
        // scheduler no longer nudges tasks apart on its own.
        if fireDueDailyReminders(in: tasks, at: now) {
            save()
        }

        let overdue = tasks.filter { $0.isOverdue(at: now) }
        alerts.handleOverdue(overdue)
        chime.evaluate(at: now)
        recordActivityIfDue(at: now)
    }

    /// Resolves each daily trigger against `Calendar.current` on *this* pass,
    /// so DST shifts and timezone changes are picked up without stored state.
    /// Returns whether anything fired — the only reason a tick may save.
    private func fireDueDailyReminders(in tasks: [TaskItem], at now: Date) -> Bool {
        let calendar = Calendar.current
        var didFire = false

        for task in tasks {
            guard let dueToday = task.dailyReminderDate(on: now, calendar: calendar),
                  now >= dueToday
            else { continue }

            if let lastDay = task.lastDailyReminderDay,
               calendar.isDate(lastDay, inSameDayAs: now) {
                continue
            }

            task.lastDailyReminderDay = calendar.startOfDay(for: now)
            task.fireNow(at: now)
            didFire = true
        }

        return didFire
    }

    // MARK: - Transitions

    /// Done / switch: the task starts a fresh interval.
    func markHandled(_ task: TaskItem) {
        guard isLive(task) else { return }
        task.markHandled(at: .now)
        alerts.clear(taskID: task.id)
        save()
    }

    func snooze(_ task: TaskItem) {
        guard isLive(task) else { return }
        task.snooze(at: .now)
        alerts.clear(taskID: task.id)
        save()
    }

    /// Enabling restarts a full interval, so the task is not overdue either
    /// way — both directions leave the alert set.
    func setEnabled(_ task: TaskItem, to enabled: Bool) {
        guard isLive(task) else { return }
        task.setEnabled(enabled, at: .now)
        alerts.clear(taskID: task.id)
        save()
    }

    // MARK: - Uniform interval

    /// Sets one interval on every task and restarts the countdowns so the
    /// enabled ones fall due evenly spread across that interval rather than
    /// all at once. Overwrites whatever interval each task had.
    ///
    /// With three tasks and fifteen minutes they come due at five, ten and
    /// fifteen minutes. They then stay five minutes apart on their own,
    /// because from that point they all repeat on the same period.
    func applyUniformInterval(seconds: TimeInterval) {
        guard seconds > 0 else { return }

        let now = Date.now
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\TaskItem.sortIndex)]
        )
        guard let tasks = try? modelContext.fetch(descriptor), !tasks.isEmpty else { return }

        // Disabled tasks get the interval too, so they inherit the new
        // cadence whenever they are switched back on.
        for task in tasks where isLive(task) {
            task.intervalSeconds = seconds
        }

        let enabled = tasks.filter { isLive($0) && $0.isEnabled }
        if !enabled.isEmpty {
            let step = seconds / Double(enabled.count)
            for (index, task) in enabled.enumerated() {
                // Offsets run from one step out to the full interval, so no
                // task is due the instant the user presses the button.
                task.nextFireAt = now.addingTimeInterval(step * Double(index + 1))
            }
        }

        save()

        // Nothing is overdue any more, so any alert still running refers to a
        // countdown that no longer exists.
        alerts.clearAll()
        evaluateNow()

        logger.info("Applied uniform interval of \(seconds, format: .fixed(precision: 0), privacy: .public)s across \(enabled.count, privacy: .public) enabled tasks")
    }

    /// Whether a model is still backed by a row.
    ///
    /// Mutating a model whose row has gone — deleted here, or wiped from the
    /// store by another process — makes CoreData fire a fault it cannot
    /// fulfil. That throws an Objective-C exception, which `try` cannot
    /// catch, so it takes the whole app down rather than surfacing as an
    /// error. Checking first is the only defence.
    private func isLive(_ task: TaskItem) -> Bool {
        !task.isDeleted && task.modelContext != nil
    }

    private func save() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

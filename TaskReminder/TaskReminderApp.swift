//
//  TaskReminderApp.swift
//  TaskReminder
//

import AppKit
import SwiftData
import SwiftUI

@main
struct TaskReminderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The app's real surfaces are both AppKit-hosted: the floating panel and
    /// the settings window. This scene exists only because `App` requires
    /// one — it is deliberately inert. Settings cannot go through the
    /// `Settings` scene, because nothing can open it in an `LSUIElement` app
    /// on macOS 26; see `SettingsWindowController`.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Persistence

/// The single `ModelContainer` for the process. It is injected twice: into
/// the SwiftUI scenes via `.modelContainer(_:)`, and into the floating
/// panel's `NSHostingView` root view — the panel is built from AppKit and
/// does not inherit the scene environment.
enum PersistenceStack {
    /// Where the SQLite file lives.
    ///
    /// SwiftData's default is `Application Support/default.store`. Outside
    /// the sandbox that is a *shared* directory and `default.store` is the
    /// name every framework-default SwiftData app picks, so unrelated
    /// processes end up on the same file — `/usr/libexec/icloudmailagent`
    /// was observed holding this app's store open read-write. Whichever
    /// process opens it with a mismatched schema migrates it destructively
    /// and silently wipes the other's tables.
    ///
    /// An app-owned subdirectory plus a unique filename removes the whole
    /// class of problem.
    static let storeURL: URL = {
        let directory = URL.applicationSupportDirectory
            .appending(path: "TaskReminder", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appending(path: "TaskReminder.store")
    }()

    static let container: ModelContainer = {
        let schema = Schema([TaskItem.self, SubtaskItem.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            // The store is the source of truth, not the context. Autosave is
            // a backstop under the explicit `save()` calls on every
            // transition, so a crash cannot strand a change in memory.
            container.mainContext.autosaveEnabled = true
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

// MARK: - Services

/// Owns the long-lived services and keeps their wiring in one place.
@MainActor
final class AppServices {
    let settings: AppSettings
    let alerts: AlertCoordinator
    let chime: QuarterHourChime
    let scheduler: TaskScheduler
    let panel: FloatingPanelController
    let settingsWindow: SettingsWindowController

    init() {
        let context = PersistenceStack.container.mainContext
        let settings = AppSettings()
        let alerts = AlertCoordinator(settings: settings)
        let chime = QuarterHourChime(settings: settings)
        let scheduler = TaskScheduler(modelContext: context, alerts: alerts, chime: chime)
        let panel = FloatingPanelController(settings: settings)
        let settingsWindow = SettingsWindowController()

        self.settings = settings
        self.alerts = alerts
        self.chime = chime
        self.scheduler = scheduler
        self.panel = panel
        self.settingsWindow = settingsWindow

        // The coordinator raises the panel when a task comes due. It never
        // activates the app — that would steal focus from the user's work.
        alerts.raisePanel = { [weak panel] in panel?.raiseWithoutStealingFocus() }
        // `panel` is captured weakly: the controller owns this closure, so a
        // strong capture would make it retain itself.
        panel.makeRootView = { [scheduler, alerts, settings, chime, settingsWindow, weak panel] in
            AnyView(
                TaskListView(mode: .full)
                    .environment(scheduler)
                    .environment(alerts)
                    .environment(settings)
                    .environment(chime)
                    .environment(settingsWindow)
                    .environment(panel)
                    .modelContainer(PersistenceStack.container)
            )
        }

        // `settingsWindow` is captured weakly for the same reason as the
        // panel: the controller owns this closure.
        settingsWindow.makeRootView = { [settings, chime, weak panel] in
            AnyView(
                SettingsView()
                    .environment(settings)
                    .environment(chime)
                    .environment(panel)
                    .modelContainer(PersistenceStack.container)
            )
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()

    /// Held for the app's lifetime. Without it App Nap throttles the 1 Hz
    /// timer once the app has been in the background for a while.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Task countdowns must keep ticking in the background"
        )

        // Before seeding, so freshly created sample tasks are never shifted,
        // and before starting, so the first evaluation already sees the
        // corrected fire dates.
        services.scheduler.resumeFromLastRun()

        SeedData.installIfNeeded(in: PersistenceStack.container.mainContext)

        services.scheduler.start()
        if services.settings.showPanelOnLaunch {
            services.panel.show()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [services] _ in
            MainActor.assumeIsolated { services.scheduler.evaluateNow() }
        }
    }

    /// Relaunching an already-running app only sends a reopen event. This app
    /// has no Dock icon, and its menu bar item can be hidden by a menu bar
    /// manager such as Bartender, so without this the user has no way back to
    /// a panel they closed — launching it again would appear to do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services.panel.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.scheduler.stop()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }
}

// MARK: - Seed data

enum SeedData {
    /// Set the first time seeding runs, so it can never run twice.
    private static let didSeedKey = "didInstallSeedData"

    /// Populates a brand-new store with two example tasks so the first
    /// launch is not an empty panel.
    ///
    /// Gated on a stored flag rather than on the task count alone. Counting
    /// cannot tell a genuinely new install from a store that failed to open
    /// or was wiped underneath us, and in those cases writing samples
    /// destroys evidence and papers over the fault.
    static func installIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didSeedKey) else { return }

        let existing = (try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0
        guard existing == 0 else {
            defaults.set(true, forKey: didSeedKey)
            return
        }

        let samples = [
            TaskItem(
                title: "AICube",
                sortIndex: 0,
                intervalSeconds: 45 * 60,
                soundName: SoundLibrary.defaultSoundName,
                glyph: .text("AI"),
                colorHex: TaskPalette.hex(forIndex: 0)
            ),
            TaskItem(
                title: "3D print - box",
                sortIndex: 1,
                intervalSeconds: 25 * 60,
                soundName: SoundLibrary.defaultSoundName,
                glyph: .text("3D"),
                colorHex: TaskPalette.hex(forIndex: 5)
            ),
        ]
        for sample in samples {
            context.insert(sample)
        }
        try? context.save()
        defaults.set(true, forKey: didSeedKey)
    }
}

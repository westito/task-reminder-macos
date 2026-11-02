//
//  SettingsWindowController.swift
//  TaskReminder
//

import AppKit
import SwiftUI

/// Owns the settings window.
///
/// Settings deliberately does *not* go through SwiftUI's `Settings` scene.
/// `showSettingsWindow:` was removed after Sonoma, and on macOS 26 both
/// `SettingsLink` and `@Environment(\.openSettings)` need a live SwiftUI
/// render tree to resolve against — which an `LSUIElement` app driving an
/// AppKit-hosted panel does not have. Hosting the view in a plain `NSWindow`
/// is the only route here that is actually under our control.
@Observable
final class SettingsWindowController {
    /// Set by the app wiring. The window is built from AppKit and does not
    /// inherit the SwiftUI scene environment, so the root view — including
    /// the model container — is supplied here.
    @ObservationIgnored var makeRootView: (() -> AnyView)?

    @ObservationIgnored private var window: NSWindow?

    private static let frameAutosaveName = "TaskReminderSettingsWindow"

    func show() {
        let window = ensureWindow()
        // Opening settings is an explicit user request, so taking focus is
        // correct here — unlike the alert path, which must never steal it.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TaskReminder Settings"
        // The controller holds the only reference; closing must not free it.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: makeRootView?() ?? AnyView(EmptyView()))
        window.center()
        window.setFrameAutosaveName(Self.frameAutosaveName)

        self.window = window
        return window
    }
}

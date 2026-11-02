//
//  FloatingPanelController.swift
//  TaskReminder
//

import AppKit
import SwiftUI

/// Owns the floating panel window: creates it lazily, keeps its level and
/// frame in sync with `AppSettings`, and raises it for alerts.
@Observable
final class FloatingPanelController {
    /// Set by the app wiring after construction. The panel is built from
    /// AppKit and does not inherit the SwiftUI scene environment, so the
    /// root view — including the model container — is supplied here.
    @ObservationIgnored var makeRootView: (() -> AnyView)?

    private(set) var isVisible = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var panel: FloatingPanel?
    @ObservationIgnored private var windowDelegate: PanelWindowDelegate?

    private static let frameAutosaveName = "TaskReminderFloatingPanel"

    init(settings: AppSettings) {
        self.settings = settings
        observeSettings()
    }

    // MARK: - Visibility

    func show() {
        present()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    /// Brings the panel forward during an alert. `orderFrontRegardless()`
    /// moves it to the front of its level while the app stays in the
    /// background; `NSApp.activate` would yank focus out of whatever the
    /// user is typing in.
    func raiseWithoutStealingFocus() {
        present()
    }

    private func present() {
        let panel = ensurePanel()
        // A display can be unplugged while the panel is hidden, which would
        // otherwise bring it back somewhere the user cannot reach.
        if !Self.isUsableOnAttachedScreen(panel.frame) {
            panel.setFrame(Self.defaultFrame(), display: false)
        }
        panel.orderFrontRegardless()
        isVisible = true
    }

    fileprivate func panelDidClose() {
        isVisible = false
    }

    // MARK: - Panel construction

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }

        let panel = FloatingPanel(contentRect: Self.defaultFrame())
        let delegate = PanelWindowDelegate(controller: self)
        windowDelegate = delegate
        panel.delegate = delegate
        panel.contentView = NSHostingView(rootView: rootView())

        restoreFrame(for: panel)
        applyLevel(to: panel)

        self.panel = panel
        return panel
    }

    private func rootView() -> some View {
        GlassContainer { makeRootView?() ?? AnyView(EmptyView()) }
            .environment(settings)
    }

    // MARK: - Settings

    private func observeSettings() {
        withObservationTracking {
            _ = settings.alwaysOnTop
        } onChange: { [weak self] in
            // `onChange` fires before the new value is stored, so read it
            // on the next main-actor turn, then re-arm the tracking.
            Task { @MainActor in
                guard let self else { return }
                self.applyLevel(to: self.panel)
                self.observeSettings()
            }
        }
        // `panelOpacity` needs no AppKit work: `GlassContainer` reads it
        // from the environment, so SwiftUI re-renders the glass layer
        // without rebuilding the hosting view.
    }

    private func applyLevel(to panel: FloatingPanel?) {
        panel?.level = settings.alwaysOnTop ? .floating : .normal
    }

    // MARK: - Frame persistence

    private func restoreFrame(for panel: FloatingPanel) {
        // Restore first, then enable autosaving: naming the window saves
        // its current frame, which would overwrite the stored one.
        let restored = panel.setFrameUsingName(Self.frameAutosaveName)
        if !restored || !Self.isUsableOnAttachedScreen(panel.frame) {
            panel.setFrame(Self.defaultFrame(), display: false)
        }
        _ = panel.setFrameAutosaveName(Self.frameAutosaveName)
    }

    /// A frame saved on a display that is no longer attached would put the
    /// panel somewhere the user cannot reach it.
    private static func isUsableOnAttachedScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 80 && overlap.height >= 40
        }
    }

    private static func defaultFrame() -> NSRect {
        let size = PanelMetrics.defaultSize
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        let margin = PanelMetrics.screenMargin
        return NSRect(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin,
            width: size.width,
            height: size.height
        )
    }
}

/// Separate from the controller so the controller stays a plain
/// `@Observable` class instead of an `NSObject` subclass.
private final class PanelWindowDelegate: NSObject, NSWindowDelegate {
    private weak var controller: FloatingPanelController?

    init(controller: FloatingPanelController) {
        self.controller = controller
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        controller?.panelDidClose()
    }
}

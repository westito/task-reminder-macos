//
//  FloatingPanel.swift
//  TaskReminder
//

import AppKit

/// Geometry shared by the panel window and the glass it draws behind its
/// content, so the two agree on where the rounded edge is.
enum PanelMetrics {
    /// Close enough to the system window rounding that the glass reaches
    /// the edge without bleeding past the window's own clip.
    static let cornerRadius: CGFloat = 20
    static let defaultSize = CGSize(width: 320, height: 420)
    static let minSize = CGSize(width: 260, height: 240)
    /// Inset of the default frame from the top-right of the main screen.
    static let screenMargin: CGFloat = 24
}

/// The always-available task panel.
///
/// Every flag set here is load-bearing. The panel has to accept key status
/// so text fields inside it work, yet it must never activate the app or
/// take focus away from whatever the user is working in.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // No `.closable`: the close control lives inside the widget, so a
            // titlebar button floating above the content would duplicate it.
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Key only when a control actually needs it, and never dismissed
        // because another app came forward.
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        // The controller holds the only reference; closing must not free it.
        isReleasedWhenClosed = false

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // The glass is drawn by the SwiftUI content. An opaque window
        // background would paint straight over it.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Follow the user between Spaces and stay usable next to a
        // full-screen app.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        minSize = NSSize(width: PanelMetrics.minSize.width, height: PanelMetrics.minSize.height)
    }

    /// Text fields need key status; main status would make the panel the
    /// app's principal window and pull focus on click.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

//
//  GlassContainer.swift
//  TaskReminder
//

import AppKit
import SwiftUI

/// Wraps the panel's root content in its translucent background.
///
/// Glass belongs to the functional layer only: the panel background and
/// its controls get it, task rows stay flat so they remain legible.
///
/// This is the `NSVisualEffectView` rung of the fallback ladder, not the
/// SwiftUI `.glassEffect` one. `NSGlassEffectView`, which backs
/// `.glassEffect`, renders hosted `NSHostingView` content blank on macOS 26
/// — the material composites over the SwiftUI layer instead of behind it,
/// which blurs text away entirely. Controls still use `.buttonStyle(.glass)`;
/// only the panel backdrop had to come down a rung.
struct GlassContainer<Content: View>: View {
    /// Injected by `FloatingPanelController`. Optional so previews and the
    /// menu bar popover can use the container without a settings object.
    @Environment(AppSettings.self) private var settings: AppSettings?

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background {
                // Opacity rides on the backdrop alone. Fading the content
                // instead would make the task list unreadable.
                PanelBackdrop()
                    .opacity(settings?.panelOpacity ?? 1)
            }
    }
}

/// The panel's blurred backdrop.
private struct PanelBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // The panel is *always* in the background by design — it must never
        // take focus. The default `.followsWindowActiveState` would therefore
        // leave the backdrop permanently greyed out.
        view.state = .active

        // Round the layer itself rather than relying on a SwiftUI clip:
        // clipping a hosted AppKit view leaves aliased corners.
        view.wantsLayer = true
        view.layer?.cornerRadius = PanelMetrics.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

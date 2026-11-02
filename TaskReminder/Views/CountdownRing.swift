//
//  CountdownRing.swift
//  TaskReminder
//

import SwiftUI

/// A clock-style wedge filled from 12 o'clock clockwise.
///
/// The task badge uses this as its background, so the whole icon *is* the
/// countdown. A separate ring alongside the icon would compete with it for
/// space and say the same thing twice.
nonisolated struct ProgressSweep: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        // The wedge backs a rounded rectangle, so the radius has to reach the
        // furthest corner — not the nearest edge, which would leave the
        // corners unfilled at full progress.
        let radius = (rect.width * rect.width + rect.height * rect.height).squareRoot()

        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clamped),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

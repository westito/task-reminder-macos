//
//  TaskPalette.swift
//  TaskReminder
//

import SwiftUI

/// The fixed set of accent colours a task or subtask may carry, plus the
/// hex <-> `Color` conversion used to persist them as scalar strings.
nonisolated enum TaskPalette {
    struct Entry: Identifiable, Hashable, Sendable {
        let name: String
        let hex: String

        var id: String { hex }
        var color: Color { TaskPalette.color(forHex: hex) }
    }

    static let entries: [Entry] = [
        Entry(name: "Blue", hex: "#3B82F6"),
        Entry(name: "Indigo", hex: "#6366F1"),
        Entry(name: "Purple", hex: "#A855F7"),
        Entry(name: "Pink", hex: "#EC4899"),
        Entry(name: "Red", hex: "#EF4444"),
        Entry(name: "Orange", hex: "#F97316"),
        Entry(name: "Amber", hex: "#F59E0B"),
        Entry(name: "Lime", hex: "#84CC16"),
        Entry(name: "Green", hex: "#22C55E"),
        Entry(name: "Teal", hex: "#14B8A6"),
        Entry(name: "Cyan", hex: "#06B6D4"),
        Entry(name: "Slate", hex: "#94A3B8"),
    ]

    static let defaultHex = entries[0].hex

    /// A colour for a task that has none yet, cycled so freshly created
    /// tasks do not all look alike.
    static func hex(forIndex index: Int) -> String {
        entries[abs(index) % entries.count].hex
    }

    /// Parses `#RRGGBB` (with or without the leading `#`). Unparseable
    /// input yields the default colour rather than failing, so a corrupt
    /// stored value can never break rendering.
    static func color(forHex hex: String) -> Color {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let packed = UInt32(value, radix: 16) else { return .blue }
        return Color(
            .sRGB,
            red: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255,
            opacity: 1
        )
    }
}

//
//  TaskGlyph.swift
//  TaskReminder
//

import Foundation

/// The badge shown for a task or subtask: either an SF Symbol or a short
/// text abbreviation such as "AI" or "3D".
///
/// Stored on the models as decomposed scalar fields (`glyphKind`,
/// `symbolName`, `textGlyph`) rather than as a `Codable` enum, because
/// enums with associated values crash SwiftData on delete and cannot be
/// used in predicates.
nonisolated enum TaskGlyph: Hashable, Sendable {
    case symbol(String)
    case text(String)

    static let fallback = TaskGlyph.symbol("circle.dashed")

    /// Maximum number of characters a text glyph may contain.
    static let textLimit = 3

    var kind: Kind {
        switch self {
        case .symbol: .symbol
        case .text: .text
        }
    }

    var symbolName: String? {
        if case let .symbol(name) = self { return name }
        return nil
    }

    var textGlyph: String? {
        if case let .text(text) = self { return text }
        return nil
    }

    enum Kind: String, Sendable {
        case symbol
        case text
    }

    /// Rebuilds a glyph from persisted scalar fields, falling back to a
    /// placeholder when the stored combination is incomplete.
    static func make(kind: String, symbolName: String?, textGlyph: String?) -> TaskGlyph {
        switch Kind(rawValue: kind) {
        case .text:
            guard let textGlyph, !textGlyph.isEmpty else { return .fallback }
            return .text(textGlyph)
        case .symbol, nil:
            guard let symbolName, !symbolName.isEmpty else { return .fallback }
            return .symbol(symbolName)
        }
    }

    /// Trims a user-entered abbreviation to the supported length.
    static func sanitizedText(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(textLimit))
    }
}

extension TaskGlyph {
    /// SF Symbols offered in the glyph picker, grouped for display.
    static let symbolCatalog: [(section: String, symbols: [String])] = [
        ("Work", [
            "laptopcomputer", "desktopcomputer", "keyboard", "terminal",
            "chevron.left.forwardslash.chevron.right", "hammer", "wrench.and.screwdriver",
            "briefcase", "doc.text", "pencil.and.ruler",
        ]),
        ("Making", [
            "cube", "printer", "paintbrush", "paintpalette", "scissors",
            "ruler", "gearshape.2", "screwdriver", "camera", "guitars",
        ]),
        ("Life", [
            "house", "cart", "fork.knife", "cup.and.saucer", "bed.double",
            "figure.run", "dumbbell", "leaf", "pawprint", "heart",
        ]),
        ("Signals", [
            "bell", "alarm", "flag", "star", "bolt",
            "flame", "sparkles", "target", "lightbulb", "brain.head.profile",
        ]),
    ]
}

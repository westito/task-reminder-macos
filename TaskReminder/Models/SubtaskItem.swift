//
//  SubtaskItem.swift
//  TaskReminder
//

import Foundation
import SwiftData

/// A purely organisational child of a `TaskItem`. Subtasks carry a title,
/// a glyph and a colour — deliberately no timers, intervals or alerts.
@Model
final class SubtaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var sortIndex: Int = 0

    var glyphKind: String = TaskGlyph.Kind.symbol.rawValue
    var symbolName: String?
    var textGlyph: String?
    var colorHex: String = TaskPalette.defaultHex

    var parent: TaskItem?

    init(
        title: String,
        sortIndex: Int = 0,
        glyph: TaskGlyph = .fallback,
        colorHex: String = TaskPalette.defaultHex
    ) {
        self.id = UUID()
        self.title = title
        self.sortIndex = sortIndex
        self.glyphKind = glyph.kind.rawValue
        self.symbolName = glyph.symbolName
        self.textGlyph = glyph.textGlyph
        self.colorHex = colorHex
    }
}

extension SubtaskItem {
    var glyph: TaskGlyph {
        get { TaskGlyph.make(kind: glyphKind, symbolName: symbolName, textGlyph: textGlyph) }
        set {
            glyphKind = newValue.kind.rawValue
            symbolName = newValue.symbolName
            textGlyph = newValue.textGlyph
        }
    }
}

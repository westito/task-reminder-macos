//
//  GlyphPickerView.swift
//  TaskReminder
//

import SwiftUI

/// Renders a `TaskGlyph` as a tinted badge. Shared by rows, pickers and the
/// editor so a glyph looks identical everywhere it appears.
struct GlyphBadge: View {
    let glyph: TaskGlyph
    let color: Color
    var size: CGFloat = 28

    /// Countdown progress, 0 at the start of the interval and 1 when due.
    /// `nil` everywhere the badge is only an icon — pickers and the editor.
    var progress: Double?
    var isOverdue: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    /// The glyph sits on top of the sweep, so it has to switch to white once
    /// the fill behind it is dense enough to swallow the accent colour.
    private var glyphColor: Color {
        isOverdue ? .white : color
    }

    var body: some View {
        ZStack {
            shape.fill(color.opacity(0.16))

            if let progress {
                shape
                    .fill(color.opacity(isOverdue ? 0.9 : 0.45))
                    .mask { ProgressSweep(progress: isOverdue ? 1 : progress) }
            }

            glyphContent
        }
        .frame(width: size, height: size)
        .overlay {
            shape.strokeBorder(color.opacity(isOverdue ? 0.9 : 0.35), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var glyphContent: some View {
        switch glyph {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(glyphColor)
        case let .text(text):
            Text(text)
                .font(.system(size: size * (text.count > 2 ? 0.34 : 0.42), weight: .semibold, design: .rounded))
                .foregroundStyle(glyphColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        }
    }
}

/// Picks the glyph (SF Symbol or a 1–3 character abbreviation) and the
/// accent colour for a task or subtask.
struct GlyphPickerView: View {
    @Binding var glyph: TaskGlyph
    @Binding var colorHex: String

    @State private var textDraft: String
    @State private var symbolDraft: String

    init(glyph: Binding<TaskGlyph>, colorHex: Binding<String>) {
        _glyph = glyph
        _colorHex = colorHex
        _textDraft = State(initialValue: glyph.wrappedValue.textGlyph ?? "")
        _symbolDraft = State(initialValue: glyph.wrappedValue.symbolName ?? TaskGlyph.fallback.symbolName ?? "circle")
    }

    private var color: Color { TaskPalette.color(forHex: colorHex) }

    private var kind: Binding<TaskGlyph.Kind> {
        Binding(
            get: { glyph.kind },
            set: { newKind in
                switch newKind {
                case .symbol:
                    glyph = .symbol(symbolDraft)
                case .text:
                    // An empty text glyph would render as a blank badge, so a
                    // fresh switch seeds a single character the user overwrites.
                    let seed = textDraft.isEmpty ? "A" : textDraft
                    textDraft = seed
                    glyph = .text(seed)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                GlyphBadge(glyph: glyph, color: color, size: 40)

                Picker("Glyph", selection: kind) {
                    Text("Symbol").tag(TaskGlyph.Kind.symbol)
                    Text("Text").tag(TaskGlyph.Kind.text)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch glyph.kind {
            case .symbol:
                symbolGrid
            case .text:
                textEntry
            }

            Divider()

            colorRow
        }
    }

    // MARK: - Symbol

    private var symbolGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 34), spacing: 6)],
                alignment: .leading,
                spacing: 6,
                pinnedViews: [.sectionHeaders]
            ) {
                // Indexed rather than keyed by `\.section`: the catalog holds
                // tuples, which cannot be addressed with a key path.
                ForEach(TaskGlyph.symbolCatalog.indices, id: \.self) { index in
                    let entry = TaskGlyph.symbolCatalog[index]
                    Section {
                        ForEach(entry.symbols, id: \.self) { name in
                            symbolCell(name)
                        }
                    } header: {
                        Text(entry.section)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.trailing, 4)
        }
        .frame(height: 170)
    }

    private func symbolCell(_ name: String) -> some View {
        let isSelected = glyph.symbolName == name
        return Button {
            symbolDraft = name
            glyph = .symbol(name)
        } label: {
            Image(systemName: name)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .foregroundStyle(isSelected ? color : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? color.opacity(0.22) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(name)
    }

    // MARK: - Text

    private var textEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Abbreviation", text: $textDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onChange(of: textDraft) { _, newValue in
                    let sanitized = TaskGlyph.sanitizedText(newValue)
                    if sanitized != newValue { textDraft = sanitized }
                    glyph = .text(sanitized)
                }

            Text("Up to \(TaskGlyph.textLimit) characters, e.g. \"AI\" or \"3D\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Colour

    private var colorRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(TaskPalette.entries) { entry in
                Button {
                    colorHex = entry.hex
                } label: {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if entry.hex == colorHex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            Circle().strokeBorder(.primary.opacity(entry.hex == colorHex ? 0.5 : 0), lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .help(entry.name)
            }
        }
    }
}

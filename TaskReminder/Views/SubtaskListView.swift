//
//  SubtaskListView.swift
//  TaskReminder
//

import SwiftData
import SwiftUI

/// Add, rename, reorder and delete the subtasks of a task.
///
/// Subtasks are organisational only: title, glyph and colour. They carry no
/// interval, no countdown and no alert of their own — do not add one.
struct SubtaskListView: View {
    let task: TaskItem

    @Environment(\.modelContext) private var modelContext

    @State private var newTitle = ""
    @State private var glyphTarget: SubtaskItem?

    private var subtasks: [SubtaskItem] {
        task.subtasks.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var trimmedNewTitle: String {
        newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if subtasks.isEmpty {
                Text("No subtasks yet. Subtasks are labels only — they never alert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(subtasks) { subtask in
                        SubtaskRow(
                            subtask: subtask,
                            onPickGlyph: { glyphTarget = subtask },
                            onDelete: { delete(subtask) }
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                        .listRowSeparator(.hidden)
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(subtasks.count) * 32 + 10, 170))
            }

            HStack(spacing: 6) {
                TextField("New subtask", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)

                Button("Add", systemImage: "plus", action: add)
                    .labelStyle(.iconOnly)
                    .disabled(trimmedNewTitle.isEmpty)
            }
        }
        .sheet(item: $glyphTarget) { subtask in
            SubtaskGlyphSheet(subtask: subtask)
        }
    }

    // MARK: - Mutations

    private func add() {
        guard !trimmedNewTitle.isEmpty else { return }
        let subtask = SubtaskItem(
            title: trimmedNewTitle,
            sortIndex: (subtasks.map(\.sortIndex).max() ?? -1) + 1,
            glyph: .symbol("circle"),
            colorHex: task.colorHex
        )
        modelContext.insert(subtask)
        task.subtasks.append(subtask)
        newTitle = ""
        try? modelContext.save()
    }

    private func delete(_ subtask: SubtaskItem) {
        modelContext.delete(subtask)
        try? modelContext.save()
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var reordered = subtasks
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, subtask) in reordered.enumerated() {
            subtask.sortIndex = index
        }
        try? modelContext.save()
    }
}

// MARK: - Row

private struct SubtaskRow: View {
    @Bindable var subtask: SubtaskItem

    let onPickGlyph: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPickGlyph) {
                GlyphBadge(
                    glyph: subtask.glyph,
                    color: TaskPalette.color(forHex: subtask.colorHex),
                    size: 22
                )
            }
            .buttonStyle(.plain)
            .help("Change glyph and colour")

            TextField("Title", text: $subtask.title)
                .textFieldStyle(.plain)

            Button("Delete", systemImage: "minus.circle", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete this subtask")
        }
    }
}

// MARK: - Glyph sheet

private struct SubtaskGlyphSheet: View {
    @Bindable var subtask: SubtaskItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subtask.title.isEmpty ? "Subtask" : subtask.title)
                .font(.headline)

            GlyphPickerView(glyph: $subtask.glyph, colorHex: $subtask.colorHex)

            HStack {
                Spacer()
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

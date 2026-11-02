//
//  TaskListView.swift
//  TaskReminder
//

import AppKit
import SwiftData
import SwiftUI

/// Density of the shared task list. `.compact` is the menu bar popover,
/// `.full` is the floating panel. One view serves both — never fork it.
enum TaskListMode {
    case compact
    case full
}

struct TaskListView: View {
    let mode: TaskListMode

    @Environment(\.modelContext) private var modelContext
    @Environment(TaskScheduler.self) private var scheduler
    @Environment(AlertCoordinator.self) private var alerts
    @Environment(AppSettings.self) private var settings
    /// Optional: the menu bar popover renders this view without a panel.
    @Environment(FloatingPanelController.self) private var panelController: FloatingPanelController?
    @Environment(SettingsWindowController.self) private var settingsWindow: SettingsWindowController?
    /// Optional: not every host injects the chime, e.g. previews.
    @Environment(QuarterHourChime.self) private var chime: QuarterHourChime?

    @Query(sort: \TaskItem.sortIndex) private var tasks: [TaskItem]

    @State private var editingTask: TaskItem?
    /// Set while the editor is open for a task that was created by the add
    /// button, so cancelling the editor removes it again.
    @State private var draftTaskID: UUID?
    /// Whether the header is showing the spread-interval choices.
    @State private var isPickingSpread = false

    private var isCompact: Bool { mode == .compact }

    var body: some View {
        VStack(spacing: 0) {
            if mode == .full {
                header
                Divider()
            }

            if tasks.isEmpty {
                emptyState
            } else {
                taskList
            }

            if mode == .full {
                Divider()
                footer
            }
        }
        .frame(minWidth: isCompact ? 280 : 320, maxHeight: isCompact ? 360 : .infinity)
        .sheet(item: $editingTask) { task in
            TaskEditorView(
                task: task,
                onSave: { draftTaskID = nil },
                onCancel: { discardDraft(task) }
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            if isPickingSpread {
                spreadChoices
            } else {
                Text("Tasks")
                    .font(.headline)

                Spacer()

                Button("Spread Intervals", systemImage: "clock.arrow.2.circlepath") {
                    withAnimation(.easeOut(duration: 0.12)) { isPickingSpread = true }
                }
                .disabled(tasks.isEmpty)
                .help("Set one interval on every task and spread their countdowns evenly")
            }

            Button("Add Task", systemImage: "plus") {
                addTask()
            }
            .help("Add a task")

            // The panel's titlebar close button is gone, so closing lives
            // inside the widget where the rest of the controls are.
            Button("Close", systemImage: "xmark") {
                panelController?.hide()
            }
            .help("Hide the panel")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Sets one interval on every task and restarts the countdowns evenly
    /// spread across it, so the alerts arrive in a steady rotation instead
    /// of bunching up.
    ///
    /// The choices open inside the header on click rather than in a `Menu`.
    /// A menu label draws in AppKit's *active* appearance while the plain
    /// buttons beside it draw dimmed — this panel never becomes key — and
    /// tinting could not reliably match the two. Using the same button widget
    /// as its neighbours removes the mismatch instead of chasing it.
    private var spreadChoices: some View {
        HStack(spacing: 4) {
            Text("Every")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(TaskItem.intervalOptionMinutes, id: \.self) { minutes in
                Button("\(minutes)") {
                    scheduler.applyUniformInterval(seconds: Double(minutes) * 60)
                    withAnimation(.easeOut(duration: 0.12)) { isPickingSpread = false }
                }
            }

            Button("Cancel", systemImage: "xmark.circle") {
                withAnimation(.easeOut(duration: 0.12)) { isPickingSpread = false }
            }

            Spacer(minLength: 0)
        }
    }

    private var taskList: some View {
        List {
            ForEach(tasks) { task in
                TaskRowView(
                    task: task,
                    mode: mode,
                    onEdit: { editingTask = task },
                    onDelete: { delete(task) }
                )
                .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(task)
                    }
                }
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        // The panel paints glass behind this view; an opaque list background
        // would cover it.
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Tasks", systemImage: "timer")
        } description: {
            Text(isCompact ? "Add a task from the panel." : "Add a task to start a countdown.")
        } actions: {
            if mode == .full {
                Button("Add Task") { addTask() }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxHeight: isCompact ? 160 : .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(
                settings.alwaysOnTop ? "Always on Top" : "Normal Level",
                systemImage: settings.alwaysOnTop ? "pin.fill" : "pin.slash"
            ) {
                settings.alwaysOnTop.toggle()
            }
            .labelStyle(.iconOnly)
            .help(settings.alwaysOnTop ? "Stop floating above other apps" : "Float above other apps")

            Spacer()

            Button("Settings…", systemImage: "gearshape") {
                openSettingsWindow()
            }
            .labelStyle(.iconOnly)
            .help("Settings")

            if let chime {
                Button(
                    chime.isEnabled ? "Quarter-Hour Chime: On" : "Quarter-Hour Chime: Off",
                    systemImage: chime.isEnabled ? "speaker.wave.2.fill" : "speaker.slash"
                ) {
                    chime.toggle()
                }
                .labelStyle(.iconOnly)
                .help("Chime once every quarter hour (:00, :15, :30, :45), independent of any task")
            }

            Button("Quit", systemImage: "power") {
                NSApp.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .help("Quit TaskReminder")
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Mutations

    private func addTask() {
        let nextIndex = (tasks.map(\.sortIndex).max() ?? -1) + 1
        let task = TaskItem(
            title: "New Task",
            sortIndex: nextIndex,
            intervalSeconds: Double(settings.defaultIntervalMinutes) * 60,
            snoozeSeconds: Double(settings.defaultSnoozeMinutes) * 60,
            soundName: settings.defaultSoundName,
            glyph: .symbol("bell"),
            colorHex: TaskPalette.hex(forIndex: nextIndex)
        )
        modelContext.insert(task)
        persist()
        draftTaskID = task.id
        editingTask = task
    }

    private func delete(_ task: TaskItem) {
        modelContext.delete(task)
        persist()
    }

    /// A task created by the add button only survives if the editor is saved.
    private func discardDraft(_ task: TaskItem) {
        guard draftTaskID == task.id else { return }
        draftTaskID = nil
        delete(task)
    }

    /// Rewrites `sortIndex` from the order on screen. The list is never
    /// sorted automatically, so what the user drags is exactly what is stored.
    private func move(from offsets: IndexSet, to destination: Int) {
        var reordered = tasks
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, task) in reordered.enumerated() {
            task.sortIndex = index
        }
        persist()
    }

    private func persist() {
        try? modelContext.save()
        scheduler.evaluateNow()
    }

    /// Settings lives in an AppKit window of our own. The `showSettingsWindow:`
    /// selector this used to send was removed after Sonoma, and on macOS 26
    /// `SettingsLink` and `openSettings` both need a live SwiftUI render tree
    /// that an `LSUIElement` app hosting its UI from AppKit does not have.
    private func openSettingsWindow() {
        settingsWindow?.show()
    }
}

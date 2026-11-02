//
//  TaskRowView.swift
//  TaskReminder
//

import SwiftUI

/// Formats a remaining-time interval for display. Negative values mean the
/// task is already overdue.
enum CountdownFormat {
    static func text(forRemaining remaining: TimeInterval) -> String {
        let isOverdue = remaining < 0
        let total = Int(abs(remaining).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        let clock = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)

        return isOverdue ? "+\(clock) over" : clock
    }
}

/// One task in the list: drag handle, badge, live countdown, and the
/// Done / Snooze actions. Hovering the badge swaps those actions for a
/// quick interval switcher.
///
/// Rows stay deliberately flat — no glass. Liquid Glass belongs to the panel
/// background and the controls, not to content that has to stay legible.
struct TaskRowView: View {
    let task: TaskItem
    let mode: TaskListMode
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(TaskScheduler.self) private var scheduler
    @Environment(AlertCoordinator.self) private var alerts
    @Environment(AppSettings.self) private var settings

    @State private var isRowHovered = false
    @State private var isBadgeHovered = false
    /// Driven by a click, not by hover: a hover-triggered picker vanished
    /// the moment the pointer set off towards it.
    @State private var isPickingInterval = false

    private var isCompact: Bool { mode == .compact }
    private var accent: Color { TaskPalette.color(forHex: task.colorHex) }
    private var isOverdue: Bool { alerts.overdueTaskIDs.contains(task.id) }
    private var badgeSize: CGFloat { isCompact ? 26 : 34 }

    /// Actions stay hidden until the pointer arrives, but an overdue task
    /// shows them unconditionally — an alert must be dismissable without
    /// hunting for the row first. An open interval picker also pins them,
    /// so the controls cannot vanish from under the pointer mid-choice.
    private var showsActions: Bool {
        mode == .full && task.isEnabled && (isRowHovered || isOverdue || isPickingInterval)
    }

    private var currentIntervalMinutes: Int {
        Int((task.intervalSeconds / 60).rounded())
    }

    private var enabledBinding: Binding<Bool> {
        // Enabling restarts a fresh interval and disabling clears the alert,
        // so this must route through the scheduler rather than the model.
        Binding(
            get: { task.isEnabled },
            set: { scheduler.setEnabled(task, to: $0) }
        )
    }

    var body: some View {
        // The countdown is derived from the stored `nextFireAt` on every tick
        // of this timeline. Nothing is written to SwiftData here, so showing a
        // live countdown costs no disk I/O and never invalidates the list.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .padding(.vertical, isCompact ? 4 : 7)
        .padding(.horizontal, isCompact ? 6 : 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isRowHovered = hovering
                // Leaving the row is the dismissal. Moving onto the choices
                // never leaves it, because they open inside the row.
                if !hovering { isPickingInterval = false }
            }
        }
        .contextMenu { contextMenuItems }
    }

    private func content(now: Date) -> some View {
        let remaining = task.remainingSeconds(at: now)

        return HStack(spacing: isCompact ? 8 : 10) {
            if mode == .full {
                dragHandle
            }

            badge(now: now)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(isCompact ? .callout : .body)
                    .fontWeight(isOverdue ? .semibold : .regular)
                    .lineLimit(1)

                countdownLabel(remaining: remaining)
            }

            Spacer(minLength: 4)

            if showsActions {
                actionButtons
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Toggle("Enabled", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(task.isEnabled ? "Pause this task" : "Resume this task")
        }
        .animation(.easeOut(duration: 0.12), value: showsActions)
        .animation(.easeOut(duration: 0.12), value: isPickingInterval)
    }

    // MARK: - Drag handle

    /// The list reorders through `.onMove`, which accepts a drag from
    /// anywhere in the row. This is the visible affordance for it.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 12)
            .opacity(isRowHovered ? 1 : 0.25)
            .help("Drag to reorder")
            .accessibilityHidden(true)
    }

    // MARK: - Badge

    /// The badge carries the countdown as a filling wedge, and reveals an
    /// edit affordance while the pointer is over it.
    @ViewBuilder
    private func badge(now: Date) -> some View {
        let art = GlyphBadge(
            glyph: task.glyph,
            color: accent,
            size: badgeSize,
            progress: task.isEnabled ? task.progress(at: now) : nil,
            isOverdue: isOverdue
        )
        .opacity(task.isEnabled ? 1 : 0.45)

        if mode == .full {
            Button(action: onEdit) {
                art.overlay {
                    if isBadgeHovered {
                        RoundedRectangle(cornerRadius: badgeSize * 0.28, style: .continuous)
                            .fill(.black.opacity(0.55))
                            .overlay {
                                Image(systemName: "pencil")
                                    .font(.system(size: badgeSize * 0.42, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) { isBadgeHovered = hovering }
            }
            .help("Edit \(task.title)")
        } else {
            art
        }
    }

    private func countdownLabel(remaining: TimeInterval) -> some View {
        Group {
            if task.isEnabled {
                Text(CountdownFormat.text(forRemaining: remaining))
                    .monospacedDigit()
                    .foregroundStyle(isOverdue ? Color.red : Color.secondary)
            } else {
                Text("Paused")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(isCompact ? .caption2 : .caption)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if isPickingInterval {
                intervalChoices
            } else {
                intervalButton
            }

            Button("Done", systemImage: "checkmark") {
                scheduler.markHandled(task)
            }
            .help("Restart this task's interval")

            Button("Snooze", systemImage: "zzz") {
                scheduler.snooze(task)
            }
            .help("Push this task out by its snooze time")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    /// Shows the interval currently in force, and opens the choices on click.
    private var intervalButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { isPickingInterval = true }
        } label: {
            Text("\(currentIntervalMinutes)m").monospacedDigit()
        }
        .help("Change how long this task runs between reminders")
    }

    /// The choices open in place rather than in a popover: the panel is a
    /// non-activating window, and a separate popover window attached to one
    /// can dismiss itself the moment it tries to take key status.
    private var intervalChoices: some View {
        HStack(spacing: 4) {
            ForEach(TaskItem.intervalOptionMinutes, id: \.self) { minutes in
                intervalChoice(minutes: minutes)
            }
        }
        .transition(.opacity)
    }

    /// The selected value gets a tinted fill behind a `.plain` button rather
    /// than `.buttonStyle(.glass)` — glass renders its own capsule shape
    /// that a background tint cannot show through cleanly.
    @ViewBuilder
    private func intervalChoice(minutes: Int) -> some View {
        let action = {
            task.intervalSeconds = Double(minutes * 60)
            // Matches Done/Switch semantics: the new interval starts now.
            scheduler.markHandled(task)
            withAnimation(.easeOut(duration: 0.12)) { isPickingInterval = false }
        }

        if minutes == currentIntervalMinutes {
            Button(action: action) {
                Text("\(minutes)")
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Button(action: action) {
                Text("\(minutes)").monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Done / Switch") { scheduler.markHandled(task) }
            .disabled(!task.isEnabled)
        Button("Snooze") { scheduler.snooze(task) }
            .disabled(!task.isEnabled)
        Divider()
        Button(task.isEnabled ? "Pause" : "Resume") {
            scheduler.setEnabled(task, to: !task.isEnabled)
        }
        // The editor is a sheet, which the menu bar popover cannot host.
        if mode == .full {
            Button("Edit…", action: onEdit)
        }
        Divider()
        Button("Delete", role: .destructive, action: onDelete)
    }

    // MARK: - Highlight

    /// Overdue rows are tinted, and the tint alternates while the coordinator
    /// blinks. With reduce-motion on, the coordinator holds `isBlinking`
    /// steady, so this degrades to a static highlight on its own.
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(highlightColor)
            .animation(settings.reduceMotion ? nil : .easeInOut(duration: 0.2), value: alerts.isBlinking)
    }

    private var highlightColor: Color {
        if isOverdue {
            return accent.opacity(alerts.isBlinking ? 0.34 : 0.13)
        }
        return isRowHovered ? Color.primary.opacity(0.07) : .clear
    }
}

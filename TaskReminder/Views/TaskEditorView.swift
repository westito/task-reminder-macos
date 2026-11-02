//
//  TaskEditorView.swift
//  TaskReminder
//

import SwiftData
import SwiftUI

/// Create or edit one task. All scalar fields are edited as local drafts and
/// only written through on Save, so Cancel really discards.
///
/// A task is a single title plus its two triggers — a repeating interval and
/// an optional wall-clock time of day. There is deliberately no description,
/// no notes and no due date.
struct TaskEditorView: View {
    let task: TaskItem
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskScheduler.self) private var scheduler

    @State private var title: String
    @State private var intervalSeconds: Double
    @State private var snoozeSeconds: Double
    @State private var soundName: String
    @State private var dailyEnabled: Bool
    @State private var dailyTime: Date
    @State private var glyph: TaskGlyph
    @State private var colorHex: String

    /// Shared with the row's quick picker, so a task's interval offers the
    /// same choices wherever it is set.
    private static let intervalPresetMinutes: [Double] = TaskItem.intervalOptionMinutes.map(Double.init)
    private static let snoozePresetMinutes: [Double] = [1, 2, 5, 10, 15, 20, 30]

    init(task: TaskItem, onSave: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}) {
        self.task = task
        self.onSave = onSave
        self.onCancel = onCancel

        _title = State(initialValue: task.title)
        _intervalSeconds = State(initialValue: task.intervalSeconds)
        _snoozeSeconds = State(initialValue: task.snoozeSeconds)
        _soundName = State(initialValue: task.soundName)
        _dailyEnabled = State(initialValue: task.dailyReminderMinutes != nil)
        _dailyTime = State(initialValue: Self.date(fromMinutes: task.dailyReminderMinutes ?? 9 * 60))
        _glyph = State(initialValue: task.glyph)
        _colorHex = State(initialValue: task.colorHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title)
                } header: {
                    Text("Task")
                }

                Section {
                    Picker("Remind me every", selection: $intervalSeconds) {
                        ForEach(durationOptions(Self.intervalPresetMinutes, including: intervalSeconds), id: \.self) { value in
                            Text(Self.durationLabel(value)).tag(value)
                        }
                    }

                    Picker("Snooze for", selection: $snoozeSeconds) {
                        ForEach(durationOptions(Self.snoozePresetMinutes, including: snoozeSeconds), id: \.self) { value in
                            Text(Self.durationLabel(value)).tag(value)
                        }
                    }
                } header: {
                    Text("Interval")
                }

                Section {
                    Toggle("Also remind at a fixed time", isOn: $dailyEnabled)
                    DatePicker(
                        "Time of day",
                        selection: $dailyTime,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!dailyEnabled)
                } header: {
                    Text("Daily reminder")
                } footer: {
                    Text("Fires once per day, independently of the interval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Picker("Sound", selection: $soundName) {
                            ForEach(SoundLibrary.availableNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }

                        Button("Preview", systemImage: "speaker.wave.2") {
                            SoundLibrary.preview(soundName)
                        }
                        .labelStyle(.iconOnly)
                        .help("Play this sound")
                    }
                } header: {
                    Text("Alert")
                }

                Section {
                    GlyphPickerView(glyph: $glyph, colorHex: $colorHex)
                } header: {
                    Text("Appearance")
                }

                Section {
                    SubtaskListView(task: task)
                } header: {
                    Text("Subtasks")
                } footer: {
                    Text("Subtask edits are saved immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 640)
    }

    // MARK: - Saving

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let intervalChanged = task.intervalSeconds != intervalSeconds

        task.title = trimmed.isEmpty ? "Untitled" : trimmed
        task.intervalSeconds = intervalSeconds
        task.snoozeSeconds = snoozeSeconds
        task.soundName = soundName
        task.glyph = glyph
        task.colorHex = colorHex

        if dailyEnabled {
            task.dailyReminderMinutes = Self.minutes(from: dailyTime)
        } else {
            task.dailyReminderMinutes = nil
            task.lastDailyReminderDay = nil
        }

        try? modelContext.save()

        // `nextFireAt` is an absolute instant, so a changed interval only
        // takes effect by restarting the countdown from now.
        if intervalChanged, task.isEnabled {
            scheduler.markHandled(task)
        }
        scheduler.evaluateNow()

        onSave()
        dismiss()
    }

    // MARK: - Duration helpers

    /// Presets in seconds, with the stored value folded in when it is not one
    /// of them (seeded or previously customised tasks).
    private func durationOptions(_ presetMinutes: [Double], including current: Double) -> [Double] {
        let presets = presetMinutes.map { $0 * 60 }
        guard !presets.contains(current) else { return presets }
        return (presets + [current]).sorted()
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours) h \(minutes) min"
    }

    // MARK: - Time-of-day helpers

    private static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: .now
        ) ?? .now
    }
}

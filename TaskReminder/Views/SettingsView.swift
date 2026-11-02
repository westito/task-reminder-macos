//
//  SettingsView.swift
//  TaskReminder
//

import SwiftUI

/// The `Settings` scene body.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(FloatingPanelController.self) private var panel: FloatingPanelController?
    @Environment(QuarterHourChime.self) private var chime

    /// Shared with the editor and the row's quick picker.
    private static let intervalOptions = TaskItem.intervalOptionMinutes
    private static let snoozeOptions = [1, 2, 5, 10, 15, 30]

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Keep panel above other apps", isOn: $settings.alwaysOnTop)
                Toggle("Show panel at launch", isOn: $settings.showPanelOnLaunch)

                LabeledContent("Panel opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.panelOpacity, in: 0.4...1.0)
                            .frame(width: 180)
                        Text(settings.panelOpacity.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if let panel {
                    Button(panel.isVisible ? "Hide Panel" : "Show Panel") {
                        panel.toggle()
                    }
                }
            } header: {
                Text("Panel")
            }

            Section {
                Toggle("Blink when a task is due", isOn: $settings.blinkOnAlert)
                Toggle("Play a sound when a task is due", isOn: $settings.soundOnAlert)

                if settings.reduceMotion {
                    Text("Reduce Motion is on in System Settings, so overdue tasks use a steady highlight instead of a blink.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Alerts stay inside the app — no system notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("General")
            }

            Section {
                Picker("Default interval", selection: $settings.defaultIntervalMinutes) {
                    ForEach(Self.intervalOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }

                Picker("Default snooze", selection: $settings.defaultSnoozeMinutes) {
                    ForEach(Self.snoozeOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }

                LabeledContent("Default sound") {
                    HStack(spacing: 8) {
                        Picker("", selection: $settings.defaultSoundName) {
                            ForEach(SoundLibrary.availableNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()

                        Button("Preview", systemImage: "play.fill") {
                            SoundLibrary.preview(settings.defaultSoundName)
                        }
                        .labelStyle(.iconOnly)
                        .help("Preview the default sound")
                    }
                }
            } header: {
                Text("New Task Defaults")
            } footer: {
                Text("These values seed every newly created task; existing tasks keep their own settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Chime every quarter hour",
                    isOn: Binding(
                        get: { chime.isEnabled },
                        set: { chime.setEnabled($0) }
                    )
                )
            } header: {
                Text("Quarter-Hour Chime")
            } footer: {
                Text("Plays a single signal at :00, :15, :30 and :45 of every hour, independent of any task. No visual, no countdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

# TaskReminder — project instructions

macOS app that reminds the user to rotate between parallel projects. A
permanent floating glass panel lists tasks; each enabled task runs its own
countdown, and when one elapses the app blinks, plays a sound, and raises the
panel. Written in SwiftUI on an AppKit shell.

## Product decisions (settled with the user — do not re-litigate)

- **Parallel countdowns.** Every enabled task ticks independently and
  simultaneously. There is no single "active task". A task is either enabled
  (ticking) or disabled (not ticking). Several tasks may be overdue at once.
- **Two independent triggers per task:** a repeating interval, and an optional
  absolute wall-clock time-of-day that fires once per day.
- **Interval choices are fixed:** 5, 10, 15, 30, 60 minutes, defined once in
  `TaskItem.intervalOptionMinutes` and used by the row picker, the editor and
  the new-task default. Do not add a second list.
- **Subtasks are organisational only.** They carry title, glyph and colour. They
  have no timers, no intervals, no alerts.
- **A task is a single title** — "AICube", "3D print - box". No descriptions,
  no notes, no due dates beyond the two triggers above.
- **The floating panel is the only surface.** No menu bar item, no Dock icon.
  Closing the panel hides it; relaunching the app from Finder brings it back.
- **Quitting pauses every countdown; relaunching resumes it** with the same
  time remaining. Sleep and wake do *not* pause (see rule 1).
- **Manual order only.** The list is never sorted automatically — overdue tasks
  stay where the user put them. Reorder by drag; the row shows a grip handle.
- **Alerting is in-app only:** blink + sound + raise the panel. The task's sound
  repeats every 2 seconds until the user acknowledges it (Done, Snooze or
  disable). Deliberately no system notifications, so the app needs no
  notification permission and no signed bundle.
- **Alerts are spaced, not stacked.** When a task fires, any other task due
  within 2 minutes is pushed out to 1 minute plus a random 0–60 seconds. While
  an alert is unacknowledged, any task dropping below 1 minute gets the same
  treatment. A deferral never pulls a task earlier.
- **Quarter-hour chime:** an optional single frog sound at :00, :15, :30 and
  :45. Audio only — no countdown, no visual. Toggled from the panel footer and
  in Settings; switching it on plays the sound once as confirmation.
- **macOS 26 only.** Native Liquid Glass, no backport shims, no availability
  branches for older systems.

## Stack

Swift 6 language mode (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
`SWIFT_APPROACHABLE_CONCURRENCY = YES`) / Xcode 26 / macOS 26.5, arm64.
SwiftUI + AppKit interop, SwiftData for persistence, AVFoundation for the
bundled chime. App Sandbox is off (personal tool). `INFOPLIST_KEY_LSUIElement =
YES` — no Dock icon. The project uses file-system-synchronized groups: a file
dropped into `TaskReminder/` is in the target, no `project.pbxproj` edit needed.

## Architecture

`TaskReminderApp` owns an `NSApplicationDelegateAdaptor`. Both real windows are
AppKit-hosted SwiftUI (`NSHostingView`), owned by `AppServices`:

- the floating panel — an `NSPanel` (`FloatingPanelController`);
- the settings window — a plain `NSWindow` (`SettingsWindowController`).

The App's only Scene is `Settings { EmptyView() }`. It is deliberately inert and
exists solely because `App` requires a scene. Do not put UI in it.

```
TaskReminder/
  TaskReminderApp.swift      app delegate, AppServices wiring, PersistenceStack, seed data
  Models/                    TaskItem, SubtaskItem, TaskGlyph, TaskPalette
  Services/                  TaskScheduler, AlertCoordinator, QuarterHourChime,
                             SoundLibrary, AppSettings
  Windows/                   FloatingPanel, FloatingPanelController,
                             SettingsWindowController, GlassContainer
  Views/                     TaskListView, TaskRowView, TaskEditorView,
                             GlyphPickerView, SubtaskListView, SettingsView,
                             CountdownRing (the badge's ProgressSweep shape)
  Resources/frog.mov         the quarter-hour chime
```

`TaskListView(mode:)` still has `.compact` and `.full`. Only `.full` is
constructed now that the menu bar popover is gone; the `.compact` branches are
dead code kept for a possible return of a second surface.

Services reach views through `@Environment(Type.self)` (Observation, not
`ObservableObject`). Anything a view may be rendered without is read as an
optional.

## Rules that are easy to get wrong

These are correctness constraints, not style preferences. Each one exists
because the obvious alternative is broken.

1. **All scheduling is absolute-`Date` arithmetic.** Persist `nextFireAt` as a
   date; never store or decrement a remaining-seconds counter. This makes sleep
   correct — a task whose interval elapsed while the Mac was asleep fires
   exactly once on wake, not once per missed interval. Overdue is *derived*
   (`isEnabled && nextFireAt <= now`); there is no stored alerting flag.

   Quit-pause is built on top of this, not instead of it:
   `TaskScheduler.resumeFromLastRun()` shifts every enabled task's `nextFireAt`
   forward by the downtime, **once, at launch only**, measured against
   `schedulerLastActiveAt` in `UserDefaults`. The scheduler refreshes that
   marker every 15 s and on termination, so a crash mis-accounts at most 15 s.
   Never apply the shift on wake, and never shift for negative downtime (a
   clock moved backwards).

2. **Never write to SwiftData from a quiet tick.** Persist only on real state
   transitions: fire, snooze, acknowledge, enable/disable, edit, a daily
   reminder crossing, an alert-spacing deferral. The live countdown is derived
   from `nextFireAt` inside `TimelineView(.periodic(from:by:1))`, so displaying
   it costs no disk I/O.

3. **One 1 Hz timer for the whole app**, owned by `TaskScheduler`. Not one per
   task, and not one for the chime — `QuarterHourChime.evaluate(at:)` is called
   from the scheduler's pass. The chime compares quarter-hour *slots*, so a Mac
   that slept through several quarters chimes once on wake. The only other
   timers are UI-only: `AlertCoordinator`'s blink and its 2 s sound repeat.

4. **Hold a `ProcessInfo.beginActivity`** (`.userInitiatedAllowingIdleSystemSleep`)
   for the app's lifetime, or App Nap throttles the timer once the app has been
   in the background. Also observe `NSWorkspace.didWakeNotification` and
   re-evaluate immediately on wake.

5. **The panel must use `.nonactivatingPanel`** in its style mask, with
   `becomesKeyOnlyIfNeeded = true` and `hidesOnDeactivate = false`. Clicking the
   panel must never pull focus away from the app the user is working in. When
   alerting, raise with `orderFrontRegardless()` — never `NSApp.activate`.
   (The settings window *does* activate: opening it is an explicit request.)

6. **The panel never becomes key, so it draws its controls dimmed.** Two
   consequences:
   - Use plain `Button`s with `.buttonStyle(.glass)` everywhere in the panel.
     A `Menu` label renders in the *active* appearance and visibly mismatches
     its neighbours; no tint or opacity reliably fixes it.
   - Do not open a SwiftUI `.popover` from the panel — the popover window can
     dismiss itself the moment it reaches for key status. Choice rows open
     **inline, on click**: the row's interval picker closes on selection or
     when the pointer leaves the row; the header's spread picker closes on
     selection or its cancel button. Never open them on hover: a
     hover-triggered picker vanishes as the pointer sets off towards it.

7. **The store lives at `Application Support/TaskReminder/TaskReminder.store`**
   (`PersistenceStack.storeURL`), never SwiftData's default
   `Application Support/default.store`. Unsandboxed, that is a shared
   directory and a shared filename: other processes (`icloudmailagent` was
   caught holding it) open it with a different schema and migrate it
   destructively. Seeding is gated on the `didInstallSeedData` flag, not on an
   empty count, so a wiped store is never papered over with samples.

8. **The `ModelContainer` is built once** and injected into each AppKit-hosted
   root view (the panel and the settings window). Neither inherits a SwiftUI
   scene environment.

9. **Settings never goes through SwiftUI's `Settings` scene.** On macOS 26 an
   `LSUIElement` app has no working route to it: `showSettingsWindow:` was
   removed after Sonoma, and `SettingsLink` / `@Environment(\.openSettings)`
   need a live SwiftUI render tree the app does not have. Use
   `SettingsWindowController.show()`.

10. **Glass belongs to the functional layer only.** Panel background and controls
    get glass; task rows stay flat so they remain legible.

11. **The panel backdrop is `NSVisualEffectView`, not `.glassEffect`.**
    `NSGlassEffectView` (behind `.glassEffect`) composites *over* `NSHostingView`
    content on macOS 26 and blurs all text away. `GlassContainer` uses
    `.hudWindow` with `state = .active` — the default `.followsWindowActiveState`
    would grey it out permanently, because the panel is always in the
    background. Buttons still use `.buttonStyle(.glass)`.

12. **Store the task glyph as decomposed scalar fields** (`glyphKind`,
    `symbolName`, `textGlyph`, `colorHex`) with a computed `TaskGlyph` on top.
    `Codable` enums with associated values have documented
    `swift_dynamicCastFailure` crashes on delete. `TaskGlyph` and `TaskPalette`
    are `nonisolated` because SwiftData's generated code uses them as stored
    property defaults outside the main actor.

13. **Honour reduce-motion.** With
    `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — or with blink
    switched off — `AlertCoordinator` holds `isBlinking = true` for a steady
    highlight. Views read `isBlinking` as highlight *strength*, so leaving it
    false would strand an overdue row in the dim phase.

14. **Play `frog.mov` with `AVAudioPlayer`, not `NSSound`.** It is a QuickTime
    container around a single MP3 track, which `NSSound` does not decode
    reliably.

## Data model sketch

```
@Model TaskItem
  id, title, sortIndex, createdAt
  isEnabled: Bool
  intervalSeconds: Double
  nextFireAt: Date
  snoozeSeconds: Double
  soundName: String
  dailyReminderMinutes: Int?     // minutes since midnight, nil = off
  lastDailyReminderDay: Date?    // date-only, so it fires once per day
  glyphKind: String              // "symbol" | "text"
  symbolName: String?
  textGlyph: String?             // 1–3 characters, e.g. "AI", "3D"
  colorHex: String
  subtasks: [SubtaskItem]        // cascade delete

@Model SubtaskItem
  id, title, sortIndex, glyphKind, symbolName, textGlyph, colorHex, parent
```

Scheduler transitions: **Done/Switch** sets `nextFireAt = now + interval`;
**Snooze** sets `nextFireAt = now + snoozeSeconds`; **Disable** clears the
alert and stops ticking; **Enable** restarts a fresh interval;
**`applyUniformInterval`** sets one interval on every task and spreads the
enabled countdowns evenly across it. Daily reminders resolve through
`Calendar` in the current timezone on each evaluation.

Preferences live in `UserDefaults` through `AppSettings` (panel, alerting,
launch at login, new-task defaults, chime). Only the scheduler's
`schedulerLastActiveAt` and the seed flag are written outside it.

## Build, install, verify

Builds run locally on the Mac — this is an Xcode/macOS target, so it does not
use the rtx remote build host.

```
xcodebuild -project TaskReminder.xcodeproj -scheme TaskReminder -configuration Release build
```

The user runs the app from `/Applications`. After a change, replace
`/Applications/TaskReminder.app` with the fresh Release product and relaunch.

**Verify the installed app against the source, not against DerivedData.** A
stale `/Applications` copy once kept pointing at the old shared store and
looked like total data loss. Comparing it with the DerivedData product proved
nothing, because that was just as stale. Check that no `*.swift` file is newer
than `/Applications/TaskReminder.app/Contents/MacOS/TaskReminder`.

The app has no Dock icon or menu bar item, so "it does not start" usually means
it is running with the panel hidden or on another display — check the process
and the window list before assuming a crash. Prefer the `lint` tool over CLI
analysis, but note that sourcekit-lsp lacks module context here and reports
spurious "cannot find in scope" errors; `xcodebuild` is the authority.

After any scheduler change, sanity check two tasks with different intervals
both firing, including across a sleep/wake cycle and a quit/relaunch — neither
path has automated coverage.

## Roadmap

Phases 1–5 are done: model and persistence, floating panel, scheduler and
alerting, UI, and polish (reduce-motion, sound preview, launch at login via
`SMAppService`, empty state, drag reorder). Not yet done: keyboard shortcuts.

## Known-rough APIs

- `.glassEffect(.regular, in: RoundedRectangle(...))` sometimes renders as a
  capsule. Use `.buttonStyle(.glass)` for buttons instead of the raw modifier.
- A `List` with `.onMove` accepts a drag from anywhere in the row; the grip
  handle is an affordance, not a hard restriction.
- `SMAppService` launch-at-login can misbehave for an ad-hoc-signed app running
  outside `/Applications`.
- Bartender and similar menu bar managers hide new status items by default —
  relevant if a menu bar item is ever reintroduced.

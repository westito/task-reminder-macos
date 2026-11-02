//
//  SoundLibrary.swift
//  TaskReminder
//

import AVFoundation
import AppKit
import Foundation

/// The alert sounds a task can use. Only built-in system sounds are offered,
/// so nothing has to ship with the app.
enum SoundLibrary {
    /// Names shipped by macOS in `/System/Library/Sounds`. Filtered at load
    /// against `NSSound(named:)` so a renamed or missing sound never reaches
    /// the picker.
    private static let candidateNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    static let availableNames: [String] = candidateNames.filter {
        NSSound(named: NSSound.Name($0)) != nil
    }

    static let defaultSoundName: String = availableNames.first { $0 == "Submarine" }
        ?? availableNames.first
        ?? "Submarine"

    /// Playback is asynchronous, so the instance has to outlive the call that
    /// started it. The cache doubles as the retain that keeps it alive.
    private static var loaded: [String: NSSound] = [:]
    private static var previewing: NSSound?

    /// The bundled frog clip used by the quarter-hour chime.
    ///
    /// It ships as a QuickTime container wrapping a single MP3 track, which
    /// `NSSound` does not decode reliably — `AVAudioPlayer` does. Held for
    /// the app's lifetime so a half-second signal never pays for a decode.
    private static let frog: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "frog", withExtension: "mov"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player.prepareToPlay()
        return player
    }()

    /// Plays the frog signal, restarting it if it is already sounding.
    /// A missing or unreadable clip is a no-op rather than an error.
    static func playFrog() {
        guard let frog else { return }
        frog.currentTime = 0
        frog.play()
    }

    /// Plays the named sound. A name that does not resolve on this system is a
    /// no-op rather than an error — a task must never fail because of a sound.
    static func play(_ name: String) {
        guard let sound = sound(named: name) else { return }
        sound.stop()
        sound.play()
    }

    /// Plays a sound for the picker, cutting the previous preview off first so
    /// clicking through the list does not layer sounds on top of each other.
    static func preview(_ name: String) {
        previewing?.stop()
        previewing = sound(named: name)
        previewing?.play()
    }

    private static func sound(named name: String) -> NSSound? {
        guard !name.isEmpty else { return nil }
        if let cached = loaded[name] { return cached }
        guard let sound = NSSound(named: NSSound.Name(name)) else { return nil }
        loaded[name] = sound
        return sound
    }
}

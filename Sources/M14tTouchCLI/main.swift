import ApplicationServices
import CoreGraphics
import Foundation
import M14tTouchCore

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

let signalQueue = DispatchQueue(label: "m14ttouch.signals")
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)

for source in [interruptSource, terminateSource] {
    source.setEventHandler {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
            CFRunLoopStop(CFRunLoopGetMain())
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
    source.resume()
}

let banner = """

  ┌──────────────────────────────────────────────────────────┐
  │  m14ttouch 2.0 · Tablet & Trackpad Driver for M14t macOS │
  └──────────────────────────────────────────────────────────┘
"""

func printDisplays() {
    print("📺 Connected displays:")
    for d in DisplayResolver.all() {
        var tags: [String] = []
        if d.isM14t { tags.append("M14t detected ✅") }
        if d.isMain { tags.append("main") }
        let suffix = tags.isEmpty ? "" : "  ← " + tags.joined(separator: ", ")
        print("   [\(d.index)]  \"\(d.name)\"  \(Int(d.bounds.width)) × \(Int(d.bounds.height))  @ (\(Int(d.bounds.minX)),\(Int(d.bounds.minY)))  rot=\(d.rotationDegrees)°\(suffix)")
    }
    fflush(stdout)
}

func checkAccessibilityPermission(prompt: Bool) {
    guard !AXIsProcessTrusted() else { return }

    let message = """
    ⚠️  Accessibility permission is required to synthesize pointer and trackpad gestures.
        System Settings → Privacy & Security → Accessibility
        → toggle off & on ~/.local/bin/m14ttouch (or your terminal app).
        (Driver will stay running and activate automatically as soon as permission is granted.)

    """
    fputs(message, stderr)
    fflush(stderr)

    if prompt {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let defaultConfig = PreferencesStore.load()?.touchConfig ?? TouchConfig()

switch ArgumentParser.parse(arguments, defaults: defaultConfig) {

case .help:
    print(ArgumentParser.usageText)
    exit(0)

case .listDisplays:
    printDisplays()
    exit(0)

case .resetCalibration:
    if CalibrationStore.reset() {
        print("🗑️  Calibration reset (\(CalibrationStore.url.path))")
    } else {
        print("ℹ️  No saved calibration to reset (using factory 12372×6960 M14t bounds).")
    }
    exit(0)

case .error(let message):
    print("❌ \(message)")
    print(ArgumentParser.usageText)
    exit(1)

case .run(let config):
    print(banner)
    printDisplays()
    checkAccessibilityPermission(prompt: config.promptForAccessibility)

    let driver = HIDTouchDriver(config: config)
    driver.start()

    RunLoop.main.run()
}

import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid
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
        let dpiTag = d.isHiDPI
            ? "2x HiDPI (\(d.pixelWidth)×\(d.pixelHeight) px)"
            : "1x (\(d.pixelWidth)×\(d.pixelHeight) px)"
        let suffix = tags.isEmpty ? "" : "  ← " + tags.joined(separator: ", ")
        print("   [\(d.index)]  \"\(d.name)\"  \(Int(d.bounds.width)) × \(Int(d.bounds.height)) [\(dpiTag)]  @ (\(Int(d.bounds.minX)),\(Int(d.bounds.minY)))  rot=\(d.rotationDegrees)°\(suffix)")
    }
    fflush(stdout)
}

func printDisplayModes() {
    guard let target = DisplayResolver.resolve(forIndex: 1, preferAutoDetectM14t: true) else {
        print("❌ No display found.")
        return
    }
    print("📐 Available modes for [\(target.index)] \"\(target.name)\" (Display ID \(target.id)):")
    for mode in DisplayResolver.availableModes(for: target.id) {
        let currentMark = (Int(target.bounds.width.rounded()) == mode.width &&
                           Int(target.bounds.height.rounded()) == mode.height &&
                           target.pixelWidth == mode.pixelWidth &&
                           Int(target.refreshRate.rounded()) == Int(mode.refreshRate.rounded())) ? "  ← active ✅" : ""
        print("   • \(mode.description)\(currentMark)")
    }
    fflush(stdout)
}

func checkAccessibilityPermission(prompt: Bool) {
    let axTrusted = AXIsProcessTrusted()
    let imTrusted = (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)

    if !axTrusted {
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

    if !imTrusted {
        let message = """
        ⚠️  Input Monitoring permission is required to read M14t USB touch & Smart Pencil HID events.
            System Settings → Privacy & Security → Input Monitoring
            → toggle off & on ~/.local/bin/m14ttouch (or your terminal app).
            (Driver will stay running and activate automatically as soon as permission is granted.)

        """
        fputs(message, stderr)
        fflush(stderr)

        if prompt {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
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

case .listModes:
    printDisplayModes()
    exit(0)

case .setResolution(let preset):
    switch DisplayResolver.applyResolutionPreset(preset) {
    case .success(let msg):
        print("✅ \(msg)")
        exit(0)
    case .failure(let err):
        print("❌ \(err.localizedDescription)")
        exit(1)
    }

case .resetCalibration:
    if CalibrationStore.reset() {
        print("🗑️  Calibration reset (\(CalibrationStore.url.path))")
    } else {
        print("ℹ️  No saved calibration to reset (using factory 12372×6960 M14t bounds).")
    }
    exit(0)

case .checkPermissions:
    let ax = AXIsProcessTrusted()
    let im = (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
    let binaryPath = CommandLine.arguments.first ?? "m14ttouch"
    let existingState = DaemonStateStore.load()
    let state = DaemonState(
        pid: Int(ProcessInfo.processInfo.processIdentifier),
        isAccessibilityTrusted: ax,
        isInputMonitoringTrusted: im,
        binaryPath: binaryPath,
        activeConfig: existingState?.activeConfig
    )
    DaemonStateStore.save(state)
    print("{\"accessibility\": \(ax), \"inputMonitoring\": \(im)}")
    fflush(stdout)
    exit(0)

case .requestPermissions:
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    let ax = AXIsProcessTrustedWithOptions(options)
    let im = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    print("{\"accessibility\": \(ax), \"inputMonitoring\": \(im)}")
    fflush(stdout)
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

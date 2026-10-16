import AppKit
import SwiftUI
import M14tTouchCore

@main
struct M14tTouchSettingsApp: App {
    @StateObject private var model = SettingsModel()

    var body: some Scene {
        WindowGroup("M14t Touch") {
            SettingsView()
                .environmentObject(model)
                .frame(minWidth: 560, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var preferences: AppPreferences
    @Published var displays: [DisplayInfo]
    @Published var statusMessage = "Ready"
    @Published var isCalibrating = false

    private var calibrationProcess: Process?

    init() {
        self.preferences = PreferencesStore.load() ?? AppPreferences()
        self.displays = DisplayResolver.all()
    }

    var helperURL: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("m14ttouch"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/m14ttouch")
        if FileManager.default.isExecutableFile(atPath: localBin.path) {
            return localBin
        }

        return Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("m14ttouch")
            ?? URL(fileURLWithPath: "/usr/local/bin/m14ttouch")
    }

    func refreshDisplays() {
        displays = DisplayResolver.all()
        if let m14t = displays.first(where: { $0.isM14t }) {
            preferences.displayIndex = m14t.index
        } else if !displays.contains(where: { $0.index == preferences.displayIndex }) {
            preferences.displayIndex = displays.first?.index ?? 1
        }
    }

    func save() {
        do {
            try PreferencesStore.save(preferences)
            try applyRunAtLogin()
            statusMessage = "Settings saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func restartHelper() {
        save()
        do {
            try LaunchAgentManager.restart()
            statusMessage = preferences.runAtLogin
                ? "Background helper restarted"
                : "Settings saved; enable Run at Login to manage the background helper"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func startCalibration() {
        save()
        stopCalibration()

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--auto-calibrate"]
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            calibrationProcess = process
            isCalibrating = true
            statusMessage = "Touch all four corners on the M14t, then stop calibration"
        } catch {
            statusMessage = "Could not start calibration: \(error.localizedDescription)"
        }
    }

    func stopCalibration() {
        guard let process = calibrationProcess else { return }
        if process.isRunning {
            process.terminate()
        }
        calibrationProcess = nil
        isCalibrating = false
        statusMessage = "Calibration stopped"
    }

    func resetCalibration() {
        _ = CalibrationStore.reset()
        statusMessage = "Restored factory M14t calibration (12372×6960)"
    }

    func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func applyRunAtLogin() throws {
        if preferences.runAtLogin {
            try LaunchAgentManager.install(helperURL: helperURL)
            try LaunchAgentManager.bootstrap()
        } else {
            try LaunchAgentManager.bootout()
            try LaunchAgentManager.remove()
        }
    }

    private func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                displaySection
                tabletSection
                trackpadSection
                helperSection
                permissionSection
                statusBar
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("M14t Touch 2.0")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Lenovo ThinkVision M14t tablet & MacBook trackpad gesture driver")
                .foregroundStyle(.secondary)
        }
    }

    private var displaySection: some View {
        GroupBox("Display Target") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Automatically lock to Lenovo ThinkVision M14t display", isOn: $model.preferences.autoDetectM14tDisplay)

                HStack {
                    Text("Fallback display")
                    Picker("Target display", selection: $model.preferences.displayIndex) {
                        ForEach(model.displays, id: \.index) { display in
                            Text(displayTitle(display)).tag(display.index)
                        }
                    }
                    .labelsHidden()
                }

                HStack(spacing: 16) {
                    Toggle("Invert X axis", isOn: $model.preferences.invertX)
                    Toggle("Invert Y axis", isOn: $model.preferences.invertY)
                    Toggle("Active Stylus / Pen", isOn: $model.preferences.stylusEnabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tabletSection: some View {
        GroupBox("1-Finger Tablet Experience") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("1-Finger Drag Behavior", selection: $model.preferences.oneFingerMode) {
                    Text("Select Text & Drag Windows (Desktop Mode)").tag(OneFingerMode.selectAndDrag)
                    Text("Scroll Content, Hold-then-Drag to Select (iPad Mode)").tag(OneFingerMode.scrollAndHoldToSelect)
                }

                Toggle("Tap to click (Single / Double-tap word / Triple-tap paragraph)", isOn: $model.preferences.tapToClick)
                Toggle("Long-press (0.5s hold) for Right-Click", isOn: $model.preferences.longPressRightClick)

                HStack {
                    Text("Drag jitter threshold")
                    Slider(value: $model.preferences.dragThreshold, in: 1.5...12, step: 0.5)
                    Text(model.preferences.dragThreshold, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trackpadSection: some View {
        GroupBox("2 / 3 / 4-Finger MacBook Trackpad Gestures") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("2-Finger tap for Right-Click", isOn: $model.preferences.twoFingerRightClick)
                Toggle("2-Finger smooth inertial scroll", isOn: $model.preferences.twoFingerScroll)
                Toggle("Natural scrolling direction", isOn: $model.preferences.naturalScrolling)
                Toggle("2-Finger Pinch to Zoom", isOn: $model.preferences.pinchToZoom)
                Divider()
                Toggle("3 / 4-Finger Swipes (Switch Desktops, Mission Control, App Exposé)", isOn: $model.preferences.threeFingerSwipes)
                Toggle("Natural Desktop swipe direction", isOn: $model.preferences.naturalSpacesSwipe)
                Toggle("Debug logging", isOn: $model.preferences.debugMode)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var helperSection: some View {
        GroupBox("Driver Service") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Run background helper at login", isOn: Binding(
                    get: { model.preferences.runAtLogin },
                    set: { newValue in
                        model.preferences.runAtLogin = newValue
                        model.save()
                    }
                ))

                HStack {
                    Button("Save") { model.save() }
                    Button("Save & Restart Helper") { model.restartHelper() }
                    Button(model.isCalibrating ? "Stop Calibration" : "Custom Calibrate") {
                        model.isCalibrating ? model.stopCalibration() : model.startCalibration()
                    }
                    Button("Use Factory Calibration") { model.resetCalibration() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissionSection: some View {
        GroupBox("macOS Permissions") {
            HStack {
                Button("Open Accessibility") { model.openAccessibilitySettings() }
                Button("Open Input Monitoring") { model.openInputMonitoringSettings() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(model.statusMessage)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh Displays") { model.refreshDisplays() }
        }
    }

    private func displayTitle(_ display: DisplayInfo) -> String {
        var tags: [String] = []
        if display.isM14t { tags.append("M14t") }
        if display.isMain { tags.append("main") }
        let suffix = tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))"
        return "[\(display.index)] \(display.name) — \(Int(display.bounds.width))×\(Int(display.bounds.height))\(suffix)"
    }
}

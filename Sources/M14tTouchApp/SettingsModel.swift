import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import M14tTouchCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case service = "Service & Permissions"
    case display = "Display & HiDPI"
    case stylus = "Smart Pencil"
    case gestures = "Gestures & Trackpad"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .service: return "shield.checkered"
        case .display: return "display.2"
        case .stylus: return "pencil.and.outline"
        case .gestures: return "hand.tap"
        }
    }
}

@MainActor
public final class SettingsModel: ObservableObject {
    @Published public var preferences: AppPreferences
    @Published public var displays: [DisplayInfo]
    @Published public var statusMessage = "Ready"
    @Published public var isCalibrating = false

    @Published public var accessibilityGranted = false

    @Published public var isHelperInstalled = false
    @Published public var isHelperRunning = false
    @Published public var helperPID: Int? = nil

    @Published public var selectedTab: SettingsTab = .service
    @Published public var isSaving = false
    @Published public var saveSuccess = false

    private var calibrationProcess: Process?
    private var periodicTimer: Timer?
    private var notificationObserver: NSObjectProtocol?

    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .medium
        return df
    }()

    public init() {
        self.preferences = PreferencesStore.load() ?? AppPreferences()
        self.displays = DisplayResolver.all()

        refreshAll()
        setupObservers()
    }

    deinit {
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        periodicTimer?.invalidate()
    }

    private func setupObservers() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }

        periodicTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshHelperStatus()
                self?.refreshPermissions()
            }
        }
    }

    // MARK: - Status & Diagnostics

    public var allPermissionsGranted: Bool {
        accessibilityGranted
    }

    public var m14tDisplay: DisplayInfo? {
        displays.first(where: { $0.isM14t })
    }

    public var isM14tConnected: Bool {
        m14tDisplay != nil
    }

    public var helperURL: URL {
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/m14ttouch")
        if FileManager.default.isExecutableFile(atPath: localBin.path) {
            return localBin
        }

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("m14ttouch"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        return Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("m14ttouch")
            ?? URL(fileURLWithPath: "/usr/local/bin/m14ttouch")
    }

    public func refreshAll() {
        refreshHelperStatus()
        refreshPermissions()
        refreshDisplays()
    }

    public func refreshPermissions() {
        // Inspect the ground-truth state emitted strictly by the running background daemon
        if let liveState = DaemonStateStore.load(),
           (isHelperRunning && (helperPID == nil || liveState.pid == helperPID || abs(Date().timeIntervalSince1970 - liveState.timestamp) < 30)) {
            accessibilityGranted = liveState.isAccessibilityTrusted
            return
        }

        // Fallback to cached state from previous daemon runs (never run subprocesses from M14tTouch.app)
        if let cached = DaemonStateStore.load() {
            accessibilityGranted = cached.isAccessibilityTrusted
        } else {
            accessibilityGranted = false
        }
    }

    public func refreshHelperStatus() {
        let status = LaunchAgentManager.helperStatus()
        isHelperInstalled = status.isInstalled
        isHelperRunning = status.isRunning
        helperPID = status.pid
    }

    public func refreshDisplays() {
        displays = DisplayResolver.all()
        if let m14t = displays.first(where: { $0.isM14t }) {
            preferences.displayIndex = m14t.index
        } else if !displays.contains(where: { $0.index == preferences.displayIndex }) {
            preferences.displayIndex = displays.first?.index ?? 1
        }
    }

    // MARK: - Actions

    public func save() {
        isSaving = true
        do {
            try PreferencesStore.save(preferences)
            try applyRunAtLogin()

            if preferences.displayResolutionPreset != .systemDefault {
                _ = DisplayResolver.applyResolutionPreset(
                    preferences.displayResolutionPreset,
                    fallbackIndex: preferences.displayIndex,
                    preferAutoDetectM14t: preferences.autoDetectM14tDisplay
                )
                refreshDisplays()
            }

            statusMessage = "Settings saved at \(timeFormatter.string(from: Date()))"
            saveSuccess = true
            refreshHelperStatus()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.saveSuccess = false
                self?.isSaving = false
            }
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            isSaving = false
        }
    }

    public func restartHelper() {
        save()
        do {
            try LaunchAgentManager.restart()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.refreshHelperStatus()
                if let pid = self?.helperPID {
                    self?.statusMessage = "Background driver restarted (PID: \(pid))"
                } else {
                    self?.statusMessage = self?.preferences.runAtLogin == true
                        ? "Background driver restarted"
                        : "Settings saved; enable Run at Login to manage LaunchAgent"
                }
            }
        } catch {
            statusMessage = "Restart failed: \(error.localizedDescription)"
        }
    }

    public func startHelper() {
        save()
        do {
            try LaunchAgentManager.start(helperURL: helperURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.refreshHelperStatus()
                self?.statusMessage = "Background driver started"
            }
        } catch {
            statusMessage = "Could not start helper: \(error.localizedDescription)"
        }
    }

    public func stopHelper() {
        do {
            try LaunchAgentManager.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshHelperStatus()
                self?.statusMessage = "Background driver stopped"
            }
        } catch {
            statusMessage = "Could not stop helper: \(error.localizedDescription)"
        }
    }

    public func applyDisplayResolution() {
        let result = DisplayResolver.applyResolutionPreset(
            preferences.displayResolutionPreset,
            fallbackIndex: preferences.displayIndex,
            preferAutoDetectM14t: preferences.autoDetectM14tDisplay
        )
        refreshDisplays()
        switch result {
        case .success(let msg):
            try? PreferencesStore.save(preferences)
            statusMessage = msg
        case .failure(let err):
            statusMessage = err.localizedDescription
        }
    }

    public func startCalibration() {
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
            statusMessage = "Calibration active: Touch all four corners of the M14t, then click Stop"
        } catch {
            statusMessage = "Could not start calibration: \(error.localizedDescription)"
        }
    }

    public func stopCalibration() {
        guard let process = calibrationProcess else { return }
        if process.isRunning {
            process.terminate()
        }
        calibrationProcess = nil
        isCalibrating = false
        statusMessage = "Calibration stopped"
    }

    public func resetCalibration() {
        _ = CalibrationStore.reset()
        statusMessage = "Restored factory Lenovo M14t calibration (12372×6960)"
    }

    // MARK: - Permission Handlers

    public func requestAccessibilityPermission() {
        revealHelperInFinder()
        openAccessibilitySettings()
        statusMessage = "To authorize: drag 'm14ttouch' from Finder into System Settings → Accessibility"
    }

    public func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public func openLogFolder() {
        let logDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/M14tTouch", isDirectory: true)
        NSWorkspace.shared.open(logDir)
    }

    public func revealHelperInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([helperURL])
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

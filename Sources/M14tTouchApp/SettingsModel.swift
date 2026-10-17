import AppKit
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
    @Published public var inputMonitoringGranted = false
    @Published public var isRefreshingPermissions = false
    @Published public var isRefreshingDisplays = false

    @Published public var isHelperInstalled = false
    @Published public var isHelperRunning = false
    @Published public var helperPID: Int? = nil
    @Published public var activeDriverConfig: TouchConfig?

    @Published public var selectedTab: SettingsTab = .service
    @Published public var isSaving = false
    @Published public var saveSuccess = false

    private var initialLoadedPreferences: AppPreferences
    private var calibrationProcess: Process?
    private var periodicTimer: Timer?
    private var notificationObserver: NSObjectProtocol?
    private var isPermissionProbeInFlight = false

    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .medium
        return df
    }()

    public init() {
        let loadedPrefs = PreferencesStore.load() ?? AppPreferences()
        self.preferences = loadedPrefs
        self.initialLoadedPreferences = loadedPrefs
        self.displays = DisplayResolver.all()
        let daemonState = DaemonStateStore.load()
        self.accessibilityGranted = daemonState?.isAccessibilityTrusted ?? false
        self.inputMonitoringGranted = daemonState?.isInputMonitoringTrusted ?? false
        self.activeDriverConfig = daemonState?.activeConfig

        ensureLocalHelperInstalled()
        refreshAll(animated: false)
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
                self?.refreshAll(animated: true)
            }
        }

        periodicTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshHelperStatus()
                self?.refreshPermissions(animated: false)
            }
        }
    }

    // MARK: - Status & Diagnostics

    public var allPermissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    public var m14tDisplay: DisplayInfo? {
        displays.first(where: { $0.isM14t })
    }

    public var isM14tConnected: Bool {
        m14tDisplay != nil
    }

    public var requiresDriverRestart: Bool {
        guard isHelperRunning else { return false }
        if let active = activeDriverConfig {
            return preferences.requiresDriverRestart(comparedTo: active)
        }
        return preferences.requiresDriverRestart(comparedTo: initialLoadedPreferences)
    }

    private func ensureLocalHelperInstalled() {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("m14ttouch"),
              FileManager.default.isExecutableFile(atPath: bundled.path) else {
            return
        }

        let localDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
        let localBin = localDir.appendingPathComponent("m14ttouch")

        if FileManager.default.isExecutableFile(atPath: localBin.path),
           FileManager.default.contentsEqual(atPath: bundled.path, andPath: localBin.path) {
            return
        }

        do {
            try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: localBin.path) {
                try FileManager.default.removeItem(at: localBin)
            }
            try FileManager.default.copyItem(at: bundled, to: localBin)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localBin.path)
        } catch {
            // Fall back to bundled helper if ~/.local/bin cannot be written
        }
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

    public func refreshAll(animated: Bool = true) {
        refreshHelperStatus()
        refreshPermissions(animated: animated)
        refreshDisplays()
    }

    // CRITICAL ARCHITECTURAL INVARIANT — DO NOT MODIFY OR ROLLBACK:
    // 1. NEVER import `ApplicationServices` or call `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions()`
    //    inside `M14tTouchApp`. Doing so causes macOS TCC to register `M14tTouch.app` itself in
    //    System Settings → Accessibility and pop up false permission prompts for the GUI app.
    // 2. NEVER spawn `m14ttouch --check-permissions` as a direct child `Process()` of `M14tTouch.app`.
    //    macOS TCC sets the parent GUI app (`M14tTouch.app`) as the "responsible process" for direct
    //    child processes, returning `M14tTouch.app`'s TCC status instead of `m14ttouch`'s status.
    // 3. NEVER rely solely on reading cached `DaemonStateStore.load()` without a live probe, because
    //    macOS `HIServices` caches `AXIsProcessTrusted()` inside long-running processes.
    // 4. ALWAYS validate permissions via `LaunchAgentManager.probeBinaryPermissions(helperURL:)` /
    //    `LaunchAgentManager.probeBinaryAccessibility(helperURL:)`, which runs a one-shot `launchd`
    //    job (parent PID 1) so `tccd` evaluates the exact on-disk `m14ttouch` binary with zero
    //    process-level cache staleness.
    public func refreshPermissions() {
        refreshPermissions(animated: true)
    }

    public func refreshPermissions(animated: Bool) {
        if isPermissionProbeInFlight {
            if animated {
                isRefreshingPermissions = true
            }
            return
        }

        isPermissionProbeInFlight = true
        if animated {
            isRefreshingPermissions = true
        }

        let targetHelperURL = helperURL
        let wasAccessibilityGranted = accessibilityGranted
        let wasInputMonitoringGranted = inputMonitoringGranted
        let startTime = Date()

        Task.detached(priority: .userInitiated) {
            let perms = LaunchAgentManager.probeBinaryPermissions(helperURL: targetHelperURL)
            var status = LaunchAgentManager.helperStatus()

            if status.isRunning && (perms.accessibility != wasAccessibilityGranted || perms.inputMonitoring != wasInputMonitoringGranted) {
                try? LaunchAgentManager.restart()
                status = LaunchAgentManager.helperStatus()
            }

            let shouldAnimate = await MainActor.run { [weak self] in
                self?.isRefreshingPermissions ?? animated
            }

            if shouldAnimate {
                let elapsed = Date().timeIntervalSince(startTime)
                let minSpinDuration: TimeInterval = 0.5
                if elapsed < minSpinDuration {
                    try? await Task.sleep(nanoseconds: UInt64((minSpinDuration - elapsed) * 1_000_000_000))
                }
            }

            let finalStatus = status
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isHelperInstalled = finalStatus.isInstalled
                self.isHelperRunning = finalStatus.isRunning
                self.helperPID = finalStatus.pid
                self.accessibilityGranted = perms.accessibility
                self.inputMonitoringGranted = perms.inputMonitoring
                self.isRefreshingPermissions = false
                self.isPermissionProbeInFlight = false
            }
        }
    }

    public func refreshHelperStatus() {
        let status = LaunchAgentManager.helperStatus()
        isHelperInstalled = status.isInstalled
        isHelperRunning = status.isRunning
        helperPID = status.pid
        if status.isRunning, let active = DaemonStateStore.load()?.activeConfig {
            activeDriverConfig = active
        }
    }

    public func refreshDisplays() {
        isRefreshingDisplays = true
        displays = DisplayResolver.all()
        if let m14t = displays.first(where: { $0.isM14t }) {
            preferences.displayIndex = m14t.index
        } else if !displays.contains(where: { $0.index == preferences.displayIndex }) {
            preferences.displayIndex = displays.first?.index ?? 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.isRefreshingDisplays = false
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
        activeDriverConfig = preferences.touchConfig
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
        activeDriverConfig = preferences.touchConfig
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

    // CRITICAL: Do NOT call `AXIsProcessTrustedWithOptions` or `IOHIDRequestAccess` here. Calling
    // them from `M14tTouch.app` prompts macOS to authorize `M14tTouch.app` instead of `m14ttouch`.
    public func requestAccessibilityPermission() {
        revealHelperInFinder()
        openAccessibilitySettings()
        statusMessage = "To authorize: drag 'm14ttouch' from Finder into System Settings → Accessibility (or toggle it off & on)"
    }

    public func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public func requestInputMonitoringPermission() {
        revealHelperInFinder()
        openInputMonitoringSettings()
        statusMessage = "To authorize: drag 'm14ttouch' from Finder into System Settings → Input Monitoring (or toggle it off & on)"
    }

    public func openInputMonitoringSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
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

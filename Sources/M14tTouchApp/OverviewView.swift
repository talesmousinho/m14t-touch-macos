import SwiftUI
import M14tTouchCore

public struct OverviewView: View {
    @EnvironmentObject private var model: SettingsModel

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HardwareBannerCard(
                    display: model.m14tDisplay,
                    isM14tConnected: model.isM14tConnected,
                    onRefresh: model.refreshDisplays
                )

                PermissionsHubCard(
                    allGranted: model.allPermissionsGranted,
                    accessibilityGranted: model.accessibilityGranted,
                    onRefresh: model.refreshPermissions,
                    onRevealBinary: model.revealHelperInFinder,
                    onRequestAccessibility: model.requestAccessibilityPermission,
                    onOpenAccessibility: model.openAccessibilitySettings
                )

                DriverServiceControlCard(
                    isRunning: model.isHelperRunning,
                    pid: model.helperPID,
                    runAtLogin: Binding(
                        get: { model.preferences.runAtLogin },
                        set: { newValue in
                            model.preferences.runAtLogin = newValue
                            model.save()
                        }
                    ),
                    isSaving: model.isSaving,
                    saveSuccess: model.saveSuccess,
                    onSave: model.save,
                    onRestart: model.restartHelper,
                    onStart: model.startHelper,
                    onStop: model.stopHelper,
                    onOpenLogs: model.openLogFolder
                )

                TouchCalibrationCard(
                    isCalibrating: model.isCalibrating,
                    onStart: model.startCalibration,
                    onStop: model.stopCalibration,
                    onReset: model.resetCalibration
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Hardware Banner Card

private struct HardwareBannerCard: View {
    let display: DisplayInfo?
    let isM14tConnected: Bool
    let onRefresh: () -> Void

    @State private var isSpinning = false

    var body: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 16) {
                IconSquircle(
                    icon: isM14tConnected ? "display.2" : "display.trianglebadge.exclamationmark",
                    color: isM14tConnected ? AppColor.statusSuccess : AppColor.statusWarning,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(isM14tConnected ? "Lenovo ThinkVision M14t Connected" : "No M14t Display Detected")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)

                        if isM14tConnected {
                            GlassBadge(text: "Digitizer Active", icon: "hand.tap.fill", color: AppColor.statusSuccess)
                        } else {
                            GlassBadge(text: "Waiting for USB-C", icon: "cable.connector", color: AppColor.statusWarning)
                        }
                    }

                    if let display {
                        Text("Display [\(display.index)] • \(Int(display.bounds.width))×\(Int(display.bounds.height)) point viewport\(display.isHiDPI ? " • 2x Retina HiDPI" : "")")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.80))
                    } else {
                        Text("Connect your Lenovo ThinkVision M14t with a full-featured USB-C cable to activate multi-touch & pen input.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }
                }

                Spacer()

                GlassActionButton(isProminent: false, action: handleRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                }
                .controlSize(.regular)
            }
        }
    }

    private func handleRefresh() {
        withAnimation(.easeInOut(duration: 0.4)) {
            isSpinning = true
            onRefresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSpinning = false
        }
    }
}

// MARK: - Permissions Hub Card

private struct PermissionsHubCard: View {
    let allGranted: Bool
    let accessibilityGranted: Bool
    let onRefresh: () -> Void
    let onRevealBinary: () -> Void
    let onRequestAccessibility: () -> Void
    let onOpenAccessibility: () -> Void

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    GlassSectionHeader(
                        title: "Driver Service Permissions",
                        subtitle: "Required for background binary (~/.local/bin/m14ttouch) to synthesize cursor movements & gestures",
                        icon: "shield.lefthalf.filled",
                        iconColor: allGranted ? AppColor.statusSuccess : AppColor.statusWarning
                    )

                    Spacer()

                    if !allGranted {
                        GlassBadge(text: "Action Required", icon: "exclamationmark.triangle.fill", color: AppColor.statusWarning)
                    }

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help("Re-check binary permissions")
                }

                if !allGranted {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppColor.statusWarning)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add Driver Binary to Accessibility")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text("macOS requires background daemons to be manually added. The settings app (**M14tTouch.app**) needs no permissions — only the binary (**m14ttouch**) requires Accessibility.")
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(Color.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: 10) {
                            GlassActionButton(isProminent: true, tint: .blue, action: onRevealBinary) {
                                Label("1. Reveal Binary in Finder", systemImage: "folder.fill")
                            }
                            .controlSize(.regular)

                            GlassActionButton(isProminent: false, action: onOpenAccessibility) {
                                Label("2. Open Accessibility Settings", systemImage: "arrow.up.forward.app")
                            }
                            .controlSize(.regular)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColor.statusWarning.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppColor.statusWarning.opacity(0.25), lineWidth: 1)
                    )
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.statusSuccess)

                        Text("Driver binary is authorized. USB touch coordinates are actively synthesized into native gestures.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(Color.primary.opacity(0.85))

                        Spacer()

                        GlassActionButton(isProminent: false, tint: .blue, action: onRevealBinary) {
                            Label("Reveal Binary in Finder", systemImage: "folder")
                        }
                        .controlSize(.regular)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColor.statusSuccess.opacity(0.08))
                    )
                }

                Divider()
                    .opacity(0.3)

                PermissionItemRow(
                    title: "Accessibility (Synthetic Pointer & Gestures)",
                    subtitle: "Allows ~/.local/bin/m14ttouch to simulate cursor clicks, text selection, drag & drop, and multi-finger gestures. (Settings app does not require permissions).",
                    icon: "hand.point.up.left.and.text",
                    iconColor: .purple,
                    isGranted: accessibilityGranted,
                    onGrant: onRequestAccessibility,
                    onSettings: onOpenAccessibility
                )
            }
        }
    }
}

// MARK: - Permission Item Row

private struct PermissionItemRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let isGranted: Bool
    let onGrant: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconSquircle(icon: icon, color: iconColor, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)

                    if isGranted {
                        GlassBadge(text: "Granted", icon: "checkmark.circle.fill", color: AppColor.statusSuccess)
                    } else {
                        GlassBadge(text: "Action Required", icon: "exclamationmark.triangle.fill", color: AppColor.statusWarning)
                    }
                }

                Text(subtitle)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isGranted {
                GlassActionButton(isProminent: false, action: onSettings) {
                    Text("Open Settings")
                }
                .controlSize(.regular)
            } else {
                GlassActionButton(isProminent: true, tint: AppColor.statusWarning, action: onGrant) {
                    Label(
                        title: { Text("Grant Access") },
                        icon: { Image(systemName: "arrow.up.forward.app") }
                    )
                }
                .controlSize(.regular)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}

// MARK: - Driver Service Control Card

private struct DriverServiceControlCard: View {
    let isRunning: Bool
    let pid: Int?
    @Binding var runAtLogin: Bool
    let isSaving: Bool
    let saveSuccess: Bool
    let onSave: () -> Void
    let onRestart: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onOpenLogs: () -> Void

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    GlassSectionHeader(
                        title: "Driver Service & Daemon",
                        subtitle: "Low-latency background driver managing touch coordinate mapping, active stylus, and trackpad gestures",
                        icon: "cpu.fill",
                        iconColor: .blue
                    )

                    Spacer()

                    if isRunning {
                        if let pid {
                            GlassBadge(text: "Running (PID \(pid))", icon: "bolt.fill", color: AppColor.statusSuccess)
                        } else {
                            GlassBadge(text: "Running", icon: "bolt.fill", color: AppColor.statusSuccess)
                        }
                    } else {
                        GlassBadge(text: "Stopped", icon: "stop.circle.fill", color: .secondary)
                    }
                }

                Divider()
                    .opacity(0.3)

                HStack(spacing: 14) {
                    StatusDot(color: isRunning ? AppColor.statusSuccess : AppColor.statusWarning, isPulsing: isRunning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isRunning ? "Background Driver Active" : "Background Driver Inactive")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)

                        if isRunning {
                            Text("The driver is actively translating M14t touch & stylus events with sub-millisecond precision.")
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(Color.primary.opacity(0.75))
                        } else {
                            Text("Start the driver or enable 'Run at Login' to process touch & pencil gestures.")
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(Color.primary.opacity(0.75))
                        }
                    }

                    Spacer()

                    if isRunning {
                        GlassActionButton(isProminent: false, action: onStop) {
                            Label("Stop Driver", systemImage: "stop.fill")
                        }
                        .controlSize(.regular)
                    } else {
                        GlassActionButton(isProminent: true, tint: AppColor.statusSuccess, action: onStart) {
                            Label("Start Driver", systemImage: "play.fill")
                        }
                        .controlSize(.regular)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                )

                SettingRow(
                    icon: "bolt.badge.clock.fill",
                    iconColor: .indigo,
                    title: "Start driver automatically at macOS login",
                    subtitle: "Installs a persistent LaunchAgent daemon in ~/Library/LaunchAgents"
                ) {
                    Toggle("", isOn: $runAtLogin)
                        .labelsHidden()
                }

                HStack(spacing: 12) {
                    GlassActionButton(isProminent: true, tint: saveSuccess ? AppColor.statusSuccess : .accentColor, action: onSave) {
                        Label(
                            title: {
                                Text(saveSuccess ? "Saved!" : (isSaving ? "Saving..." : "Save Configuration"))
                                    .fontWeight(.semibold)
                            },
                            icon: {
                                Image(systemName: saveSuccess ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                            }
                        )
                        .frame(minWidth: 160)
                    }
                    .controlSize(.regular)
                    .keyboardShortcut("s", modifiers: .command)

                    GlassActionButton(isProminent: false, action: onRestart) {
                        Label("Save & Restart Driver", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.regular)

                    Spacer()

                    GlassActionButton(isProminent: false, action: onOpenLogs) {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    .controlSize(.regular)
                    .help("Open driver logs folder in Finder")
                }
            }
        }
    }
}

// MARK: - Touch Calibration Card

private struct TouchCalibrationCard: View {
    let isCalibrating: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onReset: () -> Void

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(
                    title: "Touch Coordinate Calibration",
                    subtitle: "Fine-tune digitizer boundary mapping for pixel-perfect edge accuracy",
                    icon: "target",
                    iconColor: .purple
                )

                Divider()
                    .opacity(0.3)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCalibrating ? "Calibration Running" : "Hardware Calibration")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text(isCalibrating
                             ? "Touch all 4 screen corners firmly on the M14t, then click 'Stop Calibration'."
                             : "The Lenovo ThinkVision M14t uses factory raw bounds (12372×6960). Calibrate if touches drift near the bezels.")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        if isCalibrating {
                            GlassActionButton(isProminent: true, tint: .red, action: onStop) {
                                Label("Stop Calibration", systemImage: "stop.circle.fill")
                            }
                            .controlSize(.regular)
                        } else {
                            GlassActionButton(isProminent: false, tint: .purple, action: onStart) {
                                Label("4-Corner Calibrate", systemImage: "viewfinder")
                            }
                            .controlSize(.regular)
                        }

                        GlassActionButton(isProminent: false, action: onReset) {
                            Text("Reset Factory")
                        }
                        .controlSize(.regular)
                        .help("Restore default Lenovo 12372×6960 calibration bounds")
                    }
                }
            }
        }
    }
}

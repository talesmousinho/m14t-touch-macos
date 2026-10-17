import SwiftUI
import M14tTouchCore

public struct DisplaySettingsView: View {
    @EnvironmentObject private var model: SettingsModel

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DisplayTargetCard(
                    autoDetect: $model.preferences.autoDetectM14tDisplay,
                    displayIndex: $model.preferences.displayIndex,
                    displays: model.displays,
                    isM14tConnected: model.isM14tConnected,
                    onRefresh: model.refreshDisplays
                )

                CursorReturnCard(
                    returnCursorToMainDisplay: $model.preferences.returnCursorToMainDisplay
                )

                ResolutionPresetCard(
                    preset: $model.preferences.displayResolutionPreset,
                    onApply: model.applyDisplayResolution
                )

                AxesOrientationCard(
                    invertX: $model.preferences.invertX,
                    invertY: $model.preferences.invertY
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Display Target Card

private struct DisplayTargetCard: View {
    @Binding var autoDetect: Bool
    @Binding var displayIndex: Int
    let displays: [DisplayInfo]
    let isM14tConnected: Bool
    let onRefresh: () -> Void

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                GlassSectionHeader(
                    title: "Display Mapping Target",
                    subtitle: "Directs touch and stylus digitizer coordinate mapping to the correct display surface",
                    icon: "display",
                    iconColor: .blue
                )

                Divider()
                    .opacity(0.3)

                VStack(spacing: 12) {
                    SettingRow(
                        icon: "lock.display",
                        iconColor: .blue,
                        title: "Automatically lock to ThinkVision M14t",
                        subtitle: "Binds to M14t EDID across reconnects and multi-monitor changes"
                    ) {
                        Toggle("", isOn: $autoDetect)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                        .opacity(0.2)

                    SettingRow(
                        icon: "display.and.arrow.down",
                        iconColor: .indigo,
                        title: "Fallback Target Display",
                        subtitle: "Used if M14t monitor EDID is not actively detected"
                    ) {
                        HStack(spacing: 8) {
                            Picker("Target Display", selection: $displayIndex) {
                                ForEach(displays, id: \.index) { display in
                                    Text(displayTitle(display)).tag(display.index)
                                }
                            }
                            .labelsHidden()
                            .disabled(autoDetect && isM14tConnected)

                            GlassActionButton(isProminent: false, action: onRefresh) {
                                Text("Refresh")
                            }
                            .controlSize(.regular)
                        }
                    }
                }
            }
        }
    }

    private func displayTitle(_ display: DisplayInfo) -> String {
        var tags: [String] = []
        if display.isM14t { tags.append("M14t") }
        if display.isHiDPI { tags.append("2x HiDPI") }
        if display.isMain { tags.append("main") }
        let suffix = tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))"
        return "[\(display.index)] \(display.name) — \(Int(display.bounds.width))×\(Int(display.bounds.height))\(suffix)"
    }
}

// MARK: - Cursor Auto-Return Card

private struct CursorReturnCard: View {
    @Binding var returnCursorToMainDisplay: Bool

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                GlassSectionHeader(
                    title: "Multi-Screen Cursor Navigation",
                    subtitle: "Automatically return mouse pointer to main display after touching the external screen",
                    icon: "cursorarrow.motionlines",
                    iconColor: .teal
                )

                Divider()
                    .opacity(0.3)

                SettingRow(
                    icon: "arrow.uturn.backward.circle.fill",
                    iconColor: .teal,
                    title: "Auto-Return Pointer to Main Display",
                    subtitle: "Snaps pointer back to main screen as soon as trackpad or mouse is used after touch"
                ) {
                    Toggle("", isOn: $returnCursorToMainDisplay)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
}

// MARK: - Resolution Preset Card

private struct ResolutionPresetCard: View {
    @Binding var preset: DisplayResolutionPreset
    let onApply: () -> Void

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    GlassSectionHeader(
                        title: "M14t HiDPI Scaling & Refresh Rate",
                        subtitle: "Configure crisp 2x Retina rendering and optimal 75Hz refresh rate for the 14-inch panel",
                        icon: "sparkles.rectangle.stack.fill",
                        iconColor: .purple
                    )

                    Spacer()

                    GlassActionButton(isProminent: true, tint: .purple, action: onApply) {
                        Label("Apply Resolution Now", systemImage: "bolt.fill")
                    }
                    .controlSize(.regular)
                }

                Divider()
                    .opacity(0.3)

                VStack(alignment: .leading, spacing: 14) {
                    SettingRow(
                        icon: "aspectratio.fill",
                        iconColor: .purple,
                        title: "Active Resolution Preset",
                        subtitle: "Controls Retina scaling buffer and display refresh rate"
                    ) {
                        Picker("M14t Resolution", selection: $preset) {
                            ForEach(DisplayResolutionPreset.selectablePresets, id: \.self) { p in
                                Text(p.label).tag(p)
                            }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PresetTipRow(
                            title: "1920×1080 @ 75Hz (2x Retina 4K)",
                            tag: "Recommended",
                            description: "True 75Hz high-refresh rate combined with 4K Retina downsampling. Silky smooth stylus inking."
                        )
                        PresetTipRow(
                            title: "1600×900 @ 60Hz (2x Retina QHD+)",
                            tag: "Balanced",
                            description: "Optimal balance between UI touch targets and screen workspace for the 14\" display size."
                        )
                        PresetTipRow(
                            title: "1344×756 @ 60Hz (2x Retina 2.6K)",
                            tag: "Large Touch Targets",
                            description: "Generous sizing for comfortable finger tapping and tablet navigation."
                        )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.purple.opacity(0.06))
                    )
                }
            }
        }
    }
}

// MARK: - Preset Tip Row

private struct PresetTipRow: View {
    let title: String
    let tag: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.purple.opacity(0.5))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                    GlassBadge(text: tag, color: .purple)
                }
                Text(description)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
        }
    }
}

// MARK: - Axes Orientation Card

private struct AxesOrientationCard: View {
    @Binding var invertX: Bool
    @Binding var invertY: Bool

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(
                    title: "Orientation & Coordinate Inversion",
                    subtitle: "Adjust coordinate mapping when the display is physically rotated or placed upside-down",
                    icon: "arrow.triangle.swap",
                    iconColor: .teal
                )

                Divider()
                    .opacity(0.3)

                VStack(spacing: 12) {
                    SettingRow(
                        icon: "arrow.left.and.right.square.fill",
                        iconColor: .teal,
                        title: "Invert Horizontal X Axis",
                        subtitle: "Mirrors horizontal touch coordinates from right to left"
                    ) {
                        Toggle("", isOn: $invertX)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                        .opacity(0.2)

                    SettingRow(
                        icon: "arrow.up.and.down.square.fill",
                        iconColor: .cyan,
                        title: "Invert Vertical Y Axis",
                        subtitle: "Mirrors vertical touch coordinates from bottom to top"
                    ) {
                        Toggle("", isOn: $invertY)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
        }
    }
}

import SwiftUI
import M14tTouchCore

public struct TouchGesturesView: View {
    @EnvironmentObject private var model: SettingsModel

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OneFingerTabletCard(
                    mode: $model.preferences.oneFingerMode,
                    tapToClick: $model.preferences.tapToClick,
                    longPressRightClick: $model.preferences.longPressRightClick,
                    dragThreshold: $model.preferences.dragThreshold
                )

                TwoFingerTrackpadCard(
                    twoFingerRightClick: $model.preferences.twoFingerRightClick,
                    twoFingerScroll: $model.preferences.twoFingerScroll,
                    naturalScrolling: $model.preferences.naturalScrolling,
                    pinchToZoom: $model.preferences.pinchToZoom
                )

                ThreeFingerSpacesCard(
                    threeFingerSwipes: $model.preferences.threeFingerSwipes,
                    naturalSpacesSwipe: $model.preferences.naturalSpacesSwipe
                )

                DiagnosticsCard(
                    debugMode: $model.preferences.debugMode
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - 1-Finger Tablet Card

private struct OneFingerTabletCard: View {
    @Binding var mode: OneFingerMode
    @Binding var tapToClick: Bool
    @Binding var longPressRightClick: Bool
    @Binding var dragThreshold: Double

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                GlassSectionHeader(
                    title: "1-Finger Tablet Experience",
                    subtitle: "Choose between standard desktop mouse selection or iPadOS-style direct touch scrolling",
                    icon: "hand.point.up.left.fill",
                    iconColor: .blue
                )

                Divider()
                    .opacity(0.3)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        TabletModeSelectionButton(
                            mode: .selectAndDrag,
                            currentMode: mode,
                            title: "Desktop Select & Drag",
                            subtitle: "Direct mouse dragging: selects text, moves windows, drags sliders",
                            icon: "cursorarrow.and.square.on.square.dashed",
                            gradient: LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                            onSelect: { mode = .selectAndDrag }
                        )

                        TabletModeSelectionButton(
                            mode: .scrollAndHoldToSelect,
                            currentMode: mode,
                            title: "iPadOS Smooth Scroll",
                            subtitle: "1 finger scrolls web & apps; brief hold (~240ms) then drag selects text",
                            icon: "hand.draw.fill",
                            gradient: LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            onSelect: { mode = .scrollAndHoldToSelect }
                        )
                    }

                    Divider()
                        .opacity(0.2)

                    VStack(spacing: 12) {
                        SettingRow(
                            icon: "hand.tap.fill",
                            iconColor: AppColor.statusSuccess,
                            title: "Tap to Click",
                            subtitle: "Single-tap clicks, double-tap selects word, triple-tap selects paragraph"
                        ) {
                            Toggle("", isOn: $tapToClick)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()
                            .opacity(0.2)

                        SettingRow(
                            icon: "clock.arrow.circlepath",
                            iconColor: .orange,
                            title: "Long-Press for Right-Click",
                            subtitle: "Stationary 0.5s finger hold summons context menu at touch position"
                        ) {
                            Toggle("", isOn: $longPressRightClick)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()
                            .opacity(0.2)

                        SettingRow(
                            icon: "waveform.path.badge.plus",
                            iconColor: .blue,
                            title: "Drag Jitter Suppression",
                            subtitle: "Filters natural finger micro-tremor when tapping buttons (\(String(format: "%.1f", dragThreshold)) px)"
                        ) {
                            Slider(value: $dragThreshold, in: 1.5...12.0, step: 0.5)
                                .frame(width: 140)
                                .tint(.blue)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tablet Mode Selection Button

private struct TabletModeSelectionButton: View {
    let mode: OneFingerMode
    let currentMode: OneFingerMode
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let onSelect: () -> Void

    private var isSelected: Bool { mode == currentMode }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconSquircle(icon: icon, gradient: gradient, size: 30)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.blue)
                    }
                }

                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2-Finger Trackpad Card

private struct TwoFingerTrackpadCard: View {
    @Binding var twoFingerRightClick: Bool
    @Binding var twoFingerScroll: Bool
    @Binding var naturalScrolling: Bool
    @Binding var pinchToZoom: Bool

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(
                    title: "2-Finger MacBook Trackpad Gestures",
                    subtitle: "Fluid inertial trackpad scroll and gesture gestures identical to Apple Magic Trackpad",
                    icon: "hand.point.up.braille.fill",
                    iconColor: .teal
                )

                Divider()
                    .opacity(0.3)

                VStack(spacing: 12) {
                    SettingRow(
                        icon: "cursorarrow.rays",
                        iconColor: .teal,
                        title: "2-Finger Tap for Right-Click",
                        subtitle: "Tap two fingers together anywhere to trigger context menu"
                    ) {
                        Toggle("", isOn: $twoFingerRightClick)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                        .opacity(0.2)

                    SettingRow(
                        icon: "arrow.up.and.down.circle.fill",
                        iconColor: .blue,
                        title: "2-Finger Smooth Inertial Scroll",
                        subtitle: "Sub-pixel fluid trackpad panning across web pages and documents"
                    ) {
                        Toggle("", isOn: $twoFingerScroll)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                        .opacity(0.2)

                    SettingRow(
                        icon: "arrow.triangle.swap",
                        iconColor: AppColor.statusSuccess,
                        title: "Natural Scrolling Direction",
                        subtitle: "Content moves in the same direction as fingers (macOS default)"
                    ) {
                        Toggle("", isOn: $naturalScrolling)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                        .opacity(0.2)

                    SettingRow(
                        icon: "arrow.up.left.and.down.right.magnifyingglass",
                        iconColor: .indigo,
                        title: "2-Finger Pinch to Zoom",
                        subtitle: "Smooth zooming in Safari, Figma, Preview, Photos, and Maps"
                    ) {
                        Toggle("", isOn: $pinchToZoom)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
        }
    }
}

// MARK: - 3 & 4-Finger Spaces Card

private struct ThreeFingerSpacesCard: View {
    @Binding var threeFingerSwipes: Bool
    @Binding var naturalSpacesSwipe: Bool

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(
                    title: "3 & 4-Finger Desktop & Spaces Gestures",
                    subtitle: "Quickly navigate macOS Spaces, Mission Control, and App Exposé with full hand swipes",
                    icon: "square.split.3x3.fill",
                    iconColor: .purple
                )

                Divider()
                    .opacity(0.3)

                VStack(spacing: 12) {
                    SettingRow(
                        icon: "rectangle.split.3x1.fill",
                        iconColor: .purple,
                        title: "3 / 4-Finger Multi-Touch Swipes",
                        subtitle: "Swipe Left/Right for Desktops, Up for Mission Control, Down for Exposé"
                    ) {
                        Toggle("", isOn: $threeFingerSwipes)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                        .opacity(0.2)

                    SettingRow(
                        icon: "arrow.left.and.right.text.vertical",
                        iconColor: .indigo,
                        title: "Natural Spaces Swipe Direction",
                        subtitle: "Swipe follows natural trackpad gesture physics"
                    ) {
                        Toggle("", isOn: $naturalSpacesSwipe)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
        }
    }
}

// MARK: - Diagnostics Card

private struct DiagnosticsCard: View {
    @Binding var debugMode: Bool

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(
                    title: "Diagnostics & Debug Mode",
                    subtitle: "Prints incoming USB HID packets and gesture state machine transitions to helper.err.log",
                    icon: "terminal.fill",
                    iconColor: .gray
                )

                Divider()
                    .opacity(0.3)

                SettingRow(
                    icon: "terminal",
                    iconColor: .gray,
                    title: "Verbose HID Debug Logging",
                    subtitle: "Writes raw USB coordinate reports to ~/Library/Logs/M14tTouch/helper.err.log"
                ) {
                    Toggle("", isOn: $debugMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
}

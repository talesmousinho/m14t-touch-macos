import SwiftUI
import M14tTouchCore

public struct SmartPencilView: View {
    @EnvironmentObject private var model: SettingsModel

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SmartPencilMasterCard(
                    stylusEnabled: $model.preferences.stylusEnabled,
                    palmRejection: $model.preferences.palmRejectionWhileStylusInRange
                )

                BarrelButtonsCard(
                    stylusEnabled: model.preferences.stylusEnabled,
                    bottomAction: $model.preferences.barrelButtonAction,
                    topAction: $model.preferences.secondaryBarrelButtonAction
                )

                DigitizerSpecsCard()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Smart Pencil Master Card

private struct SmartPencilMasterCard: View {
    @Binding var stylusEnabled: Bool
    @Binding var palmRejection: Bool

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    GlassSectionHeader(
                        title: "Smart Pencil & Active Stylus",
                        subtitle: "Lenovo Active Pen with 4096 levels of hardware pressure sensitivity and tilt reporting",
                        icon: "pencil.tip.crop.circle",
                        iconColor: .pink
                    )

                    Spacer()

                    Toggle("", isOn: $stylusEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Divider()
                    .opacity(0.3)

                SettingRow(
                    icon: "hand.raised.slash.fill",
                    iconColor: .orange,
                    title: "Palm Rejection in Hover Range",
                    subtitle: "Suppresses finger touch while pen tip is within 15mm of the screen glass"
                ) {
                    Toggle("", isOn: $palmRejection)
                        .labelsHidden()
                        .disabled(!stylusEnabled)
                }
            }
        }
    }
}

// MARK: - Barrel Buttons Card

private struct BarrelButtonsCard: View {
    let stylusEnabled: Bool
    @Binding var bottomAction: StylusButtonAction
    @Binding var topAction: StylusButtonAction

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                GlassSectionHeader(
                    title: "Side Barrel Buttons",
                    subtitle: "Customize actions triggered by the physical rocker buttons on the stylus body",
                    icon: "slider.vertical.3",
                    iconColor: .indigo
                )

                Divider()
                    .opacity(0.3)

                VStack(spacing: 12) {
                    SettingRow(
                        icon: "cursorarrow.click.2",
                        iconColor: .blue,
                        title: "Bottom Barrel Button",
                        subtitle: "Closest to pen tip (standard primary index finger hold)"
                    ) {
                        Picker("Bottom Button", selection: $bottomAction) {
                            ForEach(StylusButtonAction.allCases, id: \.self) { action in
                                HStack {
                                    Image(systemName: iconForAction(action))
                                    Text(action.label)
                                }
                                .tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }

                    Divider()
                        .opacity(0.2)

                    SettingRow(
                        icon: "eraser.line.dashed",
                        iconColor: .purple,
                        title: "Top Barrel Button",
                        subtitle: "Secondary upper button on the pen barrel"
                    ) {
                        Picker("Top Button", selection: $topAction) {
                            ForEach(StylusButtonAction.allCases, id: \.self) { action in
                                HStack {
                                    Image(systemName: iconForAction(action))
                                    Text(action.label)
                                }
                                .tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }
                }
                .disabled(!stylusEnabled)
                .opacity(stylusEnabled ? 1.0 : 0.5)
            }
        }
    }

    private func iconForAction(_ action: StylusButtonAction) -> String {
        switch action {
        case .rightClick:  return "cursorarrow.click.2"
        case .eraser:      return "eraser.line.dashed"
        case .middleClick: return "arrow.up.and.down.and.arrow.left.and.right"
        case .doubleClick: return "hand.tap"
        case .undo:        return "arrow.uturn.backward"
        case .disabled:    return "nosign"
        }
    }
}

// MARK: - Digitizer Specs Card

private struct DigitizerSpecsCard: View {
    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(
                    title: "Active Digitizer Specifications",
                    subtitle: "Wacom AES 2.0 / Lenovo Active Pen hardware capabilities supported by the M14t driver",
                    icon: "info.circle.fill",
                    iconColor: .teal
                )

                Divider()
                    .opacity(0.3)

                HStack(spacing: 16) {
                    SpecPill(icon: "waveform", iconColor: .pink, title: "4,096 Levels", subtitle: "Pressure Curve")
                    SpecPill(icon: "angle", iconColor: .purple, title: "±60° Tilt", subtitle: "X/Y Vector")
                    SpecPill(icon: "bolt.horizontal.fill", iconColor: .blue, title: "240 Hz", subtitle: "Sample Rate")
                    SpecPill(icon: "hand.raised.slash.fill", iconColor: .orange, title: "Hardware", subtitle: "Palm Reject")
                }
            }
        }
    }
}

// MARK: - Spec Pill

private struct SpecPill: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            IconSquircle(icon: icon, color: iconColor, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(Color.primary.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(iconColor.opacity(0.08))
        )
    }
}

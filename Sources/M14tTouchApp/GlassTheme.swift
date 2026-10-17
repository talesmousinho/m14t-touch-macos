import AppKit
import SwiftUI

// MARK: - App Color & Semantic Palette

public enum AppColor {
    /// High-contrast Apple Forest/Emerald Green (accessible across dark & light glass)
    public static let statusSuccess = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.45, alpha: 1.0)
            : NSColor(calibratedRed: 0.08, green: 0.52, blue: 0.26, alpha: 1.0)
    }))

    /// High-contrast Apple Amber Warning (accessible across dark & light glass)
    public static let statusWarning = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.20, alpha: 1.0)
            : NSColor(calibratedRed: 0.78, green: 0.40, blue: 0.05, alpha: 1.0)
    }))

    /// Subtle Emerald gradient for active badges and squircle icons
    public static let successGradient = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.68, blue: 0.38),
            Color(red: 0.08, green: 0.50, blue: 0.26)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle Amber gradient for warning badges and squircle icons
    public static let warningGradient = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.60, blue: 0.15),
            Color(red: 0.80, green: 0.42, blue: 0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Window Translucency Configurator

/// Configures NSWindow to be completely transparent with full-size content view so that
/// the behind-window NSVisualEffectView blurs the actual desktop wallpaper and background windows.
public struct WindowTranslucencyConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> WindowTranslucencyView {
        WindowTranslucencyView()
    }

    public func updateNSView(_ nsView: WindowTranslucencyView, context: Context) {}
}

public final class WindowTranslucencyView: NSView {
    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        DispatchQueue.main.async { [weak window] in
            guard let window, let themeFrame = window.contentView?.superview else { return }

            func findTitlebarContainer(in v: NSView) -> NSView? {
                if "\(type(of: v))".contains("TitlebarContainer") {
                    return v
                }
                for sub in v.subviews {
                    if let found = findTitlebarContainer(in: sub) {
                        return found
                    }
                }
                return nil
            }

            if let titlebarContainer = findTitlebarContainer(in: themeFrame) {
                let backdropId = NSUserInterfaceItemIdentifier("M14tTitlebarBackdrop")
                if !titlebarContainer.subviews.contains(where: { $0.identifier == backdropId }) {
                    let backdrop = NSVisualEffectView(frame: titlebarContainer.bounds)
                    backdrop.identifier = backdropId
                    backdrop.autoresizingMask = [.width, .height]
                    backdrop.material = .headerView
                    backdrop.blendingMode = .withinWindow
                    backdrop.state = .active

                    let separator = NSBox(frame: NSRect(x: 0, y: 0, width: titlebarContainer.bounds.width, height: 1))
                    separator.identifier = NSUserInterfaceItemIdentifier("M14tTitlebarSeparator")
                    separator.boxType = .custom
                    separator.borderColor = .separatorColor
                    separator.borderWidth = 1
                    separator.fillColor = .clear
                    separator.autoresizingMask = [.width, .minYMargin]

                    titlebarContainer.addSubview(backdrop, positioned: .below, relativeTo: nil)
                    titlebarContainer.addSubview(separator, positioned: .above, relativeTo: backdrop)
                }
            }
        }
    }
}

// MARK: - AppKit Visual Effect Bridge

/// Native AppKit visual effect view that drives true macOS vibrancy and desktop blur.
public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    public let state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .fullScreenUI,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Apple System Settings Colorful Icon Squircle

/// Vibrant gradient squircle icon representing settings categories and rows (Apple HIG style).
public struct IconSquircle: View {
    public let icon: String
    public let gradient: LinearGradient
    public let size: CGFloat

    public init(icon: String, gradient: LinearGradient, size: CGFloat = 28) {
        self.icon = icon
        self.gradient = gradient
        self.size = size
    }

    public init(icon: String, color: Color, size: CGFloat = 28) {
        self.icon = icon
        self.gradient = LinearGradient(
            colors: [color.opacity(0.85), color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(gradient)
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)

            Image(systemName: icon)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Apple Settings Row

/// Standard macOS System Settings row with vibrant squircle icon, title, subtitle, and control.
public struct SettingRow<TrailingContent: View>: View {
    public let icon: String
    public let iconColor: Color
    public let title: String
    public let subtitle: String?
    @ViewBuilder public let trailing: () -> TrailingContent

    public init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconSquircle(icon: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Liquid Glass Container

/// Groups multiple Liquid Glass elements for GPU blending, morphing, and optimal rendering.
public struct GlassGroup<Content: View>: View {
    public let spacing: CGFloat
    @ViewBuilder public let content: () -> Content

    public init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

// MARK: - Liquid Glass Card

/// Translucent card with specular highlight rim and dynamic material.
public struct GlassCard<Content: View>: View {
    public let cornerRadius: CGFloat
    public let padding: CGFloat
    public let tint: Color?
    public let isInteractive: Bool
    @ViewBuilder public let content: () -> Content

    public init(
        cornerRadius: CGFloat = 14,
        padding: CGFloat = 16,
        tint: Color? = nil,
        isInteractive: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.isInteractive = isInteractive
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26, *) {
            glassContent
        } else {
            fallbackContent
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private var glassContent: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if let tint {
                if isInteractive {
                    content()
                        .padding(padding)
                        .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    content()
                        .padding(padding)
                        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                }
            } else {
                if isInteractive {
                    content()
                        .padding(padding)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    content()
                        .padding(padding)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                }
            }
        }
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.35),
                        Color.white.opacity(0.10),
                        Color.primary.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    private var fallbackContent: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint != nil ? tint!.opacity(0.08) : Color.clear)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.white.opacity(0.08),
                                Color.primary.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Liquid Glass Action Button

public struct GlassActionButton<LabelContent: View>: View {
    public let isProminent: Bool
    public let tint: Color?
    public let action: () -> Void
    @ViewBuilder public let label: () -> LabelContent

    public init(
        isProminent: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        self.isProminent = isProminent
        self.tint = tint
        self.action = action
        self.label = label
    }

    public var body: some View {
        if #available(macOS 26, *) {
            if isProminent {
                Button(action: action, label: label)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                Button(action: action, label: label)
                    .buttonStyle(.glass)
                    .tint(tint)
            }
        } else {
            if isProminent {
                Button(action: action, label: label)
                    .buttonStyle(.borderedProminent)
                    .tint(tint ?? .accentColor)
            } else {
                Button(action: action, label: label)
                    .buttonStyle(.bordered)
                    .tint(tint)
            }
        }
    }
}

// MARK: - Status Dot

public struct StatusDot: View {
    public let color: Color
    public let isPulsing: Bool
    @State private var pulse: CGFloat = 1.0

    public init(color: Color, isPulsing: Bool = false) {
        self.color = color
        self.isPulsing = isPulsing
    }

    public var body: some View {
        ZStack {
            if isPulsing {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 2)
                    .scaleEffect(pulse)
                    .opacity(1.8 - Double(pulse))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                            pulse = 2.0
                        }
                    }
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.4), radius: 2)
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Glass Badge

public struct GlassBadge: View {
    public let text: String
    public let icon: String?
    public let color: Color

    public init(text: String, icon: String? = nil, color: Color = AppColor.statusSuccess) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.35), lineWidth: 1.0)
        )
    }
}

// MARK: - Section Header

public struct GlassSectionHeader: View {
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let iconColor: Color

    public init(title: String, subtitle: String? = nil, icon: String, iconColor: Color = .accentColor) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            IconSquircle(icon: icon, color: iconColor, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
            }
            Spacer()
        }
    }
}

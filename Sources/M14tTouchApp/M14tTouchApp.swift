import AppKit
import SwiftUI
import M14tTouchCore

@main
struct M14tTouchSettingsApp: App {
    @StateObject private var model = SettingsModel()

    var body: some Scene {
        WindowGroup("M14t Touch") {
            ZStack {
                // True macOS desktop blurred glass vibrancy
                VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow, state: .active)
                    .ignoresSafeArea()

                RootSplitView()
            }
            .background(WindowTranslucencyConfigurator())
            .environmentObject(model)
            .frame(minWidth: 800, minHeight: 680)
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 740)
    }
}

// MARK: - Root Split View

struct RootSplitView: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedTab: $model.selectedTab,
                allPermissionsGranted: model.allPermissionsGranted,
                isHelperRunning: model.isHelperRunning,
                isM14tConnected: model.isM14tConnected
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .background(Color.clear)
        } detail: {
            DetailContainerView(
                selectedTab: model.selectedTab,
                statusMessage: model.statusMessage,
                isHelperRunning: model.isHelperRunning,
                isSaving: model.isSaving,
                saveSuccess: model.saveSuccess,
                isRefreshingDisplays: model.isRefreshingDisplays,
                onRefreshDisplays: model.refreshDisplays,
                onRestartDriver: model.restartHelper,
                onSave: model.save
            )
            .background(Color.clear)
        }
        .navigationSplitViewStyle(.balanced)
        .toggleStyle(.switch)
        .toolbar {
            AppToolbarItems(
                allPermissionsGranted: model.allPermissionsGranted,
                isHelperRunning: model.isHelperRunning
            )
        }
    }
}

// MARK: - Sidebar View

private struct SidebarView: View {
    @Binding var selectedTab: SettingsTab
    let allPermissionsGranted: Bool
    let isHelperRunning: Bool
    let isM14tConnected: Bool

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            List(SettingsTab.allCases, selection: Binding(
                get: { selectedTab },
                set: { if let val = $0 { selectedTab = val } }
            )) { tab in
                SidebarItemRow(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    needsPermissionAttention: tab == .service && !allPermissionsGranted
                )
                .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer()

            SidebarStatusFooter(
                isM14tConnected: isM14tConnected,
                isHelperRunning: isHelperRunning
            )
            .padding(12)
        }
    }
}

// MARK: - Sidebar Header

private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            IconSquircle(
                icon: "hand.draw.fill",
                gradient: LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                size: 34
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("M14t Touch")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    GlassBadge(text: "2.1", color: .blue)
                }

                Text("ThinkVision Driver Companion")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(Color.primary.opacity(0.72))
            }
            Spacer()
        }
    }
}

// MARK: - Sidebar Item Row

private struct SidebarItemRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let needsPermissionAttention: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconSquircle(
                icon: tab.icon,
                gradient: tabGradient(for: tab),
                size: 24
            )

            Text(tab.rawValue)
                .font(.system(.body, design: .rounded, weight: isSelected ? .semibold : .medium))

            Spacer()

            if needsPermissionAttention {
                GlassBadge(text: "Action", icon: "exclamationmark.triangle.fill", color: .orange)
            }
        }
        .padding(.vertical, 3)
    }

    private func tabGradient(for tab: SettingsTab) -> LinearGradient {
        switch tab {
        case .service:
            return AppColor.successGradient
        case .display:
            return LinearGradient(colors: [Color.blue.opacity(0.85), Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stylus:
            return LinearGradient(colors: [Color.pink.opacity(0.85), Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gestures:
            return LinearGradient(colors: [Color.cyan.opacity(0.85), Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Sidebar Status Footer

private struct SidebarStatusFooter: View {
    let isM14tConnected: Bool
    let isHelperRunning: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(color: isM14tConnected ? AppColor.statusSuccess : AppColor.statusWarning)
                Text(isM14tConnected ? "ThinkVision M14t Connected" : "No M14t Detected")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(isM14tConnected ? Color.primary : Color.primary.opacity(0.65))
                Spacer()
            }

            HStack(spacing: 8) {
                StatusDot(color: isHelperRunning ? AppColor.statusSuccess : .secondary, isPulsing: isHelperRunning)
                Text(isHelperRunning ? "Background Driver Active" : "Background Driver Stopped")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(isHelperRunning ? Color.primary : Color.primary.opacity(0.65))
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}

// MARK: - Detail Container View

private struct DetailContainerView: View {
    let selectedTab: SettingsTab
    let statusMessage: String
    let isHelperRunning: Bool
    let isSaving: Bool
    let saveSuccess: Bool
    let isRefreshingDisplays: Bool
    let onRefreshDisplays: () -> Void
    let onRestartDriver: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.2)

            ZStack {
                switch selectedTab {
                case .service:
                    OverviewView()
                case .display:
                    DisplaySettingsView()
                case .stylus:
                    SmartPencilView()
                case .gestures:
                    TouchGesturesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
                .opacity(0.2)

            StatusFooterBar(
                statusMessage: statusMessage,
                isHelperRunning: isHelperRunning,
                isSaving: isSaving,
                saveSuccess: saveSuccess,
                isRefreshingDisplays: isRefreshingDisplays,
                onRefreshDisplays: onRefreshDisplays,
                onRestartDriver: onRestartDriver,
                onSave: onSave
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Status Footer Bar

private struct StatusFooterBar: View {
    let statusMessage: String
    let isHelperRunning: Bool
    let isSaving: Bool
    let saveSuccess: Bool
    let isRefreshingDisplays: Bool
    let onRefreshDisplays: () -> Void
    let onRestartDriver: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 7) {
                StatusDot(color: isHelperRunning ? AppColor.statusSuccess : AppColor.statusWarning, isPulsing: isHelperRunning)
                Text(statusMessage)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer()

            GlassActionButton(isProminent: false, action: onRefreshDisplays) {
                Label {
                    Text("Refresh Displays")
                } icon: {
                    SpinningRefreshIcon(
                        systemName: "arrow.triangle.2.circlepath",
                        size: 12,
                        isRefreshing: isRefreshingDisplays
                    )
                }
            }
            .controlSize(.regular)
            .disabled(isRefreshingDisplays)

            GlassActionButton(isProminent: false, action: onRestartDriver) {
                Label("Restart Driver", systemImage: "arrow.clockwise")
            }
            .controlSize(.regular)

            GlassActionButton(isProminent: true, tint: saveSuccess ? AppColor.statusSuccess : .accentColor, action: onSave) {
                Label(
                    title: {
                        Text(saveSuccess ? "Saved!" : (isSaving ? "Saving..." : "Save"))
                            .fontWeight(.semibold)
                    },
                    icon: {
                        Image(systemName: saveSuccess ? "checkmark" : "square.and.arrow.down")
                    }
                )
                .frame(minWidth: 70)
            }
            .controlSize(.regular)
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}

// MARK: - App Toolbar Items

private struct AppToolbarItems: ToolbarContent {
    let allPermissionsGranted: Bool
    let isHelperRunning: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .status) {
            HStack(spacing: 8) {
                if allPermissionsGranted {
                    GlassBadge(text: "Permissions Active", icon: "checkmark.shield.fill", color: AppColor.statusSuccess)
                } else {
                    GlassBadge(text: "Permissions Needed", icon: "exclamationmark.triangle.fill", color: AppColor.statusWarning)
                }

                if isHelperRunning {
                    GlassBadge(text: "Driver Running", icon: "bolt.fill", color: AppColor.statusSuccess)
                } else {
                    GlassBadge(text: "Driver Stopped", icon: "pause.circle.fill", color: .secondary)
                }
            }
        }
    }
}

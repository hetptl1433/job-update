import SwiftUI

/// Four primary destinations plus a persistent, visually distinct jump into
/// live voice. Less frequent tools remain available from the More hub.
struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @State private var presentedMoreSheet: MoreSheet?

    var body: some View {
        TabView(selection: primarySelection) {
            HomeView()
                .tag(AppState.Tab.home)
            FinanceView()
                .tag(AppState.Tab.finance)
            HealthView()
                .tag(AppState.Tab.health)
            MoreTabHost(onOpenMoreDestination: openMoreDestination)
                .tag(AppState.Tab.more)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OrbitControlBar(
                selection: $app.selectedTab,
                onVoice: { app.assistantLaunch = .voice },
                onOpenMoreDestination: openMoreDestination
            )
        }
        .sheet(isPresented: chatPresented) {
            NavigationStack {
                AssistantView(initialPrompt: app.assistantInitialPrompt ?? "")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                app.assistantLaunch = nil
                                app.assistantInitialPrompt = nil
                            }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentedMoreSheet) { sheet in
            MoreSheetContent(sheet: sheet)
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: voicePresented) {
            LiveVoiceView()
        }
    }

    /// Secondary destinations share the More tab visually while retaining
    /// their distinct AppState values for Home shortcuts and deep links.
    private var primarySelection: Binding<AppState.Tab> {
        Binding(
            get: {
                if app.selectedTab == .tasks || app.selectedTab == .jobs || app.selectedTab == .inbox {
                    return .more
                }
                return app.selectedTab
            },
            set: { app.selectedTab = $0 }
        )
    }

    private var chatPresented: Binding<Bool> {
        Binding(
            get: { app.assistantLaunch == .chat },
            set: { presented in
                if !presented, app.assistantLaunch == .chat {
                    app.assistantLaunch = nil
                    app.assistantInitialPrompt = nil
                }
            }
        )
    }

    private var voicePresented: Binding<Bool> {
        Binding(
            get: { app.assistantLaunch == .voice },
            set: { presented in
                if !presented, app.assistantLaunch == .voice {
                    app.assistantLaunch = nil
                }
            }
        )
    }

    private func openMoreDestination(_ destination: MoreDestination) {
        switch destination {
        case .tasks:
            withAnimation(.easeOut(duration: 0.18)) { app.selectedTab = .tasks }
        case .jobs:
            withAnimation(.easeOut(duration: 0.18)) { app.selectedTab = .jobs }
        case .inbox:
            withAnimation(.easeOut(duration: 0.18)) { app.selectedTab = .inbox }
        case .automations:
            app.selectedTab = .more
            presentedMoreSheet = .automations
        case .settings:
            app.selectedTab = .more
            presentedMoreSheet = .settings
        }
    }
}

private struct MoreTabHost: View {
    @EnvironmentObject private var app: AppState
    let onOpenMoreDestination: (MoreDestination) -> Void

    @ViewBuilder
    var body: some View {
        switch app.selectedTab {
        case .tasks:
            TasksView()
        case .jobs:
            JobsView()
        case .inbox:
            InboxView()
        default:
            OrbitMoreView(onOpenMoreDestination: onOpenMoreDestination)
        }
    }
}

struct OrbitControlBar: View {
    @Binding var selection: AppState.Tab
    let onVoice: () -> Void
    let onOpenMoreDestination: (MoreDestination) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let slotWidth = proxy.size.width / 5
            let voiceDiameter = min(48, max(40, slotWidth - 24))

            HStack(alignment: .center, spacing: 0) {
                destination(.home, title: "Home", symbol: "house", selectedSymbol: "house.fill")
                destination(.finance, title: "Finance", symbol: "creditcard", selectedSymbol: "creditcard.fill")

                Button(action: onVoice) {
                    VStack(spacing: 3) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.brand.opacity(0.18))
                                .frame(width: voiceDiameter + 7, height: voiceDiameter + 7)
                                .blur(radius: 7)
                            Circle()
                                .fill(AppTheme.brandGradient)
                                .frame(width: voiceDiameter, height: voiceDiameter)
                                .overlay(Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1))
                                .shadow(color: AppTheme.brand.opacity(0.38), radius: 9, y: 4)
                            Image(systemName: "waveform")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Orbit")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.brand)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .offset(y: dynamicTypeSize.isAccessibilitySize ? 0 : -4)
                }
                .buttonStyle(OrbitBarButtonStyle())
                .accessibilityLabel("Orbit voice")
                .accessibilityHint("Opens live voice assistant")

                destination(.health, title: "Health", symbol: "heart", selectedSymbol: "heart.fill")
                moreMenu
            }
            .padding(.horizontal, 5)
            .padding(.top, 7)
            .padding(.bottom, 3)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 61 : 68)
        .background(AppTheme.primarySurface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.border.opacity(0.75))
                .frame(height: 0.5)
        }
    }

    private func destination(
        _ tab: AppState.Tab,
        title: String,
        symbol: String,
        selectedSymbol: String
    ) -> some View {
        let isSelected = isDockSelected(tab)
        return Button {
            select(tab)
        } label: {
            dockLabel(tab, title: title, symbol: symbol, selectedSymbol: selectedSymbol)
        }
        .buttonStyle(OrbitBarButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var moreMenu: some View {
        let isSelected = isDockSelected(.more)
        return Menu {
            Button { onOpenMoreDestination(.tasks) } label: {
                Label("To Do", systemImage: "checklist")
            }
            Button { onOpenMoreDestination(.jobs) } label: {
                Label("Jobs", systemImage: "briefcase.fill")
            }
            Button { onOpenMoreDestination(.inbox) } label: {
                Label("Inbox", systemImage: "tray.fill")
            }
            Divider()
            Button { onOpenMoreDestination(.automations) } label: {
                Label("Automations", systemImage: "bolt.fill")
            }
            Button { onOpenMoreDestination(.settings) } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
        } label: {
            dockLabel(
                .more,
                title: "More",
                symbol: "square.grid.2x2",
                selectedSymbol: "square.grid.2x2.fill"
            )
        } primaryAction: {
            select(.more)
        }
        .menuIndicator(.hidden)
        .menuOrder(.priority)
        .buttonStyle(OrbitBarButtonStyle())
        .accessibilityLabel("More")
        .accessibilityHint("Tap to open More. Touch and hold for shortcuts.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dockLabel(
        _ tab: AppState.Tab,
        title: String,
        symbol: String,
        selectedSymbol: String
    ) -> some View {
        let isSelected = isDockSelected(tab)
        return VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 0 : 4) {
            Image(systemName: isSelected ? selectedSymbol : symbol)
                .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(isSelected ? AppTheme.brand : AppTheme.tertiaryText)
        .frame(maxWidth: .infinity, minHeight: 47)
        .contentShape(Rectangle())
    }

    private func select(_ tab: AppState.Tab) {
        withAnimation(.easeOut(duration: 0.18)) {
            selection = tab
        }
    }

    private func isDockSelected(_ tab: AppState.Tab) -> Bool {
        if tab == .more {
            return selection == .more || selection == .tasks || selection == .jobs || selection == .inbox
        }
        return selection == tab
    }
}

/// A calm, scannable home for tools that do not need permanent dock space.
/// Direct destinations continue to use AppState tabs so deep links and Home
/// shortcuts preserve their existing behavior.
struct OrbitMoreView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenMoreDestination: (MoreDestination) -> Void
    @State private var hasAppeared = false

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: AppTheme.Spacing.md),
            GridItem(.flexible(), spacing: AppTheme.Spacing.md)
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    intro

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Workspace").sectionLabel()

                        LazyVGrid(columns: columns, spacing: AppTheme.Spacing.md) {
                            tabCard(
                                .tasks,
                                title: "To Do",
                                detail: "Plan what matters next",
                                symbol: "checklist"
                            )
                            tabCard(
                                .jobs,
                                title: "Jobs",
                                detail: "Track every opportunity",
                                symbol: "briefcase.fill"
                            )
                            tabCard(
                                .inbox,
                                title: "Inbox",
                                detail: "Review important updates",
                                symbol: "tray.fill"
                            )
                            sheetCard(
                                .automations,
                                title: "Automations",
                                detail: "Let Orbit watch for you",
                                symbol: "bolt.fill"
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Account").sectionLabel()
                        settingsRow
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.xxl)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
            }
            .background(AppTheme.background)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if reduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(.easeOut(duration: 0.28)) {
                        hasAppeared = true
                    }
                }
            }
        }
    }

    private var intro: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(AppTheme.brand.opacity(0.12))
                    .frame(width: 58, height: 58)
                Circle()
                    .strokeBorder(AppTheme.brand.opacity(0.36), lineWidth: 1)
                    .frame(width: 58, height: 58)
                Image(systemName: "waveform")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Everything else, close by")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text("Your work tools, automations, and account settings live here.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardSurface()
    }

    private func tabCard(
        _ destination: MoreDestination,
        title: String,
        detail: String,
        symbol: String
    ) -> some View {
        Button {
            onOpenMoreDestination(destination)
        } label: {
            MoreDestinationLabel(title: title, detail: detail, symbol: symbol)
        }
        .buttonStyle(MoreCardButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func sheetCard(
        _ destination: MoreDestination,
        title: String,
        detail: String,
        symbol: String
    ) -> some View {
        Button {
            onOpenMoreDestination(destination)
        } label: {
            MoreDestinationLabel(title: title, detail: detail, symbol: symbol)
        }
        .buttonStyle(MoreCardButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private var settingsRow: some View {
        Button {
            onOpenMoreDestination(.settings)
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Connections, appearance, privacy, and account")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: AppTheme.Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.primarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(MoreCardButtonStyle())
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens connections, appearance, privacy, and account settings")
    }
}

enum MoreDestination {
    case tasks
    case jobs
    case inbox
    case automations
    case settings
}

private enum MoreSheet: String, Identifiable {
    case automations
    case settings

    var id: String { rawValue }
}

private struct MoreSheetContent: View {
    @Environment(\.dismiss) private var dismiss
    let sheet: MoreSheet

    var body: some View {
        Group {
            switch sheet {
            case .automations:
                ZStack(alignment: .topTrailing) {
                    AutomationsView()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.secondarySurface, in: Circle())
                            .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(OrbitBarButtonStyle())
                    .padding(.top, AppTheme.Spacing.sm)
                    .padding(.trailing, AppTheme.Spacing.lg)
                    .accessibilityLabel("Close Automations")
                }
            case .settings:
                SettingsView()
            }
        }
    }
}

private struct MoreDestinationLabel: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                Spacer(minLength: AppTheme.Spacing.sm)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.primarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct MoreCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct OrbitBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

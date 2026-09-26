import SwiftUI

/// Four primary destinations plus a persistent, visually distinct Orbit
/// launcher. Less frequent tools remain available from the More hub. On an
/// iPad with room for it, a sidebar lists every destination instead.
struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var presentedMoreSheet: MoreSheet?
    /// Automations or Settings, when the iPad sidebar shows one beside it.
    @State private var sidebarPage: MoreSheet?

    /// Narrow iPad windows, such as Slide Over, keep the iPhone dock.
    private var usesSidebar: Bool {
        DeviceProfile.isPad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSidebar {
                OrbitSidebarLayout(
                    page: $sidebarPage,
                    onVoice: { app.assistantLaunch = .voice },
                    onOpenMoreDestination: openMoreDestination
                )
            } else {
                dockLayout
            }
        }
        .sheet(isPresented: chatPresented) {
            NavigationStack {
                AssistantView(initialPrompt: app.assistantInitialPrompt ?? "")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { app.closeChat() }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(AppTheme.background)
        }
        .sheet(item: $presentedMoreSheet) { sheet in
            MoreSheetContent(sheet: sheet)
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: voicePresented) {
            LiveVoiceView()
        }
        .focusedSceneValue(\.orbitNavigator, navigator)
    }

    private var dockLayout: some View {
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
                onChat: { app.openAssistant() },
                onVoice: { app.assistantLaunch = .voice },
                onOpenMoreDestination: openMoreDestination
            )
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

    /// Beside the iPad sidebar, Chat fills the screen instead of a sheet.
    private var chatPresented: Binding<Bool> {
        Binding(
            get: { !usesSidebar && app.assistantLaunch == .chat },
            set: { presented in
                if !presented { app.closeChat() }
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

    private var navigator: OrbitNavigator {
        OrbitNavigator(
            show: show,
            openChat: {
                presentedMoreSheet = nil
                sidebarPage = nil
                app.openAssistant()
            },
            startVoice: { app.assistantLaunch = .voice },
            newTask: { app.quickTaskCaptureRequested = true },
            openSettings: { openMoreDestination(.settings) }
        )
    }

    private func show(_ tab: AppState.Tab) {
        app.closeChat()
        presentedMoreSheet = nil
        sidebarPage = nil
        withAnimation(.easeOut(duration: 0.18)) { app.selectedTab = tab }
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
            openPage(.automations)
        case .settings:
            openPage(.settings)
        }
    }

    private func openPage(_ page: MoreSheet) {
        if usesSidebar {
            app.closeChat()
            sidebarPage = page
        } else {
            app.selectedTab = .more
            presentedMoreSheet = page
        }
    }
}

private extension AppState {
    func closeChat() {
        guard assistantLaunch == .chat else { return }
        assistantLaunch = nil
        assistantInitialPrompt = nil
    }
}

/// iPad layout: every destination in a sidebar, with Orbit Chat and live voice
/// at the top, and the selected one filling the rest of the screen. Each
/// screen keeps its own navigation stack, as it does behind the iPhone dock.
private struct OrbitSidebarLayout: View {
    @EnvironmentObject private var app: AppState
    @Binding var page: MoreSheet?
    let onVoice: () -> Void
    let onOpenMoreDestination: (MoreDestination) -> Void

    /// From this width, screens get wider margins, show more items, and lay
    /// their sections out in two columns.
    private static let wideWidth: CGFloat = 800
    /// Added to each screen's own side margin once it's wide.
    private static let wideMargin: CGFloat = 12
    /// Wider than this, such as on an external display, content stays centered.
    private static let maxContentWidth: CGFloat = 1600

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            GeometryReader { proxy in
                let isWide = proxy.size.width >= Self.wideWidth
                detail
                    .safeAreaPadding(
                        .horizontal,
                        max(isWide ? Self.wideMargin : 0, (proxy.size.width - Self.maxContentWidth) / 2)
                    )
                    .environment(\.orbitWideLayout, isWide)
                    .environment(\.orbitOpenSettings, openSettings)
            }
            .background(AppTheme.background.ignoresSafeArea())
        }
        .onChange(of: DetailRoute(tab: app.selectedTab, showsChat: app.assistantLaunch == .chat)) { old, new in
            // A deep link, widget or shortcut that opens another screen
            // replaces Chat or a page showing beside the sidebar.
            guard old.tab != new.tab else { return }
            page = nil
            if old.showsChat, new.showsChat { app.closeChat() }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section {
                Label {
                    Text("Orbit Chat").foregroundStyle(AppTheme.primaryText)
                } icon: {
                    OrbitMark(size: 24)
                }
                .tag(SidebarItem.chat)
                Button(action: onVoice) {
                    Label {
                        Text("Live voice").foregroundStyle(AppTheme.primaryText)
                    } icon: {
                        Image(systemName: "waveform").foregroundStyle(AppTheme.coral)
                    }
                }
            }

            Section {
                row(.tab(.home), title: "Home", symbol: "house")
                row(.tab(.finance), title: "Finance", symbol: "creditcard")
                row(.tab(.health), title: "Health", symbol: "heart")
            }

            Section("Workspace") {
                row(.tab(.tasks), title: "To Do", symbol: "checklist")
                row(.tab(.jobs), title: "Jobs", symbol: "briefcase")
                row(.tab(.inbox), title: "Inbox", symbol: "tray")
            }

            Section {
                row(.page(.automations), title: "Automations", symbol: "bolt")
                row(.page(.settings), title: "Settings", symbol: "gearshape")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppTheme.primarySurface)
        .environment(\.colorScheme, .dark)
        .navigationTitle("Orbit")
        .toolbarBackground(AppTheme.primarySurface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var detail: some View {
        if app.assistantLaunch == .chat {
            NavigationStack {
                AssistantView(initialPrompt: app.assistantInitialPrompt ?? "")
            }
            // Opening Chat with a new prompt, such as from Health, starts from it.
            .id(app.assistantInitialPrompt ?? "")
        } else if let page {
            switch page {
            case .automations: AutomationsView()
            case .settings: SettingsView(showsDoneButton: false)
            }
        } else {
            switch app.selectedTab {
            case .home: HomeView()
            case .finance: FinanceView()
            case .health: HealthView()
            case .tasks: TasksView()
            case .jobs: JobsView()
            case .inbox: InboxView()
            case .more: OrbitMoreView(onOpenMoreDestination: onOpenMoreDestination)
            }
        }
    }

    /// `.more` has no row: its destinations are all listed here, so the
    /// sidebar highlights nothing while the More screen is showing.
    private var selection: Binding<SidebarItem?> {
        Binding(
            get: {
                if app.assistantLaunch == .chat { return .chat }
                if let page { return .page(page) }
                return app.selectedTab == .more ? nil : .tab(app.selectedTab)
            },
            set: { item in
                switch item {
                case .chat:
                    page = nil
                    if app.assistantLaunch != .chat { app.openAssistant() }
                case .tab(let tab):
                    app.closeChat()
                    page = nil
                    app.selectedTab = tab
                case .page(let newPage):
                    app.closeChat()
                    page = newPage
                case nil:
                    break
                }
            }
        )
    }

    private func openSettings() {
        app.closeChat()
        page = .settings
    }

    private func row(_ item: SidebarItem, title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .tag(item)
    }
}

private enum SidebarItem: Hashable {
    case chat
    case tab(AppState.Tab)
    case page(MoreSheet)
}

private struct DetailRoute: Equatable {
    var tab: AppState.Tab
    var showsChat: Bool
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
    let onChat: () -> Void
    let onVoice: () -> Void
    let onOpenMoreDestination: (MoreDestination) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Only taps on the dock tick, not programmatic tab changes like deep links.
    @State private var tabFeedback = 0
    @State private var voiceFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lets the selection indicator slide between dock items.
    @Namespace private var indicatorNamespace

    var body: some View {
        GeometryReader { proxy in
            let slotWidth = proxy.size.width / 5
            let assistantDiameter = min(46, max(40, slotWidth - 24))

            HStack(alignment: .center, spacing: 0) {
                destination(.home, title: "Home", symbol: "house", selectedSymbol: "house.fill")
                destination(.finance, title: "Finance", symbol: "creditcard", selectedSymbol: "creditcard.fill")

                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.brand.opacity(0.08))
                            .frame(width: assistantDiameter + 7, height: assistantDiameter + 7)
                            .blur(radius: 5)
                        Circle()
                            .fill(AppTheme.brandGradient)
                            .frame(width: assistantDiameter, height: assistantDiameter)
                            .overlay(Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1))
                            .shadow(color: AppTheme.brand.opacity(0.2), radius: 7, y: 3)
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Orbit")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.coral)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 47)
                .offset(y: dynamicTypeSize.isAccessibilitySize ? 0 : -4)
                .contentShape(Rectangle())
                .gesture(assistantGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Orbit Chat")
                .accessibilityHint("Tap for text chat. Press and hold for live voice")
                .accessibilityIdentifier("orbit.assistant.launcher")
                .accessibilityAction { onChat() }
                .accessibilityAction(named: "Start live voice") { onVoice() }

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
        .sensoryFeedback(.selection, trigger: tabFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: voiceFeedback)
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
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                .symbolRenderingMode(.monochrome)
                .contentTransition(.symbolEffect(.replace.downUp))
                .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(title)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(isSelected ? AppTheme.coral : AppTheme.tertiaryText)
        .frame(maxWidth: .infinity, minHeight: 47)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if isSelected {
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: 18, height: 2)
                    .matchedGeometryEffect(id: "dock-indicator", in: indicatorNamespace)
                    .offset(y: -8)
            }
        }
    }

    private func select(_ tab: AppState.Tab) {
        if !isDockSelected(tab) { tabFeedback += 1 }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.78)) {
            selection = tab
        }
    }

    private var assistantGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 24)
            .exclusively(before: TapGesture())
            .onEnded { result in
                switch result {
                case .first(let didHold):
                    if didHold {
                        voiceFeedback += 1
                        onVoice()
                    }
                case .second:
                    onChat()
                }
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
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.orbitWideLayout) private var isWide
    let onOpenMoreDestination: (MoreDestination) -> Void
    @State private var hasAppeared = false

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return Array(
            repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.md),
            count: isWide ? 4 : 2
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    OrbitPageHeading(title: "More", subtitle: "Everything else, close by.")
                    intro

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionHeader(title: "Your workspace")

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
                        SectionHeader(title: "Account")
                        settingsRow
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xxl)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
            }
            .background(AppTheme.background)
            .orbitNavigationChrome()
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
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            OrbitAvatar(name: app.user?.fullName ?? "Orbit", size: 48)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(app.user?.fullName ?? "Your workspace")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text("A little more connected.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            OrbitIconButton(title: "Account settings", symbol: "gearshape") {
                onOpenMoreDestination(.settings)
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
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .cardSurface(padding: AppTheme.Spacing.lg)
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

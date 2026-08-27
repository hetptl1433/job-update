import SwiftUI

/// Five primary destinations plus a persistent, visually distinct jump into
/// live voice. The custom bar keeps Orbit voice one tap away from every tab.
struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.selectedTab) {
            HomeView()
                .tag(AppState.Tab.home)
            TasksView()
                .tag(AppState.Tab.tasks)
            InboxView()
                .tag(AppState.Tab.inbox)
            JobsView()
                .tag(AppState.Tab.jobs)
            FinanceView()
                .tag(AppState.Tab.finance)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OrbitControlBar(
                selection: $app.selectedTab,
                onVoice: { app.assistantLaunch = .voice }
            )
        }
        .sheet(isPresented: chatPresented) {
            NavigationStack {
                AssistantView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { app.assistantLaunch = nil }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: voicePresented) {
            LiveVoiceView()
        }
    }

    private var chatPresented: Binding<Bool> {
        Binding(
            get: { app.assistantLaunch == .chat },
            set: { presented in
                if !presented, app.assistantLaunch == .chat {
                    app.assistantLaunch = nil
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
}

struct OrbitControlBar: View {
    @Binding var selection: AppState.Tab
    let onVoice: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let slotWidth = proxy.size.width / 6
            let voiceDiameter = min(43, max(36, slotWidth - 18))

            HStack(alignment: .center, spacing: 0) {
                destination(.home, title: "Home", symbol: "house", selectedSymbol: "house.fill")
                destination(.tasks, title: "To Do", symbol: "checklist", selectedSymbol: "checklist")
                destination(.inbox, title: "Inbox", symbol: "tray", selectedSymbol: "tray.fill")

                Button(action: onVoice) {
                    VStack(spacing: 3) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.coral.opacity(0.16))
                                .frame(width: voiceDiameter + 7, height: voiceDiameter + 7)
                                .blur(radius: 7)
                            Circle()
                                .fill(AppTheme.coral)
                                .frame(width: voiceDiameter, height: voiceDiameter)
                                .overlay(Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1))
                                .shadow(color: AppTheme.coral.opacity(0.32), radius: 9, y: 4)
                            Image(systemName: "waveform")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Voice")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.coral)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .offset(y: dynamicTypeSize.isAccessibilitySize ? 0 : -4)
                }
                .buttonStyle(OrbitBarButtonStyle())
                .accessibilityLabel("Open Orbit live voice")

                destination(.jobs, title: "Jobs", symbol: "briefcase", selectedSymbol: "briefcase.fill")
                destination(.finance, title: "Finance", symbol: "creditcard", selectedSymbol: "creditcard.fill")
            }
            .padding(.horizontal, 5)
            .padding(.top, 7)
            .padding(.bottom, 3)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 61 : 68)
        .background(.ultraThinMaterial)
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
        let isSelected = selection == tab
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = tab
            }
        } label: {
            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 0 : 4) {
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
            .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.tertiaryText)
            .frame(maxWidth: .infinity, minHeight: 47)
            .contentShape(Rectangle())
        }
        .buttonStyle(OrbitBarButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

import SwiftUI

/// Routes the whole app off a single source of truth: `AppState.phase`.
/// Returning authenticated users never see onboarding.
struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                LaunchView()
            case .signedOut, .authenticating:
                WelcomeView()
            case .needsSetup:
                SetupServicesView()
            case .authenticated:
                MainTabView()
            }
        }
        .tint(AppTheme.brand)
        .preferredColorScheme(appearance.colorScheme)
        .task {
            if app.phase == .launching { await app.bootstrap() }
        }
        .alert(item: $app.alert) { alert in
            if let actionTitle = alert.actionTitle, let actionURL = alert.actionURL {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text(actionTitle)) { openURL(actionURL) },
                    secondaryButton: .cancel()
                )
            }
            return Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

/// Minimal launch splash while the session is restored.
struct LaunchView: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: AppTheme.Spacing.md) {
                AppLogo(size: 44)
                ProgressView().padding(.top, AppTheme.Spacing.sm)
            }
        }
    }
}

/// Minimal monochrome orbit mark shared with the App Store icon.
struct AppLogo: View {
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color.black)
            .frame(width: size, height: size)
            .overlay {
                ZStack {
                    Ellipse()
                        .stroke(Color.white, lineWidth: max(1, size * 0.045))
                        .frame(width: size * 0.62, height: size * 0.34)
                        .rotationEffect(.degrees(-18))
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.13, height: size * 0.13)
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.075, height: size * 0.075)
                        .offset(x: -size * 0.25, y: size * 0.11)
                }
            }
    }
}

import SwiftUI

/// Routes the whole app off a single source of truth: `AppState.phase`.
/// Returning authenticated users never see onboarding.
struct RootView: View {
    @EnvironmentObject private var app: AppState

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
        .tint(AppTheme.accent)
        .task {
            if app.phase == .launching { await app.bootstrap() }
        }
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
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

/// Simple wordmark logo — a filled square with the app initial. Clean and
/// brand-neutral (no radar graphics).
struct AppLogo: View {
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(AppTheme.accent)
            .frame(width: size, height: size)
            .overlay(
                Text(String(AppConfig.appName.prefix(1)))
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.onAccent)
            )
    }
}

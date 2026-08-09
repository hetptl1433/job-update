import SwiftUI

/// First-launch welcome + Google sign-in. Deliberately minimal — no feature
/// grid, no clutter.
struct WelcomeView: View {
    @EnvironmentObject private var app: AppState

    private var isAuthenticating: Bool { app.phase == .authenticating }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: AppTheme.Spacing.xxl)

                AppLogo(size: 52)
                    .padding(.bottom, AppTheme.Spacing.xl)

                Text("Your life.\nOne place.")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Email, jobs, health, tasks and AI — organized around what needs your attention.")
                    .font(.title3)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppTheme.Spacing.md)

                Spacer()

                Button {
                    Task { await app.signInWithGoogle() }
                } label: {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if isAuthenticating {
                            ProgressView().tint(AppTheme.onAccent)
                        } else {
                            GoogleGlyph()
                            Text("Continue with Google")
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isAuthenticating)

                Text("Your data stays connected to your account and you control what the app can access.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.sm)
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
        }
    }
}

/// A restrained "G" mark for the sign-in button (no external brand asset).
struct GoogleGlyph: View {
    var body: some View {
        Text("G")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 22, height: 22)
            .background(AppTheme.onAccent, in: Circle())
    }
}

#Preview {
    WelcomeView().environmentObject(PreviewSupport.appState())
}

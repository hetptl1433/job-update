import SwiftUI

/// Connected-services setup, shown once after first Google sign-in. Permissions
/// are requested per-service and only when the user opts in — never all at once.
struct SetupServicesView: View {
    @EnvironmentObject private var app: AppState
    @State private var working: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Connect your workspace")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.primaryText)
                        Text("Grant access to the things you want \(AppConfig.appName) to watch. You can change these anytime in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    VStack(spacing: AppTheme.Spacing.md) {
                        serviceRow(
                            title: "Gmail",
                            detail: "Find important emails, recruiter responses, interviews and things requiring your attention.",
                            systemImage: "envelope",
                            connected: app.connections.gmailConnected,
                            id: "gmail"
                        ) { await app.connectGmail() }

                        serviceRow(
                            title: "Calendar",
                            detail: "See upcoming interviews, meetings and deadlines.",
                            systemImage: "calendar",
                            connected: app.connections.calendarConnected,
                            id: "calendar"
                        ) { await app.connectCalendar() }
                    }

                    Label("Read-only access to start. \(AppConfig.appName) never sends email on your behalf without asking.",
                          systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(AppTheme.Spacing.xl)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppTheme.Spacing.sm) {
                    Button("Continue") { app.completeSetup() }
                        .buttonStyle(PrimaryButtonStyle())
                    Text("You can connect these later.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .padding(.horizontal, AppTheme.Spacing.xl)
                .padding(.top, AppTheme.Spacing.sm)
                .padding(.bottom, AppTheme.Spacing.sm)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func serviceRow(
        title: String,
        detail: String,
        systemImage: String,
        connected: Bool,
        id: String,
        connect: @escaping () async -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 40, height: 40)
                .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title).font(.headline).foregroundStyle(AppTheme.primaryText)
                Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppTheme.Spacing.sm)

            if connected {
                Label("Connected", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
                    .labelStyle(.titleAndIcon)
            } else if working == id {
                ProgressView()
            } else {
                Button("Connect") {
                    working = id
                    Task { await connect(); working = nil }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .cardSurface()
    }
}

#Preview {
    SetupServicesView().environmentObject(PreviewSupport.appState())
}

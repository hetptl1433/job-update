import SwiftUI

/// Connected-services setup, shown once after first Google sign-in. Permissions
/// are requested per-service and only when the user opts in — never all at once.
struct SetupServicesView: View {
    @EnvironmentObject private var app: AppState
    @State private var working: String?
    @State private var showAIConnect = false

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
                        gmailCard

                        serviceRow(
                            title: "Outlook / Microsoft 365",
                            detail: "Add Microsoft mail without changing your main Orbit identity.",
                            systemImage: "building.2",
                            connected: app.connections.outlookConnected,
                            id: "outlook"
                        ) { await app.connectOutlookAccount() }

                        aiCard

                        serviceRow(
                            title: "Google Calendar",
                            detail: "Read upcoming events from the primary Google account.",
                            systemImage: "g.circle",
                            connected: app.connections.googleCalendarConnected,
                            id: "calendar"
                        ) { await app.connectCalendar() }

                        serviceRow(
                            title: "Apple Calendar",
                            detail: "Combine on-device calendars with Google and Outlook.",
                            systemImage: "apple.logo",
                            connected: app.connections.appleCalendarConnected,
                            id: "apple-calendar"
                        ) { await app.connectAppleCalendar() }

                        serviceRow(
                            title: "Apple Health",
                            detail: "Read steps, sleep, active energy and workouts from this iPhone.",
                            systemImage: "heart",
                            connected: app.connections.healthConnected,
                            id: "health"
                        ) { await app.connectHealth() }
                    }

                    Label("Read-only access to start. \(AppConfig.appName) never sends email on your behalf without asking.",
                          systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(AppTheme.Spacing.xl)
            }
            .sheet(isPresented: $showAIConnect) { ConnectChatGPTView().environmentObject(app) }
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

    private var gmailCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Image(systemName: "envelope")
                    .font(.title3).foregroundStyle(AppTheme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Gmail").font(.headline).foregroundStyle(AppTheme.primaryText)
                    Text("Scan the primary Gmail plus any additional read-only Gmail accounts you connect.")
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !app.gmailAccounts.isEmpty {
                VStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(app.gmailAccounts) { account in
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(AppTheme.success)
                            Text(account.email).font(.caption).foregroundStyle(AppTheme.primaryText)
                            if account.userID == app.user?.userID {
                                Text("PRIMARY").font(.caption2.weight(.bold)).foregroundStyle(AppTheme.brand)
                            }
                            Spacer()
                            Button { app.removeGmailAccount(account) } label: {
                                Image(systemName: "xmark.circle").font(.caption).foregroundStyle(AppTheme.tertiaryText)
                            }
                        }
                    }
                }
            }

            if working == "gmail" || working == "gmail-add" {
                ProgressView()
            } else {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if !app.gmailAccounts.contains(where: { $0.userID == app.user?.userID }) {
                        Button("Connect primary Gmail") {
                            working = "gmail"
                            Task { await app.connectGmailAccount(); working = nil }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Add another Gmail") {
                        working = "gmail-add"
                        Task { await app.connectAdditionalGmailAccount(); working = nil }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .cardSurface()
    }

    private var aiCard: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(AppTheme.brand)
                .frame(width: 40, height: 40)
                .background(AppTheme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("AI processing").font(.headline).foregroundStyle(AppTheme.primaryText)
                Text("Turns job-related Gmail and Outlook messages into summaries and tracker updates for you to review.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            if app.connections.aiConnected {
                Label("Ready", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
            } else {
                Button("Connect") { showAIConnect = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .cardSurface()
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

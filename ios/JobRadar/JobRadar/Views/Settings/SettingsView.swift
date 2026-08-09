import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    static let storageKey = "orbit.appearance"
}

/// Clean, native Settings / profile area.
struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("dailyBriefEnabled") private var dailyBriefEnabled = true
    @State private var adminPassword = ""
    @State private var showDisconnectConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                servicesSection
                aiSection
                notificationsSection
                appearanceSection
                serverSection
                privacySection
                aboutSection
                dangerSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { adminPassword = KeychainStore.get(KeychainKeys.adminPassword) ?? "" }
            .confirmationDialog("Disconnect account?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    Task { await app.disconnectAccount(); dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This revokes \(AppConfig.appName)'s access to your Google account and signs you out.")
            }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section("Account") {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(AppTheme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.user?.fullName.isEmpty == false ? app.user!.fullName : "Signed in")
                        .font(.headline)
                    Text(app.user?.email ?? "").font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            LabeledContent("Google", value: app.connections.googleConnected ? "Connected" : "Not connected")
        }
    }

    // MARK: Connected services

    private var servicesSection: some View {
        Section("Connected Services") {
            serviceRow("Gmail", systemImage: "envelope", connected: app.connections.gmailConnected,
                       connect: { await app.connectGmail() }, disconnect: { app.disconnectGmail() })
            serviceRow("Calendar", systemImage: "calendar", connected: app.connections.calendarConnected,
                       connect: { await app.connectCalendar() }, disconnect: { app.disconnectCalendar() })
            serviceRow("Apple Health", systemImage: "heart", connected: app.connections.healthConnected,
                       connect: { app.connectHealth() }, disconnect: {})
        }
    }

    private func serviceRow(_ title: String, systemImage: String, connected: Bool,
                            connect: @escaping () async -> Void, disconnect: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: systemImage).foregroundStyle(AppTheme.primaryText)
            Spacer()
            if connected {
                Menu {
                    Button("Disconnect", role: .destructive, action: disconnect)
                } label: {
                    Text("Connected").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.success)
                }
            } else {
                Button("Connect") { Task { await connect() } }
                    .font(.caption.weight(.semibold))
            }
        }
    }

    // MARK: AI

    private var aiSection: some View {
        Section("AI") {
            LabeledContent("Assistant", value: "Backend-brokered")
            Text("The AI service runs on \(AppConfig.appName)'s backend. Your OpenAI key never lives on this device.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Morning brief", isOn: $dailyBriefEnabled)
                .tint(AppTheme.accent)
                .onChange(of: dailyBriefEnabled) { _, enabled in
                    Task {
                        if enabled { await app.notifications.scheduleDailyDigest(hour: 6) }
                        else { app.notifications.cancelDailyDigest() }
                    }
                }
            Button("Enable notifications") { Task { await app.notifications.requestAuthorization() } }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Server access (existing tracker backend)

    private var serverSection: some View {
        Section("Server access") {
            SecureField("Backend admin password", text: $adminPassword)
            Button("Save to Keychain") {
                KeychainStore.set(adminPassword, for: KeychainKeys.adminPassword)
                app.alert = AppAlert(message: "Saved securely on this device.")
            }
            Text("Used to sync your job tracker with the backend. Stored only in the iOS Keychain.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section("Privacy & Data") {
            Label("Tokens are stored in the Keychain, never in plain storage.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            Label("Only the Google scopes you approve are requested.", systemImage: "hand.raised")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: AppConfig.appName)
            LabeledContent("Minimum iOS", value: AppConfig.minimumOS)
        }
    }

    // MARK: Danger zone

    private var dangerSection: some View {
        Section {
            Button("Sign Out") { app.signOut(); dismiss() }
            Button("Disconnect Account", role: .destructive) { showDisconnectConfirm = true }
        }
    }
}

#Preview {
    SettingsView().environmentObject(PreviewSupport.appState())
}

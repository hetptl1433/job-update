import AppIntents
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
    @State private var showChatGPTSheet = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                emailSection
                servicesSection
                aiSection
                siriSection
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
            .sheet(isPresented: $showChatGPTSheet) { ConnectChatGPTView().environmentObject(app) }
            .onAppear {
                adminPassword = KeychainStore.get(KeychainKeys.adminPassword) ?? ""
            }
            .confirmationDialog("Disconnect account?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    Task { await app.disconnectAccount(); dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes connected accounts and local credentials from this iPhone, then signs you out of \(AppConfig.appName).")
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
            LabeledContent("Signed in with", value: "Google")
        }
    }

    // MARK: Email accounts

    private var emailSection: some View {
        Section("Email Accounts") {
            ForEach(app.emailAccounts) { account in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(account.email, systemImage: account.provider.systemImage).foregroundStyle(AppTheme.primaryText)
                        .font(.subheadline)
                        Text(account.isPrimaryIdentity ? "Primary identity · \(account.provider.label)" : account.provider.label)
                            .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        if account.provider == .gmail { app.removeGmailAccount(account) }
                        else { app.removeOutlookAccount(account) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                }
            }
            if !app.gmailAccounts.contains(where: { $0.userID == app.user?.userID }) {
                Button { Task { await app.connectGmailAccount() } } label: {
                    Label("Connect primary Gmail", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            Button { Task { await app.connectAdditionalGmailAccount() } } label: {
                Label("Add another Gmail", systemImage: "person.crop.circle.badge.plus")
            }
            Button { Task { await app.connectOutlookAccount() } } label: {
                Label("Add Outlook / Microsoft 365", systemImage: "building.2")
            }
            Text("Orbit scans every connected inbox through one read-only pipeline. Adding Gmail or Outlook never changes your main Orbit identity.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            if AppConfig.microsoftClientID == nil {
                Label("Outlook setup requires a Microsoft Entra public-client ID in project.yml.", systemImage: "wrench.and.screwdriver")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    // MARK: Connected services

    private var servicesSection: some View {
        Section("Connected Services") {
            HStack {
                Label("Banks & credit cards", systemImage: "creditcard").foregroundStyle(AppTheme.primaryText)
                Spacer()
                Button(financeStatusTitle) {
                    app.selectedTab = .finance
                    dismiss()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(app.finance.isConnected ? AppTheme.success : AppTheme.primaryText)
            }
            Text("Connect multiple institutions through Plaid, then view balances, card debt, inflow and outflow in Finance.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            serviceRow("Google Calendar", systemImage: "g.circle", connected: app.connections.googleCalendarConnected,
                       connect: { await app.connectCalendar() }, disconnect: { app.disconnectCalendarProvider(.google) })
            serviceRow("Apple Calendar", systemImage: "apple.logo", connected: app.connections.appleCalendarConnected,
                       connect: { await app.connectAppleCalendar() }, disconnect: { app.disconnectCalendarProvider(.apple) })
            serviceRow("Outlook Calendar", systemImage: "building.2", connected: app.connections.outlookCalendarConnected,
                       connect: { await app.connectOutlookCalendar() }, disconnect: { app.disconnectCalendarProvider(.outlook) })
            Text("Untimed To Dos stay local. Timed To Dos and reminders create linked Apple Calendar events and sync edits both ways. Any provider event can also be added to To Do manually.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            serviceRow("Apple Health", systemImage: "heart", connected: app.connections.healthConnected,
                       connect: { await app.connectHealth() }, disconnect: { app.disconnectHealth() })
            Text("On your iPhone, approve the Health categories you want Orbit to read. Orbit never writes health data.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var financeStatusTitle: String {
        if app.finance.isConnected { return "Connected" }
        return app.finance.isBackendConfigured ? "Connect" : "Setup needed"
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
            HStack {
                Label("OpenAI processing", systemImage: "sparkles").foregroundStyle(AppTheme.primaryText)
                Spacer()
                if app.connections.aiConnected {
                    Menu {
                        Button("Reconnect") { showChatGPTSheet = true }
                        Button("Disconnect", role: .destructive) { app.disconnectChatGPT() }
                    } label: {
                        Text("Connected").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.success)
                    }
                } else {
                    Button("Connect") { showChatGPTSheet = true }
                        .font(.caption.weight(.semibold))
                }
            }
            Text("Personal development mode. The key is validated, stored in Keychain, and never logged. Use a backend-held key before distributing the app.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: Siri and widgets

    private var siriSection: some View {
        Section("Siri & Widgets") {
            ShortcutsLink()
            Text("Say “Siri, set a task in Orbit,” then answer “washing at 5 PM.” Orbit extracts the time, uses Alarm by default, and syncs the timed To Do to Apple Calendar when Calendar sync is enabled.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            Label("Add Orbit Today and Orbit Reminders from the iPhone widget gallery. Both support quick add and completion.", systemImage: "rectangle.3.group")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Morning brief", isOn: $dailyBriefEnabled)
                .tint(AppTheme.brand)
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
            if app.api.isConfigured {
                LabeledContent("Tracker URL", value: app.api.baseURL?.host ?? "Configured")
                SecureField("Backend admin password", text: $adminPassword)
                Button("Save to Keychain") {
                    KeychainStore.set(adminPassword, for: KeychainKeys.adminPassword)
                    app.alert = AppAlert(message: "Saved securely on this device.")
                }
                Text("Used only for optional remote tracker sync. Stored in the iOS Keychain.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            } else {
                Label("Local-only tracker", systemImage: "iphone")
                Text("Jobs are saved on this iPhone. Add a valid APIBaseURL in project.yml only when your tracker backend is deployed.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section("Privacy & Data") {
            Label("Tokens are stored in the Keychain, never in plain storage.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            Label("Only the Google scopes you approve are requested.", systemImage: "hand.raised")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            Label("Bank credentials stay in Plaid Hosted Link. Plaid secrets and access tokens stay on Orbit's backend.", systemImage: "building.columns")
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

/// Sheet for connecting ChatGPT by pasting an OpenAI API key. The key is stored
/// only in the Keychain.
struct ConnectChatGPTView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.destructive)
                    }
                } header: {
                    Text("OpenAI API key")
                } footer: {
                    Text("Create a key at platform.openai.com → API keys. API usage is billed separately from ChatGPT Plus. Orbit validates the key before saving it.")
                }

                Section {
                    Label("For personal development only. A production mobile app must route OpenAI requests through a secure backend.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle("Connect ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let candidate = key
                        isConnecting = true
                        errorMessage = nil
                        Task {
                            do {
                                try await app.connectChatGPT(apiKey: candidate)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                isConnecting = false
                            }
                        }
                    } label: {
                        if isConnecting { ProgressView() } else { Text("Connect") }
                    }
                    .fontWeight(.semibold)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                }
            }
            .interactiveDismissDisabled(isConnecting)
        }
    }
}

#Preview {
    SettingsView().environmentObject(PreviewSupport.appState())
}

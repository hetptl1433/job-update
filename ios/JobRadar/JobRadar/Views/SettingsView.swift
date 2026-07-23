import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query private var applications: [JobApplication]
    @AppStorage("dailyDigestEnabled") private var dailyDigestEnabled = true
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Automation") {
                    Toggle("6:00 AM daily digest", isOn: $dailyDigestEnabled)
                        .onChange(of: dailyDigestEnabled) { _, enabled in if enabled { Task { await session.notifications.scheduleDailyDigest(hour: 6) } } }
                    Button("Refresh now") { Task { _ = await session.refresh(using: context) } }
                    Button("Save tracker online") { Task { await session.saveAll(applications) } }
                }
                Section("Secure server access") {
                    SecureField("Admin password", text: $password)
                    Button("Store in Keychain") { do { try session.setAdminPassword(password); session.alertMessage = "Password stored securely on this iPhone." } catch { session.alertMessage = error.localizedDescription } }
                }
                Section("Notifications") {
                    Button("Enable notifications") { Task { await session.notifications.requestAuthorization() } }
                    Text("Application follow-ups are scheduled locally. New-email alerts require APNs to be configured on the backend.").font(.caption).foregroundStyle(.secondary)
                }
                Section("About") {
                    LabeledContent("App", value: "Job Radar")
                    LabeledContent("Owner", value: "Het Patel")
                    LabeledContent("Minimum iOS", value: "17.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear { password = session.adminPassword() }
        }
    }
}

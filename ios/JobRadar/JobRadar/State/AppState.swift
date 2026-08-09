import Foundation
import SwiftData
import SwiftUI

/// Connection status for each external service the app can integrate with.
struct ConnectionStatus: Equatable {
    var googleConnected = false
    var gmailConnected = false
    var calendarConnected = false
    var healthConnected = false
    var aiConnected = false
}

/// A user-facing alert message.
struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String

    init(title: String = AppConfig.appName, message: String) {
        self.title = title
        self.message = message
    }

    init(_ error: Error) {
        self.title = "Something went wrong"
        self.message = error.localizedDescription
    }
}

/// The single coherent source of application + session state. The root view
/// routes purely off `phase`; individual screens read the service objects.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case launching
        case signedOut
        case authenticating
        case needsSetup
        case authenticated
    }

    @Published private(set) var phase: Phase = .launching
    /// The single signed-in identity (one email).
    @Published private(set) var user: UserSession?
    /// Connected Gmail mailboxes (data sources). Can be several.
    @Published private(set) var gmailAccounts: [GmailAccount] = []
    @Published private(set) var connections = ConnectionStatus()
    @Published var alert: AppAlert?

    // Service layer
    let auth: AuthenticationManager
    let api: APIClient
    let jobs: JobRepository
    let inbox: GmailRepository
    let assistant: AssistantService
    let health: HealthRepository
    let automations: AutomationService
    let notifications = NotificationManager.shared

    private enum Keys {
        static let setupComplete = "orbit.setupComplete"
        static let calendar = "orbit.conn.calendar"
        static let health = "orbit.conn.health"
        static let gmailAccounts = "orbit.gmailAccounts"
    }

    init(modelContext: ModelContext) {
        let api = APIClient()
        self.api = api
        self.auth = AuthenticationManager()
        self.jobs = JobRepository(api: api, context: modelContext)
        self.inbox = GmailRepository(api: api)
        self.assistant = LiveAssistantService(api: api)
        self.health = HealthRepository()
        self.automations = AutomationService()
    }

    // MARK: Launch

    func bootstrap() async {
        loadPersistedState()
        if let session = await auth.restoreSession() {
            apply(session)
            phase = isSetupComplete ? .authenticated : .needsSetup
        } else {
            phase = .signedOut
        }
    }

    // MARK: Authentication (single identity)

    func signInWithGoogle() async {
        phase = .authenticating
        do {
            let session = try await auth.signIn()
            apply(session)
            phase = .needsSetup
        } catch AuthError.cancelled {
            phase = .signedOut
        } catch {
            alert = AppAlert(error)
            phase = .signedOut
        }
    }

    func signOut() {
        auth.signOut()
        resetSignedOut(clearSetup: false)
    }

    func disconnectAccount() async {
        await auth.disconnect()
        resetSignedOut(clearSetup: true)
    }

    // MARK: Gmail mailboxes (multiple)

    /// Link a Gmail mailbox as a data source. Prompts Google's account chooser,
    /// then records that mailbox. Several mailboxes can be connected.
    func connectGmailAccount() async {
        do {
            let session = try await auth.requestScopes([GoogleScopes.gmailReadonly])
            addGmailAccount(email: session.email, fullName: session.fullName)
        } catch AuthError.cancelled {
        } catch {
            alert = AppAlert(error)
        }
    }

    private func addGmailAccount(email: String, fullName: String) {
        guard !email.isEmpty else { return }
        if !gmailAccounts.contains(where: { $0.email == email }) {
            gmailAccounts.append(GmailAccount(email: email, fullName: fullName))
        }
        persistGmailAccounts()
        connections.gmailConnected = !gmailAccounts.isEmpty
        inbox.markConnected(connections.gmailConnected)
    }

    func removeGmailAccount(_ account: GmailAccount) {
        gmailAccounts.removeAll { $0.email == account.email }
        persistGmailAccounts()
        connections.gmailConnected = !gmailAccounts.isEmpty
        inbox.markConnected(connections.gmailConnected)
    }

    // MARK: Calendar

    func connectCalendar() async {
        do {
            _ = try await auth.requestScopes([GoogleScopes.calendarReadonly])
            connections.calendarConnected = true
            UserDefaults.standard.set(true, forKey: Keys.calendar)
        } catch AuthError.cancelled {
        } catch {
            alert = AppAlert(error)
        }
    }

    func disconnectCalendar() {
        connections.calendarConnected = false
        UserDefaults.standard.set(false, forKey: Keys.calendar)
    }

    // MARK: Apple Health

    /// Request HealthKit authorization and load the summary. Permissions are
    /// requested only here, when the user explicitly connects Health.
    func connectHealth() async {
        let connected = await health.connect()
        connections.healthConnected = connected
        UserDefaults.standard.set(connected, forKey: Keys.health)
        if !connected, case .failed(let message) = health.state {
            alert = AppAlert(title: "Apple Health", message: message)
        }
    }

    func disconnectHealth() {
        connections.healthConnected = false
        UserDefaults.standard.set(false, forKey: Keys.health)
        health.disconnect()
    }

    // MARK: ChatGPT (user-supplied OpenAI key)

    var isChatGPTConnected: Bool {
        !(KeychainStore.get(KeychainKeys.openAIKey) ?? "").isEmpty
    }

    func connectChatGPT(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.set(trimmed, for: KeychainKeys.openAIKey)
        connections.aiConnected = true
    }

    func disconnectChatGPT() {
        KeychainStore.remove(KeychainKeys.openAIKey)
        connections.aiConnected = false
    }

    // MARK: Setup completion

    var isSetupComplete: Bool { UserDefaults.standard.bool(forKey: Keys.setupComplete) }

    func completeSetup() {
        UserDefaults.standard.set(true, forKey: Keys.setupComplete)
        phase = .authenticated
    }

    // MARK: Background refresh

    func backgroundRefresh() async -> Bool {
        await jobs.refresh()
    }

    // MARK: Helpers

    private func apply(_ session: UserSession) {
        user = session
        connections.googleConnected = true
        // If the login identity granted Gmail/Calendar during auth, reflect it.
        if session.grantedScopes.contains(GoogleScopes.gmailReadonly) {
            addGmailAccount(email: session.email, fullName: session.fullName)
        }
        if session.grantedScopes.contains(GoogleScopes.calendarReadonly) {
            connections.calendarConnected = true
        }
        connections.aiConnected = isChatGPTConnected
        inbox.markConnected(connections.gmailConnected)
    }

    private func loadPersistedState() {
        let defaults = UserDefaults.standard
        connections.calendarConnected = defaults.bool(forKey: Keys.calendar)
        connections.healthConnected = defaults.bool(forKey: Keys.health)
        connections.aiConnected = isChatGPTConnected
        if let data = defaults.data(forKey: Keys.gmailAccounts),
           let decoded = try? JSONDecoder().decode([GmailAccount].self, from: data) {
            gmailAccounts = decoded
        }
        connections.gmailConnected = !gmailAccounts.isEmpty
        inbox.markConnected(connections.gmailConnected)
    }

    private func persistGmailAccounts() {
        if let data = try? JSONEncoder().encode(gmailAccounts) {
            UserDefaults.standard.set(data, forKey: Keys.gmailAccounts)
        }
    }

    private func resetSignedOut(clearSetup: Bool) {
        user = nil
        gmailAccounts = []
        connections = ConnectionStatus()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: Keys.calendar)
        defaults.set(false, forKey: Keys.health)
        defaults.removeObject(forKey: Keys.gmailAccounts)
        if clearSetup { defaults.set(false, forKey: Keys.setupComplete) }
        inbox.markConnected(false)
        health.disconnect()
        phase = .signedOut
    }
}

import Foundation
import SwiftData
import SwiftUI

/// Connection status for each external service the app can integrate with.
struct ConnectionStatus: Equatable {
    var googleConnected = false
    var gmailConnected = false
    var outlookConnected = false
    var calendarConnected = false
    var appleCalendarConnected = false
    var googleCalendarConnected = false
    var outlookCalendarConnected = false
    var healthConnected = false
    var aiConnected = false

    var emailConnected: Bool { gmailConnected || outlookConnected }
}

/// A user-facing alert message.
struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var actionTitle: String?
    var actionURL: URL?

    init(
        title: String = AppConfig.appName,
        message: String,
        actionTitle: String? = nil,
        actionURL: URL? = nil
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionURL = actionURL
    }

    init(_ error: Error) {
        self.title = "Something went wrong"
        self.message = error.localizedDescription
        self.actionTitle = nil
        self.actionURL = nil
    }
}

/// The single coherent source of application + session state. The root view
/// routes purely off `phase`; individual screens read the service objects.
@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable { case home, tasks, inbox, jobs, finance }
    enum Phase: Equatable {
        case launching
        case signedOut
        case authenticating
        case needsSetup
        case authenticated
    }

    @Published private(set) var phase: Phase = .launching
    @Published var selectedTab: Tab = .home
    @Published var financePath: [FinanceRoute] = []
    @Published var voiceAssistantRequested = false
    /// The single signed-in identity (one email).
    @Published private(set) var user: UserSession?
    /// Connected mailboxes. `user` remains the one primary Orbit identity while
    /// any number of Gmail and Microsoft mail sources can be authorized.
    @Published private(set) var emailAccounts: [EmailAccount] = []
    var gmailAccounts: [EmailAccount] { emailAccounts.filter { $0.provider == .gmail } }
    var outlookAccounts: [EmailAccount] { emailAccounts.filter { $0.provider == .outlook } }
    @Published private(set) var connections = ConnectionStatus()
    @Published var alert: AppAlert?

    // Email → AI → dashboard pipeline
    @Published private(set) var detectedJobUpdates: [DetectedJobUpdate] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var syncStageMessage: String?
    @Published private(set) var lastSyncSummary: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var calendarState: LoadState<[CalendarEvent]> = .disconnected

    // Service layer
    let auth: AuthenticationManager
    let api: APIClient
    let jobs: JobRepository
    let inbox: EmailRepository
    let tasks: TaskRepository
    let reminders: ReminderRepository
    let calendar: CalendarRepository
    let finance: FinanceRepository
    let assistant: AssistantService
    let health: HealthRepository
    let automations: AutomationService
    let notifications = NotificationManager.shared
    private let gmailAPI = GmailAPIClient()
    private let calendarAPI = GoogleCalendarAPIClient()
    private let outlookMailAPI = OutlookMailService()
    private let appleCalendarAPI = AppleCalendarService()
    private let microsoftAuth = MicrosoftAuthService()

    private enum Keys {
        static let setupComplete = "orbit.setupComplete"
        static let calendar = "orbit.conn.calendar"
        static let health = "orbit.conn.health"
        static let gmailAccounts = "orbit.gmailAccounts"
        static let emailAccounts = "orbit.emailAccounts.v2"
        static let calendarProviders = "orbit.calendarProviders.v2"
        static let gmailDisabled = "orbit.conn.gmailDisabled"
    }

    init(modelContext: ModelContext) {
        let api = APIClient()
        let financeAPI = APIClient(baseURL: AppConfig.financeAPIBaseURL)
        let auth = AuthenticationManager()
        self.api = api
        self.auth = auth
        self.jobs = JobRepository(api: api, context: modelContext)
        self.inbox = EmailRepository()
        self.tasks = TaskRepository()
        self.reminders = ReminderRepository()
        self.calendar = CalendarRepository()
        self.finance = FinanceRepository(api: financeAPI, auth: auth)
        self.assistant = LiveAssistantService()
        self.health = HealthRepository()
        self.automations = AutomationService()
    }

    // MARK: Launch

    func bootstrap() async {
        loadPersistedState()
        if let session = await auth.restoreSession() {
            apply(session)
            phase = isSetupComplete ? .authenticated : .needsSetup
            if connections.calendarConnected { await refreshCalendar(presentErrors: false) }
            if connections.healthConnected { await health.refresh() }
        } else {
            phase = .signedOut
        }
    }

    // MARK: Authentication (single identity)

    func signInWithGoogle() async {
        phase = .authenticating
        do {
            // Gmail is the core data source, so request its read-only scope in
            // the initial Google flow instead of forcing a second OAuth prompt.
            let session = try await auth.signIn(requiredScopes: [GoogleScopes.gmailReadonly])
            UserDefaults.standard.set(false, forKey: Keys.gmailDisabled)
            apply(session)
            phase = isSetupComplete ? .authenticated : .needsSetup
        } catch AuthError.cancelled {
            phase = .signedOut
        } catch {
            alert = AppAlert(error)
            phase = .signedOut
        }
    }

    func signOut() {
        gmailAccounts.forEach { auth.forgetGoogleAccount($0.userID) }
        outlookAccounts.forEach { microsoftAuth.removeAccount($0.providerAccountID) }
        if let user { auth.forgetGoogleAccount(user.userID) }
        auth.signOut()
        resetSignedOut(clearSetup: false)
    }

    func disconnectAccount() async {
        gmailAccounts.forEach { auth.forgetGoogleAccount($0.userID) }
        outlookAccounts.forEach { microsoftAuth.removeAccount($0.providerAccountID) }
        if let user { auth.forgetGoogleAccount(user.userID) }
        await auth.disconnect()
        resetSignedOut(clearSetup: true)
    }

    // MARK: Gmail

    /// Connect the signed-in Google identity as the Gmail data source.
    func connectGmailAccount() async {
        do {
            let session = try await auth.requestScopes([GoogleScopes.gmailReadonly])
            user = session
            UserDefaults.standard.set(false, forKey: Keys.gmailDisabled)
            addGmailAccount(userID: session.userID, email: session.email, fullName: session.fullName)
        } catch AuthError.cancelled {
        } catch {
            alert = AppAlert(error)
        }
    }

    /// Opens Google's account chooser and links another mailbox without
    /// changing the primary Orbit profile.
    func connectAdditionalGmailAccount() async {
        do {
            let account = try await auth.connectAdditionalGmail()
            let alreadyConnected = gmailAccounts.contains { $0.userID == account.userID || $0.email.caseInsensitiveCompare(account.email) == .orderedSame }
            addGmailAccount(userID: account.userID, email: account.email, fullName: account.fullName)
            if alreadyConnected {
                alert = AppAlert(title: "Gmail already connected", message: "\(account.email) is already one of your Gmail sources.")
            }
        } catch AuthError.cancelled {
        } catch {
            alert = AppAlert(error)
        }
    }

    private func addGmailAccount(userID: String, email: String, fullName: String) {
        guard !email.isEmpty else { return }
        let account = EmailAccount(
            provider: .gmail,
            providerAccountID: userID,
            email: email,
            displayName: fullName,
            isPrimaryIdentity: userID == user?.userID
        )
        if let index = emailAccounts.firstIndex(where: {
            $0.provider == .gmail && ($0.userID == userID || $0.email.caseInsensitiveCompare(email) == .orderedSame)
        }) {
            emailAccounts[index] = account
        } else {
            emailAccounts.append(account)
        }
        persistEmailAccounts()
        updateEmailConnectionState()
    }

    func removeGmailAccount(_ account: EmailAccount) {
        emailAccounts.removeAll { $0.provider == .gmail && $0.userID == account.userID }
        if account.userID == user?.userID {
            // The Google identity remains signed in; only Gmail reading is off.
            UserDefaults.standard.set(true, forKey: Keys.gmailDisabled)
        } else {
            auth.forgetGoogleAccount(account.userID)
        }
        persistEmailAccounts()
        updateEmailConnectionState()
    }

    // MARK: Outlook / Microsoft 365

    func connectOutlookAccount() async {
        do {
            let account = try await microsoftAuth.connectAccount()
            let duplicate = emailAccounts.contains { $0.provider == .outlook && $0.providerAccountID == account.providerAccountID }
            if let index = emailAccounts.firstIndex(where: { $0.provider == .outlook && $0.providerAccountID == account.providerAccountID }) {
                emailAccounts[index] = account
            } else {
                emailAccounts.append(account)
            }
            persistEmailAccounts()
            updateEmailConnectionState()
            if duplicate {
                alert = AppAlert(title: "Outlook already connected", message: "\(account.email) is already one of your email sources.")
            }
        } catch MicrosoftAuthError.cancelled {
        } catch {
            alert = AppAlert(title: "Connect Outlook", message: error.localizedDescription)
        }
    }

    func removeOutlookAccount(_ account: EmailAccount) {
        microsoftAuth.removeAccount(account.providerAccountID)
        emailAccounts.removeAll { $0.provider == .outlook && $0.providerAccountID == account.providerAccountID }
        persistEmailAccounts()
        updateEmailConnectionState()
        if outlookAccounts.isEmpty { disconnectCalendarProvider(.outlook) }
    }

    // MARK: Calendar

    func connectCalendar() async {
        do {
            let session = try await auth.requestScopes([GoogleScopes.calendarReadonly])
            user = session
            calendar.setConnected(.google, true)
            persistCalendarProviders()
            updateCalendarConnectionState()
            await refreshCalendar()
        } catch AuthError.cancelled {
        } catch let error as GoogleCalendarAPIError {
            calendarState = .failed(error.localizedDescription)
            alert = AppAlert(
                title: "Enable Google Calendar API",
                message: error.localizedDescription,
                actionTitle: "Open Google Cloud",
                actionURL: error.recoveryURL
            )
        } catch {
            alert = AppAlert(error)
        }
    }

    func connectAppleCalendar() async {
        do {
            try await appleCalendarAPI.requestAccess()
            calendar.setConnected(.apple, true)
            tasks.setAppleCalendarSyncEnabled(true)
            reminders.setAppleCalendarSyncEnabled(true)
            persistCalendarProviders()
            updateCalendarConnectionState()
            await refreshCalendar()
        } catch {
            alert = AppAlert(title: "Connect Apple Calendar", message: error.localizedDescription)
        }
    }

    func connectOutlookCalendar() async {
        if outlookAccounts.isEmpty { await connectOutlookAccount() }
        guard !outlookAccounts.isEmpty else { return }
        calendar.setConnected(.outlook, true)
        persistCalendarProviders()
        updateCalendarConnectionState()
        await refreshCalendar()
    }

    func refreshCalendar(presentErrors: Bool = true) async {
        let providers = calendar.connectedProviders
        guard !providers.isEmpty else {
            calendarState = .disconnected
            return
        }
        let previousState: LoadState<[CalendarEvent]>
        if case .failed = calendarState { previousState = .empty }
        else { previousState = calendarState }
        if presentErrors {
            calendar.beginLoading()
            calendarState = .loading
        }
        var succeeded = 0
        var failures: [String] = []

        if providers.contains(.apple) {
            do {
                _ = try await appleCalendarAPI.upcomingEvents()
                tasks.reconcileWithAppleCalendar()
                reminders.reconcileWithAppleCalendar()
                calendar.setEvents(try await appleCalendarAPI.upcomingEvents(), for: .apple)
                succeeded += 1
            } catch { failures.append("Apple Calendar: \(error.localizedDescription)") }
        }

        if providers.contains(.google) {
            do {
                guard let primary = user ?? UserSession.restore(),
                      let token = await auth.googleAccessToken(for: primary.userID) else {
                    throw APIError.server(status: 401, message: "Reconnect Google Calendar.")
                }
                calendar.setEvents(try await calendarAPI.upcomingEvents(token: token), for: .google)
                succeeded += 1
            } catch let error as GoogleCalendarAPIError {
                failures.append("Google Calendar: \(error.localizedDescription)")
                if presentErrors {
                    alert = AppAlert(
                        title: "Enable Google Calendar API",
                        message: error.localizedDescription,
                        actionTitle: "Open Google Cloud",
                        actionURL: error.recoveryURL
                    )
                }
            } catch { failures.append("Google Calendar: \(error.localizedDescription)") }
        }

        if providers.contains(.outlook) {
            var outlookEvents: [UnifiedCalendarEvent] = []
            var outlookSucceeded = false
            for account in outlookAccounts {
                guard let token = await microsoftAuth.accessToken(
                    for: account.providerAccountID,
                    scopes: MicrosoftAuthService.calendarScopes
                ) else {
                    failures.append("\(account.email) calendar: reconnect required")
                    continue
                }
                do {
                    outlookEvents += try await OutlookCalendarService(account: account).upcomingEvents(token: token)
                    outlookSucceeded = true
                } catch { failures.append("\(account.email) calendar: \(error.localizedDescription)") }
            }
            if outlookSucceeded {
                calendar.setEvents(outlookEvents.sorted { $0.start < $1.start }, for: .outlook)
                succeeded += 1
            }
        }

        if succeeded == 0 {
            calendarState = presentErrors
                ? .failed(failures.first ?? "Calendar refresh failed.")
                : previousState
        } else {
            calendarState = calendar.state
            if let events = calendarState.value { tasks.mergeLinkedCalendarEvents(events) }
            if presentErrors, !failures.isEmpty, alert == nil {
                alert = AppAlert(title: "Some calendars need attention", message: failures.joined(separator: "\n"))
            }
        }
    }

    func disconnectCalendar() {
        calendar.disconnectAll()
        tasks.setAppleCalendarSyncEnabled(false)
        reminders.setAppleCalendarSyncEnabled(false)
        persistCalendarProviders()
        updateCalendarConnectionState()
        calendarState = .disconnected
    }

    func disconnectCalendarProvider(_ provider: CalendarProviderType) {
        calendar.setConnected(provider, false)
        if provider == .apple {
            tasks.setAppleCalendarSyncEnabled(false)
            reminders.setAppleCalendarSyncEnabled(false)
        }
        persistCalendarProviders()
        updateCalendarConnectionState()
        calendarState = calendar.state
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

    // MARK: OpenAI processing (personal-development credential)

    var isChatGPTConnected: Bool {
        !(KeychainStore.get(KeychainKeys.openAIKey) ?? "").isEmpty
    }

    func connectChatGPT(apiKey: String) async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.notConfigured("Enter an OpenAI API key.")
        }
        try await OpenAIClient(apiKey: trimmed).validateCredential()
        guard KeychainStore.set(trimmed, for: KeychainKeys.openAIKey) else {
            throw APIError.notConfigured("The key could not be saved to the iOS Keychain.")
        }
        connections.aiConnected = true
    }

    func disconnectChatGPT() {
        KeychainStore.remove(KeychainKeys.openAIKey)
        connections.aiConnected = false
    }

    // MARK: Email → AI → dashboard pipeline

    /// Pull recent mail from every provider, let OpenAI process it, and surface results:
    /// classified inbox + proposed job updates the user can accept.
    func syncEmail(presentErrors: Bool = true) async {
        guard !isSyncing else { return }
        guard connections.emailConnected else {
            if presentErrors {
                alert = AppAlert(title: "Connect email", message: "Connect Gmail or Outlook first so Orbit can find job updates.")
            }
            return
        }
        guard let key = KeychainStore.get(KeychainKeys.openAIKey), !key.isEmpty else {
            if presentErrors {
                alert = AppAlert(title: "Connect AI processing", message: "Connect an OpenAI API key in Settings so Orbit can turn email into job updates.")
            }
            return
        }

        let isInitialLoad = inbox.needsInitialLoad
        isSyncing = true
        syncStageMessage = "Finding job-related email…"
        if presentErrors || isInitialLoad { inbox.beginLoading() }
        defer {
            isSyncing = false
            syncStageMessage = nil
        }
        do {
            let query = "newer_than:60d -category:promotions -category:social {application applied recruiter hiring interview assessment \"next steps\" offer position candidate \"not moving forward\" \"thank you for your interest\"}"
            var important: [InboxMessage] = []
            var updates: [DetectedJobUpdate] = []
            var scannedCount = 0
            var successfulMailboxes = 0
            var failures: [String] = []

            for (index, account) in emailAccounts.enumerated() {
                syncStageMessage = "Scanning \(index + 1) of \(emailAccounts.count): \(account.email)…"
                let token: String?
                switch account.provider {
                case .gmail:
                    token = await auth.googleAccessToken(for: account.userID)
                case .outlook:
                    token = await microsoftAuth.accessToken(
                        for: account.providerAccountID,
                        scopes: MicrosoftAuthService.mailScopes
                    )
                }
                guard let token else {
                    failures.append("\(account.email): reconnect required")
                    continue
                }

                let emails: [EmailMessage]
                do {
                    switch account.provider {
                    case .gmail:
                        emails = try await gmailAPI.recentMessages(
                            query: query, maxResults: 40, token: token, account: account
                        )
                    case .outlook:
                        emails = try await outlookMailAPI.recentMessages(
                            account: account, maxResults: 40, token: token
                        )
                    }
                } catch let configuration as GmailAPIError {
                    throw configuration
                } catch {
                    failures.append("\(account.email): \(error.localizedDescription)")
                    continue
                }

                successfulMailboxes += 1
                scannedCount += emails.count
                guard !emails.isEmpty else { continue }
                syncStageMessage = "Analyzing job email from \(account.email)…"
                let output = try await EmailIntelligence(apiKey: key).analyze(emails)
                important.append(contentsOf: output.inbox)
                updates.append(contentsOf: output.jobUpdates)
            }

            guard successfulMailboxes > 0 else {
                throw APIError.server(status: 401, message: failures.first ?? "Reconnect your email accounts and try again.")
            }

            guard scannedCount > 0 else {
                inbox.setMessages([])
                detectedJobUpdates = []
                lastSyncedAt = .now
                lastSyncSummary = "No matching job email across \(successfulMailboxes) inbox\(successfulMailboxes == 1 ? "" : "es")"
                if presentErrors, !failures.isEmpty {
                    alert = AppAlert(title: "Some email accounts need attention", message: failures.joined(separator: "\n"))
                }
                return
            }

            important.sort { $0.receivedAt > $1.receivedAt }
            inbox.setMessages(important)
            detectedJobUpdates = updates
            tasks.propose(from: important, updates: updates)
            lastSyncedAt = .now
            let jobsN = updates.count
            let mailN = important.count
            lastSyncSummary = "\(scannedCount) scanned from \(successfulMailboxes) inbox\(successfulMailboxes == 1 ? "" : "es") · \(jobsN) job update\(jobsN == 1 ? "" : "s") · \(mailN) important"
            if presentErrors, !failures.isEmpty {
                alert = AppAlert(title: "Scan completed with skipped accounts", message: failures.joined(separator: "\n"))
            }
        } catch let error as GmailAPIError {
            if presentErrors {
                inbox.setFailure(error.localizedDescription)
                alert = AppAlert(
                    title: "Enable Gmail API",
                    message: error.localizedDescription,
                    actionTitle: "Open Google Cloud",
                    actionURL: error.recoveryURL
                )
            } else if isInitialLoad {
                inbox.setFailure(error.localizedDescription)
            }
        } catch {
            if presentErrors {
                inbox.setFailure(error.localizedDescription)
                alert = AppAlert(title: "Sync failed", message: error.localizedDescription)
            } else if isInitialLoad {
                inbox.setFailure(error.localizedDescription)
            }
        }
    }

    /// The Inbox cache is intentionally in-memory. Restore the visible
    /// connection immediately, then perform one silent load when Inbox opens.
    func loadInboxIfNeeded() async {
        guard inbox.needsInitialLoad else { return }
        guard connections.emailConnected else {
            inbox.markConnected(false)
            return
        }
        guard connections.aiConnected else {
            inbox.setFailure("Connect AI processing in Settings to build your important Inbox.")
            return
        }
        await syncEmail(presentErrors: false)
    }

    /// Pull-to-refresh should never nag about services the user has not set up.
    /// Explicit toolbar sync buttons still surface actionable connection errors.
    func refreshDashboard() async {
        _ = await jobs.refresh()
        tasks.reload()
        reminders.reload()
        inbox.clearTransientFailure()
        if connections.emailConnected && connections.aiConnected {
            await syncEmail(presentErrors: false)
        }
        if connections.calendarConnected { await refreshCalendar(presentErrors: false) }
        if connections.healthConnected { await health.refresh() }
    }

    func refreshJobs() async {
        _ = await jobs.refresh()
        inbox.clearTransientFailure()
        if connections.emailConnected && connections.aiConnected {
            await syncEmail(presentErrors: false)
        }
    }

    func refreshTasks() async {
        tasks.reload()
        reminders.reload()
        inbox.clearTransientFailure()
        if connections.calendarConnected { await refreshCalendar(presentErrors: false) }
        if connections.emailConnected && connections.aiConnected {
            await syncEmail(presentErrors: false)
        }
    }

    func refreshInbox() async {
        inbox.clearTransientFailure()
        guard connections.emailConnected && connections.aiConnected else { return }
        await syncEmail(presentErrors: false)
    }

    /// Confirm a detected update — writes it to the job store.
    func acceptJobUpdate(_ update: DetectedJobUpdate) {
        jobs.applyDetected(update)
        detectedJobUpdates.removeAll { $0.id == update.id }
    }

    func dismissJobUpdate(_ update: DetectedJobUpdate) {
        detectedJobUpdates.removeAll { $0.id == update.id }
    }

    func acceptAllJobUpdates() {
        let updates = detectedJobUpdates
        for update in updates { jobs.applyDetected(update) }
        detectedJobUpdates.removeAll()
    }

    func addCalendarEventToTasks(_ event: UnifiedCalendarEvent) {
        guard !tasks.tasks.contains(where: { $0.relatedCalendarEventID == event.id }) else { return }
        var details = event.provider.label
        if let notes = event.notes, !notes.isEmpty { details += " · \(notes)" }
        tasks.add(TaskItem(
            title: event.title,
            notes: details,
            dueDate: event.start,
            priority: event.isImportant ? .high : .normal,
            source: .calendar,
            relatedCalendarEventID: event.id
        ))
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

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        if url.scheme == "orbit", url.host == "voice" {
            selectedTab = .home
            voiceAssistantRequested = true
            return true
        }
        if url.scheme == "orbit", url.host == "finance" {
            let routeComponents = url.pathComponents.dropFirst()
            let requestedPath: [FinanceRoute]
            if let component = routeComponents.first {
                guard routeComponents.count == 1,
                      let route = FinanceRoute(rawValue: component.lowercased()) else { return false }
                requestedPath = [route]
            } else {
                requestedPath = []
            }
            selectedTab = .finance
            financePath = requestedPath
            Task { await finance.resumeHostedLinkIfNeeded() }
            return true
        }
        if url.scheme == "orbit", url.host == "tasks" {
            selectedTab = .tasks
            if let value = url.pathComponents.dropFirst().first {
                if value == "new" { tasks.createTaskRequested = true }
                else if let id = UUID(uuidString: value) { tasks.openTaskID = id }
            }
            return true
        }
        if url.scheme == "orbit", url.host == "reminders" {
            selectedTab = .tasks
            if let value = url.pathComponents.dropFirst().first {
                if value == "new" { reminders.createReminderRequested = true }
                else if let id = UUID(uuidString: value) { reminders.openReminderID = id }
            }
            return true
        }
        if microsoftAuth.handle(url) { return true }
        return auth.handleRedirect(url)
    }

    // MARK: Helpers

    private func apply(_ session: UserSession) {
        user = session
        connections.googleConnected = true
        // If the login identity granted Gmail/Calendar during auth, reflect it.
        if session.grantedScopes.contains(GoogleScopes.gmailReadonly),
           !UserDefaults.standard.bool(forKey: Keys.gmailDisabled) {
            addGmailAccount(userID: session.userID, email: session.email, fullName: session.fullName)
        }
        if session.grantedScopes.contains(GoogleScopes.calendarReadonly) {
            calendar.setConnected(.google, true)
            persistCalendarProviders()
            updateCalendarConnectionState()
        }
        connections.aiConnected = isChatGPTConnected
        updateEmailConnectionState()
    }

    private func loadPersistedState() {
        let defaults = UserDefaults.standard
        connections.healthConnected = defaults.bool(forKey: Keys.health)
        connections.aiConnected = isChatGPTConnected
        let storedEmailData = defaults.data(forKey: Keys.emailAccounts) ?? defaults.data(forKey: Keys.gmailAccounts)
        if let data = storedEmailData,
           let decoded = try? JSONDecoder().decode([EmailAccount].self, from: data) {
            let primaryID = UserSession.restore()?.userID
            let primaryGmailDisabled = defaults.bool(forKey: Keys.gmailDisabled)
            emailAccounts = decoded.filter {
                !(primaryGmailDisabled && $0.provider == .gmail && $0.userID == primaryID)
            }
        }
        let providerNames = defaults.stringArray(forKey: Keys.calendarProviders)
            ?? (defaults.bool(forKey: Keys.calendar) ? [CalendarProviderType.google.rawValue] : [])
        for name in providerNames {
            if let provider = CalendarProviderType(rawValue: name) { calendar.setConnected(provider, true) }
        }
        updateEmailConnectionState()
        updateCalendarConnectionState()
        tasks.reload()
        reminders.reload()
        tasks.setAppleCalendarSyncEnabled(calendar.connectedProviders.contains(.apple))
        reminders.setAppleCalendarSyncEnabled(calendar.connectedProviders.contains(.apple))
    }

    private func persistEmailAccounts() {
        if let data = try? JSONEncoder().encode(emailAccounts) {
            UserDefaults.standard.set(data, forKey: Keys.emailAccounts)
        }
    }

    private func persistCalendarProviders() {
        let names = calendar.connectedProviders.map(\.rawValue).sorted()
        UserDefaults.standard.set(names, forKey: Keys.calendarProviders)
        UserDefaults.standard.set(calendar.connectedProviders.contains(.google), forKey: Keys.calendar)
    }

    private func updateEmailConnectionState() {
        connections.gmailConnected = !gmailAccounts.isEmpty
        connections.outlookConnected = !outlookAccounts.isEmpty
        inbox.markConnected(connections.emailConnected)
    }

    private func updateCalendarConnectionState() {
        connections.appleCalendarConnected = calendar.connectedProviders.contains(.apple)
        connections.googleCalendarConnected = calendar.connectedProviders.contains(.google)
        connections.outlookCalendarConnected = calendar.connectedProviders.contains(.outlook)
        connections.calendarConnected = !calendar.connectedProviders.isEmpty
    }

    private func resetSignedOut(clearSetup: Bool) {
        user = nil
        emailAccounts = []
        connections = ConnectionStatus()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: Keys.calendar)
        defaults.set(false, forKey: Keys.health)
        defaults.removeObject(forKey: Keys.gmailAccounts)
        defaults.removeObject(forKey: Keys.emailAccounts)
        defaults.removeObject(forKey: Keys.calendarProviders)
        if clearSetup {
            defaults.set(false, forKey: Keys.setupComplete)
            defaults.removeObject(forKey: Keys.gmailDisabled)
            KeychainStore.remove(KeychainKeys.openAIKey)
            KeychainStore.remove(KeychainKeys.adminPassword)
        }
        inbox.markConnected(false)
        calendar.disconnectAll()
        tasks.setAppleCalendarSyncEnabled(false)
        reminders.setAppleCalendarSyncEnabled(false)
        calendarState = .disconnected
        health.disconnect()
        finance.clear()
        financePath = []
        phase = .signedOut
    }
}

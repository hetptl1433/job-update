import AuthenticationServices
import BackgroundTasks
import Combine
import Foundation
import Security
import SwiftData
import UIKit
import UserNotifications

@MainActor
final class AppSession: ObservableObject {
    static let shared = AppSession()

    enum SyncState: Equatable { case idle, syncing, synced, offline, failed(String) }
    enum Provider: String, CaseIterable, Identifiable { case gmail, linkedin, indeed; var id: String { rawValue } }

    @Published var syncState: SyncState = .idle
    @Published var lastSync: Date?
    @Published var connectedProviders: Set<Provider> = []
    @Published var isAppleSignedIn = false
    @Published var alertMessage: String?

    let api = APIClient()
    let notifications = NotificationManager.shared
    private let oauth = OAuthSession()

    private init() {
        connectedProviders = Set(Provider.allCases.filter { UserDefaults.standard.bool(forKey: "connected.\($0.rawValue)") })
        isAppleSignedIn = UserDefaults.standard.bool(forKey: "appleSignedIn")
    }

    func refresh(using context: ModelContext) async -> Bool {
        syncState = .syncing
        do {
            let remote = try await api.fetchApplications()
            try upsert(remote, into: context)
            lastSync = .now
            syncState = .synced
            await notifications.rescheduleAll(remote)
            return true
        } catch {
            syncState = .failed(error.localizedDescription)
            alertMessage = error.localizedDescription
            return false
        }
    }

    func saveAll(_ applications: [JobApplication]) async {
        syncState = .syncing
        do {
            try await api.saveApplications(applications.map(JobApplicationDTO.init))
            lastSync = .now
            syncState = .synced
        } catch {
            syncState = .failed(error.localizedDescription)
            alertMessage = error.localizedDescription
        }
    }

    func connect(_ provider: Provider) async {
        do {
            let callback = try await oauth.authorize(provider: provider, baseURL: api.baseURL)
            guard callback.host == "oauth" else { throw URLError(.badServerResponse) }
            connectedProviders.insert(provider)
            UserDefaults.standard.set(true, forKey: "connected.\(provider.rawValue)")
        } catch {
            alertMessage = "Could not connect \(provider.rawValue.capitalized): \(error.localizedDescription)"
        }
    }

    func disconnect(_ provider: Provider) {
        connectedProviders.remove(provider)
        UserDefaults.standard.removeObject(forKey: "connected.\(provider.rawValue)")
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  !credential.user.isEmpty else {
                throw URLError(.userAuthenticationRequired)
            }
            isAppleSignedIn = true
            UserDefaults.standard.set(true, forKey: "appleSignedIn")
        } catch {
            alertMessage = "Apple sign-in failed: \(error.localizedDescription)"
        }
    }

    func setAdminPassword(_ password: String) throws {
        try KeychainStore.set(password, for: "jobradar.adminPassword")
    }

    func adminPassword() -> String { KeychainStore.get("jobradar.adminPassword") ?? "" }

    private func upsert(_ remote: [JobApplicationDTO], into context: ModelContext) throws {
        let local = try context.fetch(FetchDescriptor<JobApplication>())
        let byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteIDs = Set(remote.map(\.id))

        for dto in remote {
            let item = byID[dto.id] ?? JobApplication(id: dto.id)
            if byID[dto.id] == nil { context.insert(item) }
            item.company = dto.company
            item.role = dto.role
            item.stage = dto.stage
            item.inviteDate = dto.inviteDate.flatMap { DateFormatters.api.date(from: $0) }
            item.interviewDate = dto.interviewDate.flatMap { DateFormatters.api.date(from: $0) }
            item.statusRaw = dto.status
            item.priorityRaw = dto.priority
            item.nextAction = dto.nextAction
            item.followUpDate = dto.followUpDate.flatMap { DateFormatters.api.date(from: $0) }
            item.contact = dto.contact
            item.mode = dto.mode
            item.notes = dto.notes
            item.updatedAt = .now
        }

        for item in local where !remoteIDs.contains(item.id) { context.delete(item) }
        try context.save()
    }
}

struct TrackerEnvelope: Decodable { let data: [JobApplicationDTO] }

final class APIClient {
    let baseURL: URL

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        baseURL = URL(string: configured ?? "https://job-update.vercel.app")!
    }

    func fetchApplications() async throws -> [JobApplicationDTO] {
        var request = URLRequest(url: baseURL.appending(path: "api/tracker"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(TrackerEnvelope.self, from: data).data
    }

    func saveApplications(_ applications: [JobApplicationDTO]) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/tracker"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(applications)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
    }

    func registerDeviceToken(_ token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/mobile/push/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token, "platform": "ios"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
    }

    private func authorize(_ request: inout URLRequest) {
        if let password = KeychainStore.get("jobradar.adminPassword"), !password.isEmpty {
            request.setValue(password, forHTTPHeaderField: "x-admin-password")
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "JobRadar.API", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message ?? "The Job Radar server rejected the request."])
        }
    }
}

@MainActor
final class OAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(provider: AppSession.Provider, baseURL: URL) async throws -> URL {
        var components = URLComponents(url: baseURL.appending(path: "api/mobile/oauth/\(provider.rawValue)/start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "callback", value: "jobradar://oauth/\(provider.rawValue)")]
        guard let url = components.url else { throw URLError(.badURL) }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: "jobradar") { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: URLError(.cancelled)) }
            }
            session?.presentationContextProvider = self
            session?.prefersEphemeralWebBrowserSession = false
            session?.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIWindow(frame: .zero)
    }
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    func scheduleReminder(for application: JobApplicationDTO) async {
        let identifier = "job-reminder-\(application.id)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let dateText = application.followUpDate,
              let date = DateFormatters.api.date(from: dateText),
              !(JobStatus(rawValue: application.status)?.isClosed ?? false) else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        let content = UNMutableNotificationContent()
        content.title = "Follow up with \(application.company)"
        content.body = application.nextAction.isEmpty ? "Check the latest status for \(application.role)." : application.nextAction
        content.sound = .default
        content.userInfo = ["applicationID": application.id]
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await center.add(request)
    }

    func scheduleDailyDigest(hour: Int = 6) async {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-job-radar"])
        let content = UNMutableNotificationContent()
        content.title = "Job Radar"
        content.body = "Your morning pipeline check is ready."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "daily-job-radar", content: content, trigger: trigger))
    }

    func rescheduleAll(_ applications: [JobApplicationDTO]) async {
        for application in applications { await scheduleReminder(for: application) }
    }
}

@MainActor
final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    static let identifier = "com.hetpatel.jobradar.refresh"
    var refreshHandler: (() async -> Bool)?

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                self.schedule()
                let success = await self.refreshHandler?() ?? false
                refreshTask.setTaskCompleted(success: success)
            }
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum KeychainStore {
    static func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecValueData: data] as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func get(_ key: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

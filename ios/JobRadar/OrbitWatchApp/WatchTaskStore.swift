import Combine
import Foundation
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

enum WatchVoiceRequestState: Equatable {
    case idle
    case requesting(UUID)
    case ready(WatchVoiceBootstrap)
    case failed(WatchVoiceFailure)

    var requestID: UUID? {
        switch self {
        case .idle:
            nil
        case let .requesting(requestID):
            requestID
        case let .ready(bootstrap):
            bootstrap.requestID
        case let .failed(failure):
            failure.requestID
        }
    }
}

final class WatchTaskStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var tasks: [WatchTaskSnapshotItem] = []
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var voiceRequestState: WatchVoiceRequestState = .idle

    private enum Keys {
        static let cachedSnapshot = "orbit.watch.cached-task-snapshot.v1"
        static let pendingCompletions = "orbit.watch.pending-task-completions.v1"
    }

    private let session = WCSession.default
    private var pendingCompletionIDs: Set<UUID> = []

    override init() {
        super.init()
        loadCache()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func task(withID id: UUID) -> WatchTaskSnapshotItem? {
        tasks.first { $0.id == id }
    }

    func complete(_ task: WatchTaskSnapshotItem) {
        guard tasks.contains(where: { $0.id == task.id }) else { return }
        pendingCompletionIDs.insert(task.id)
        tasks.removeAll { $0.id == task.id }
        persistCache()
        persistPendingCompletions()
#if os(watchOS)
        WKInterfaceDevice.current().play(.success)
#endif

        let message = WatchTaskSyncProtocol.completionMessage(taskID: task.id)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                guard let self else { return }
                _ = self.session.transferUserInfo(message)
            }
        } else {
            _ = session.transferUserInfo(message)
        }
    }

    func requestLatest() {
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(
            [WatchTaskSyncProtocol.requestSnapshotKey: true],
            replyHandler: { [weak self] response in self?.receive(response) },
            errorHandler: nil
        )
    }

    /// Requests a short-lived client credential from the companion iPhone. The
    /// resulting Watch connection goes directly to the Realtime API; audio is
    /// never relayed through WatchConnectivity.
    func requestVoiceBootstrap() {
        let request = WatchVoiceRequest()
        guard session.activationState == .activated, session.isReachable else {
            voiceRequestState = .failed(
                WatchVoiceFailure(
                    requestID: request.requestID,
                    code: .phoneUnreachable,
                    message: "Open Orbit on your iPhone, then try again."
                )
            )
            return
        }

        let message = WatchVoiceProtocol.requestMessage(request)
        guard !message.isEmpty else {
            voiceRequestState = .failed(
                WatchVoiceFailure(
                    requestID: request.requestID,
                    code: .requestEncodingFailed,
                    message: "Orbit couldn't prepare the voice request."
                )
            )
            return
        }

        voiceRequestState = .requesting(request.requestID)
        session.sendMessage(
            message,
            replyHandler: { [weak self] response in
                self?.receive(response)
            },
            errorHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self,
                          self.voiceRequestState == .requesting(request.requestID) else { return }
                    self.voiceRequestState = .failed(
                        WatchVoiceFailure(
                            requestID: request.requestID,
                            code: .requestDeliveryFailed,
                            message: "Orbit couldn't reach your iPhone. Try again nearby."
                        )
                    )
                }
            }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self,
                  self.voiceRequestState == .requesting(request.requestID) else { return }
            self.voiceRequestState = .failed(
                WatchVoiceFailure(
                    requestID: request.requestID,
                    code: .bootstrapFailed,
                    message: "Your iPhone took too long to prepare voice. Try again."
                )
            )
        }
    }

    /// Returns a credential exactly once and rechecks its lifetime immediately
    /// before the voice view begins opening the WebSocket.
    func consumeVoiceBootstrap(requestID: UUID) -> WatchVoiceBootstrap? {
        guard case let .ready(bootstrap) = voiceRequestState,
              bootstrap.requestID == requestID else { return nil }

        guard bootstrap.isUsable() else {
            voiceRequestState = .failed(expiredVoiceFailure(requestID: requestID))
            return nil
        }

        voiceRequestState = .idle
        return bootstrap
    }

    func resetVoiceRequest() {
        voiceRequestState = .idle
    }

    private func receive(_ context: [String: Any]) {
        let snapshot = WatchTaskSyncProtocol.snapshot(from: context)
        let voiceBootstrap = WatchVoiceProtocol.bootstrap(from: context)
        let voiceFailure = WatchVoiceProtocol.failure(from: context)
        guard snapshot != nil || voiceBootstrap != nil || voiceFailure != nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let snapshot { self.apply(snapshot) }
            if let voiceBootstrap { self.apply(voiceBootstrap) }
            if let voiceFailure { self.apply(voiceFailure) }
        }
    }

    private func apply(_ bootstrap: WatchVoiceBootstrap) {
        guard voiceRequestState == .requesting(bootstrap.requestID) else { return }
        guard bootstrap.isUsable() else {
            voiceRequestState = .failed(expiredVoiceFailure(requestID: bootstrap.requestID))
            return
        }
        voiceRequestState = .ready(bootstrap)
    }

    private func apply(_ failure: WatchVoiceFailure) {
        guard voiceRequestState == .requesting(failure.requestID) else { return }
        voiceRequestState = .failed(failure)
    }

    private func expiredVoiceFailure(requestID: UUID) -> WatchVoiceFailure {
        WatchVoiceFailure(
            requestID: requestID,
            code: .credentialExpired,
            message: "The voice connection took too long to start. Try again."
        )
    }

    private func apply(_ snapshot: WatchTaskSnapshot) {
        let remoteIDs = Set(snapshot.tasks.map(\.id))
        pendingCompletionIDs.formIntersection(remoteIDs)
        tasks = snapshot.tasks.filter { !pendingCompletionIDs.contains($0.id) }
        lastUpdatedAt = snapshot.generatedAt
        persistCache()
        persistPendingCompletions()
    }

    private func loadCache() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.cachedSnapshot),
           let snapshot = try? JSONDecoder().decode(WatchTaskSnapshot.self, from: data) {
            tasks = snapshot.tasks
            lastUpdatedAt = snapshot.generatedAt
        }
        let values = defaults.stringArray(forKey: Keys.pendingCompletions) ?? []
        pendingCompletionIDs = Set(values.compactMap(UUID.init(uuidString:)))
        tasks.removeAll { pendingCompletionIDs.contains($0.id) }
    }

    private func persistCache() {
        let snapshot = WatchTaskSnapshot(generatedAt: lastUpdatedAt ?? .now, tasks: tasks)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Keys.cachedSnapshot)
        }
    }

    private func persistPendingCompletions() {
        UserDefaults.standard.set(
            pendingCompletionIDs.map(\.uuidString).sorted(),
            forKey: Keys.pendingCompletions
        )
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isPhoneReachable = activationState == .activated && session.isReachable
        }
        guard error == nil, activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        requestLatest()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPhoneReachable = session.isReachable
            if session.isReachable {
                self.requestLatest()
            } else if case let .requesting(requestID) = self.voiceRequestState {
                self.voiceRequestState = .failed(
                    WatchVoiceFailure(
                        requestID: requestID,
                        code: .phoneUnreachable,
                        message: "The iPhone connection was lost. Try again nearby."
                    )
                )
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        receive(message)
        replyHandler([WatchTaskSyncProtocol.acknowledgementKey: true])
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}

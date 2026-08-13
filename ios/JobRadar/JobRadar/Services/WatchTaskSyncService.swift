import Foundation
import WatchConnectivity

/// Publishes the latest open-task snapshot to Apple Watch and accepts
/// idempotent completion events from the companion app.
final class WatchTaskSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchTaskSyncService()

    var onTaskCompleted: ((UUID) -> Void)?
    /// Mints a short-lived Realtime credential in response to an interactive
    /// Watch request. This is async because it calls OpenAI's REST endpoint;
    /// the long-lived key itself never leaves the iPhone Keychain.
    var onVoiceBootstrapRequested: (@MainActor (WatchVoiceRequest) async -> Result<WatchVoiceBootstrap, WatchVoiceFailure>)?

    private let session = WCSession.default
    private let lock = NSLock()
    private var latestContext: [String: Any]?
    private var hasStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }

        lock.lock()
        let shouldStart = !hasStarted
        hasStarted = true
        lock.unlock()

        guard shouldStart else { return }
        session.delegate = self
        session.activate()
    }

    func publish(tasks: [TaskItem]) {
        let items = SharedTaskStore.prioritized(tasks).map { task in
            WatchTaskSnapshotItem(
                id: task.id,
                title: task.title,
                notes: task.notes,
                dueDate: task.dueDate,
                priority: WatchTaskSnapshotItem.Priority(rawValue: task.priority.rawValue) ?? .normal,
                updatedAt: task.updatedAt
            )
        }
        let snapshot = WatchTaskSnapshot(generatedAt: .now, tasks: items)
        guard let context = try? WatchTaskSyncProtocol.context(for: snapshot) else { return }

        lock.lock()
        latestContext = context
        lock.unlock()
        flushLatestContext()
    }

    private func flushLatestContext() {
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled,
              let context = currentContext() else { return }

        try? session.updateApplicationContext(context)
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil, errorHandler: nil)
        }
    }

    private func currentContext() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return latestContext
    }

    private func handle(_ message: [String: Any]) {
        guard let id = WatchTaskSyncProtocol.completedTaskID(from: message) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onTaskCompleted?(id)
        }
    }

    private func handleVoiceRequest(
        _ request: WatchVoiceRequest,
        reply: @escaping ([String: Any]) -> Void
    ) {
        guard let onVoiceBootstrapRequested else {
            reply(WatchVoiceProtocol.failureMessage(WatchVoiceFailure(
                requestID: request.requestID,
                code: .phoneNotReady,
                message: "Open Orbit on your iPhone and connect ChatGPT first."
            )))
            return
        }

        Task {
            let result = await onVoiceBootstrapRequested(request)
            switch result {
            case let .success(bootstrap):
                reply(WatchVoiceProtocol.bootstrapMessage(bootstrap))
            case let .failure(failure):
                reply(WatchVoiceProtocol.failureMessage(failure))
            }
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else { return }
        flushLatestContext()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        flushLatestContext()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { flushLatestContext() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard WatchVoiceProtocol.request(from: message) == nil else { return }
        handle(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let request = WatchVoiceProtocol.request(from: message) {
            handleVoiceRequest(request, reply: replyHandler)
            return
        }
        handle(message)
        var response = currentContext() ?? [:]
        response[WatchTaskSyncProtocol.acknowledgementKey] = true
        replyHandler(response)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }
}

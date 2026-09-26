import Foundation

/// Health data access. Separated from the UI so the concrete HealthKit provider
/// can be swapped or mocked. HealthKit permissions are first requested when the
/// user connects and checked again from the Health screen when categories grow.
protocol HealthProviding {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func summary() async throws -> HealthSummary
}

@MainActor
final class HealthRepository: ObservableObject {
    @Published private(set) var state: LoadState<HealthSummary> = .disconnected
    /// True while a refresh runs behind a summary that's already showing.
    @Published private(set) var isRefreshing = false

    private let provider: HealthProviding
    /// Home and Health both refresh when they appear; they share one read.
    private var inFlightRefresh: Task<Void, Never>?
    /// A HealthKit read that never answers fails instead of spinning forever.
    private let refreshTimeout: Duration = .seconds(30)
    /// When the last read finished, so Home appearing again soon after launch
    /// or a trip to another tab doesn't rerun every HealthKit query.
    private var lastLoadedAt: Date?
    private static let automaticRefreshInterval: TimeInterval = 120

    init(provider: HealthProviding = HealthKitProvider()) {
        self.provider = provider
    }

    var isAvailable: Bool { provider.isAvailable }

    /// Requests HealthKit authorization, then loads the summary. Returns whether
    /// the connection is considered active.
    @discardableResult
    func connect() async -> Bool {
        guard provider.isAvailable else {
            state = .failed("Health data isn't available on this device.")
            return false
        }
        do {
            try await provider.requestAuthorization()
            await refresh()
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    func refresh() async {
        guard provider.isAvailable else { state = .disconnected; return }
        if let inFlightRefresh {
            await inFlightRefresh.value
            return
        }
        let task = Task { await load() }
        inFlightRefresh = task
        await task.value
        inFlightRefresh = nil
    }

    /// For automatic refreshes such as Home appearing. Pull to refresh and the
    /// Health screen itself still call `refresh()`.
    func refreshIfStale() async {
        if let lastLoadedAt, Date.now.timeIntervalSince(lastLoadedAt) < Self.automaticRefreshInterval {
            return
        }
        await refresh()
    }

    /// Keeps the last summary on screen while it reloads, so returning to
    /// Health never blanks the dashboard behind a spinner.
    private func load() async {
        let previous = state.value
        if previous == nil { state = .loading } else { isRefreshing = true }
        defer { isRefreshing = false }
        do {
            let summary = try await summaryWithTimeout()
            state = summary.hasRecentData ? .loaded(summary) : .empty
            lastLoadedAt = .now
        } catch {
            // A failed refresh keeps showing data that already loaded; its
            // "Refreshed" time shows how old it is.
            if previous == nil { state = .failed(error.localizedDescription) }
        }
    }

    /// HealthKit's callbacks can't be cancelled, so this races the read
    /// against a timer instead of waiting on a task group.
    private func summaryWithTimeout() async throws -> HealthSummary {
        let provider = provider
        let timeout = refreshTimeout
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeOnce(continuation)
            Task {
                do { gate.resume(with: .success(try await provider.summary())) }
                catch { gate.resume(with: .failure(error)) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                gate.resume(with: .failure(HealthLoadError.timedOut))
            }
        }
    }

    func disconnect() {
        state = .disconnected
        lastLoadedAt = nil
    }
}

enum HealthLoadError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "Apple Health took too long to respond. Pull down to try again."
    }
}

/// Resumes a continuation with whichever result arrives first.
private final class ResumeOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

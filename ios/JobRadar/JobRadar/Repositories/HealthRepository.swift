import Foundation

/// Health data access. Separated from the UI so the concrete HealthKit provider
/// can be swapped or mocked. HealthKit permissions are requested only when the
/// user taps "Connect Apple Health" — never during onboarding.
protocol HealthProviding {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func summary() async throws -> HealthSummary
}

@MainActor
final class HealthRepository: ObservableObject {
    @Published private(set) var state: LoadState<HealthSummary> = .disconnected

    private let provider: HealthProviding

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
        state = .loading
        do {
            let summary = try await provider.summary()
            state = summary.metrics.isEmpty ? .empty : .loaded(summary)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        state = .disconnected
    }
}

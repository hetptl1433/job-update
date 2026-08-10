import Foundation

/// One calendar timeline assembled from Apple, Google, and Outlook providers.
/// Views never reach into provider-specific clients.
@MainActor
final class CalendarRepository: ObservableObject {
    @Published private(set) var state: LoadState<[UnifiedCalendarEvent]> = .disconnected
    @Published private(set) var connectedProviders: Set<CalendarProviderType> = []

    private var eventsByProvider: [CalendarProviderType: [UnifiedCalendarEvent]] = [:]

    var events: [UnifiedCalendarEvent] { state.value ?? [] }

    func setConnected(_ provider: CalendarProviderType, _ connected: Bool) {
        if connected { connectedProviders.insert(provider) }
        else {
            connectedProviders.remove(provider)
            eventsByProvider.removeValue(forKey: provider)
        }
        publish()
    }

    func beginLoading() {
        state = connectedProviders.isEmpty ? .disconnected : .loading
    }

    func setEvents(_ events: [UnifiedCalendarEvent], for provider: CalendarProviderType) {
        connectedProviders.insert(provider)
        eventsByProvider[provider] = events
        publish()
    }

    func setFailure(_ message: String) {
        state = .failed(message)
    }

    func disconnectAll() {
        connectedProviders.removeAll()
        eventsByProvider.removeAll()
        state = .disconnected
    }

    private func publish() {
        guard !connectedProviders.isEmpty else {
            state = .disconnected
            return
        }
        let values = eventsByProvider.values.flatMap { $0 }.sorted { $0.start < $1.start }
        state = values.isEmpty ? .empty : .loaded(values)
    }
}

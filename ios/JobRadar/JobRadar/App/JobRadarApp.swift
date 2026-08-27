import SwiftData
import SwiftUI

@main
struct JobRadarApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    private let modelContainer: ModelContainer

    init() {
        let container = Self.makeContainer()
        modelContainer = container
        let state = AppState(modelContext: container.mainContext)
        _appState = StateObject(wrappedValue: state)
        BackgroundRefreshManager.shared.refreshHandler = { await state.backgroundRefresh() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.inbox)
                .environmentObject(appState.tasks)
                .environmentObject(appState.calendar)
                .environmentObject(appState.finance)
                .environmentObject(appState.health)
                .environmentObject(appState.automations)
                .onOpenURL { url in
                    _ = appState.handleOpenURL(url)
                }
                .task {
                    await appState.notifications.requestAuthorization()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        appState.consumePendingLaunchRequest()
                        appState.tasks.reload()
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    /// Build the SwiftData container. The store is a re-syncable cache, so if a
    /// schema change makes the on-disk store incompatible we recreate it rather
    /// than crashing.
    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: JobApplication.self)
        } catch {
            let fresh = ModelConfiguration(isStoredInMemoryOnly: false, allowsSave: true)
            if let container = try? ModelContainer(for: JobApplication.self, configurations: fresh) {
                return container
            }
            // Last resort: in-memory so the app still launches.
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: JobApplication.self, configurations: memory)
        }
    }
}

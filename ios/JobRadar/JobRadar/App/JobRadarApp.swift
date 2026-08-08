import SwiftData
import SwiftUI

@main
struct JobRadarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session: AppSession
    private let modelContainer: ModelContainer

    init() {
        do {
            let container = try ModelContainer(for: JobApplication.self)
            modelContainer = container
            let sharedSession = AppSession.shared
            _session = StateObject(wrappedValue: sharedSession)
            BackgroundRefreshManager.shared.refreshHandler = {
                await sharedSession.refresh(using: container.mainContext)
            }
        } catch {
            fatalError("Unable to create Job Radar database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    await session.notifications.requestAuthorization()
                    await session.notifications.scheduleDailyDigest(hour: 6)
                    _ = await session.refresh(using: modelContainer.mainContext)
                    BackgroundRefreshManager.shared.schedule()
                }
        }
        .modelContainer(modelContainer)
    }
}

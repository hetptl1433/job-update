import SwiftUI

@main
struct OrbitWatchApp: App {
    @StateObject private var tasks = WatchTaskStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(tasks)
        }
    }
}

import SwiftData
import SwiftUI

#if DEBUG
/// Helpers for SwiftUI previews only. Builds an in-memory AppState so previews
/// never touch real storage or the network.
@MainActor
enum PreviewSupport {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: JobApplication.self, configurations: config)
    }()

    static func appState() -> AppState {
        AppState(modelContext: container.mainContext)
    }
}
#endif

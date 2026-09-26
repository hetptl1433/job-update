import SwiftUI

/// What the menu bar and keyboard shortcuts can do in the focused window.
struct OrbitNavigator {
    var show: (AppState.Tab) -> Void
    var openChat: () -> Void
    var startVoice: () -> Void
    var newTask: () -> Void
    var openSettings: () -> Void
}

private struct OrbitNavigatorKey: FocusedValueKey {
    typealias Value = OrbitNavigator
}

extension FocusedValues {
    var orbitNavigator: OrbitNavigator? {
        get { self[OrbitNavigatorKey.self] }
        set { self[OrbitNavigatorKey.self] = newValue }
    }
}

/// Menu bar items and keyboard shortcuts for iPad with a hardware keyboard.
/// Holding Command lists them.
struct OrbitCommands: Commands {
    @FocusedValue(\.orbitNavigator) private var navigator

    private static let destinations: [(title: String, tab: AppState.Tab, key: KeyEquivalent)] = [
        ("Home", .home, "1"),
        ("Finance", .finance, "2"),
        ("Health", .health, "3"),
        ("To Do", .tasks, "4"),
        ("Jobs", .jobs, "5"),
        ("Inbox", .inbox, "6")
    ]

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New To Do") { navigator?.newTask() }
                .keyboardShortcut("n")
                .disabled(navigator == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings") { navigator?.openSettings() }
                .keyboardShortcut(",")
                .disabled(navigator == nil)
        }
        CommandMenu("Go") {
            Group {
                Button("Orbit Chat") { navigator?.openChat() }
                    .keyboardShortcut("k")
                Button("Live Voice") { navigator?.startVoice() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                ForEach(Self.destinations, id: \.title) { destination in
                    Button(destination.title) { navigator?.show(destination.tab) }
                        .keyboardShortcut(destination.key)
                }
            }
            .disabled(navigator == nil)
        }
    }
}

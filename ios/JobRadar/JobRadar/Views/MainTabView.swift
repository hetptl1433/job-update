import SwiftUI

/// Primary navigation: five clean destinations. The AI assistant is reached as
/// a prominent action from Home rather than a sixth tab.
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
            JobsView()
                .tabItem { Label("Jobs", systemImage: "briefcase") }
            HealthView()
                .tabItem { Label("Health", systemImage: "heart") }
            AutomationsView()
                .tabItem { Label("Automations", systemImage: "wand.and.stars") }
        }
        .tint(AppTheme.accent)
    }
}

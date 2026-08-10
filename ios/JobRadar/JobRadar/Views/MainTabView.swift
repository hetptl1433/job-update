import SwiftUI

/// Primary navigation: five clean destinations. The AI assistant is reached as
/// a prominent action from Home rather than a sixth tab.
struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView(selection: $app.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppState.Tab.home)
            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(AppState.Tab.tasks)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(AppState.Tab.inbox)
            JobsView()
                .tabItem { Label("Jobs", systemImage: "briefcase") }
                .tag(AppState.Tab.jobs)
            FinanceView()
                .tabItem { Label("Finance", systemImage: "creditcard") }
                .tag(AppState.Tab.finance)
        }
        .tint(AppTheme.brand)
        .sheet(isPresented: $app.voiceAssistantRequested) {
            NavigationStack {
                AssistantView(startsListening: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { app.voiceAssistantRequested = false }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
    }
}

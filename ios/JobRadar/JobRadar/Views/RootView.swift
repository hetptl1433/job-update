import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            RadarView()
                .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
            ConnectionsView()
                .tabItem { Label("Connections", systemImage: "link") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(.radarMint)
    }
}

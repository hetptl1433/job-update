import SwiftUI

/// Health summary. UI and data provider are separated so a real HealthKit
/// provider drops in later. Until then this shows an honest connect state.
struct HealthView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    switch app.health.state {
                    case let .loaded(summary):
                        metricsGrid(summary)
                    case .loading:
                        LoadingStateView()
                    case .failed(let message):
                        InfoStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load health",
                                      message: message)
                    default:
                        InfoStateView(
                            systemImage: "heart",
                            title: "Connect Apple Health",
                            message: "See your sleep, steps, workouts and heart data alongside everything else. Health permissions are only requested when you connect.",
                            actionTitle: "Connect Apple Health"
                        ) { app.connectHealth() }
                        .cardSurface()
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("Health")
            .task { await app.health.refresh() }
        }
    }

    private func metricsGrid(_ summary: HealthSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.md) {
            ForEach(summary.metrics) { metric in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Label(metric.title, systemImage: metric.systemImage)
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Text(metric.value).font(.title3.weight(.bold)).foregroundStyle(AppTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }
}

#Preview {
    HealthView().environmentObject(PreviewSupport.appState())
}

import SwiftUI

/// Automations configuration. These are settings the user controls; the actual
/// scheduled monitoring runs on the backend with push delivery — not on-device.
struct AutomationsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    Text("Automations run on \(AppConfig.appName)'s backend and notify you here. Enable the ones you want.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)

                    VStack(spacing: AppTheme.Spacing.md) {
                        ForEach(app.automations.automations) { automation in
                            AutomationRow(automation: automation) { enabled in
                                app.automations.setEnabled(enabled, for: automation)
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
            .navigationTitle("Automations")
        }
    }
}

private struct AutomationRow: View {
    let automation: Automation
    let onToggle: (Bool) -> Void
    @State private var isOn: Bool

    init(automation: Automation, onToggle: @escaping (Bool) -> Void) {
        self.automation = automation
        self.onToggle = onToggle
        _isOn = State(initialValue: automation.enabled)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: automation.trigger.systemImage)
                .font(.title3)
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 40, height: 40)
                .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(automation.title).font(.headline).foregroundStyle(AppTheme.primaryText)
                Text(automation.detail).font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(automation.frequency).font(.caption2).foregroundStyle(AppTheme.tertiaryText).padding(.top, 2)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppTheme.accent)
                .onChange(of: isOn) { _, newValue in onToggle(newValue) }
        }
        .cardSurface()
    }
}

#Preview {
    AutomationsView().environmentObject(PreviewSupport.appState())
}

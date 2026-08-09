import Foundation

/// Manages the user's automation configuration.
///
/// These are user-configurable settings, not fabricated live results. Actual
/// scheduled monitoring runs on the backend (with push notifications to the
/// device) — the iOS app cannot reliably run hourly server monitoring itself.
@MainActor
final class AutomationService: ObservableObject {
    @Published private(set) var automations: [Automation]

    init() {
        // Seed the catalog of available automations, all disabled by default.
        automations = AutomationTrigger.allCases.map { trigger in
            Automation(
                id: trigger.rawValue,
                trigger: trigger,
                enabled: false,
                frequency: Self.defaultFrequency(for: trigger),
                lastRun: nil,
                nextRun: nil
            )
        }
    }

    func setEnabled(_ enabled: Bool, for automation: Automation) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[index].enabled = enabled
        // A real implementation registers/removes the schedule on the backend.
    }

    var enabledCount: Int { automations.filter(\.enabled).count }

    private static func defaultFrequency(for trigger: AutomationTrigger) -> String {
        switch trigger {
        case .importantEmail: "Every 30 minutes"
        case .jobFollowUp: "Daily"
        case .morningBrief: "Daily at 6:00 AM"
        case .interviewReminder: "1 hour before"
        case .weeklyHealth: "Weekly"
        }
    }
}

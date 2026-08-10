import Foundation
import SwiftUI

// MARK: - Attention items (Home: "Needs your attention")

enum AttentionCategory: String, Codable, CaseIterable {
    case email, job, calendar, health, task, system

    var systemImage: String {
        switch self {
        case .email: "envelope"
        case .job: "briefcase"
        case .calendar: "calendar"
        case .health: "heart"
        case .task: "checklist"
        case .system: "bell"
        }
    }

    var label: String { rawValue.capitalized }
}

enum AttentionImportance: Int, Codable, Comparable {
    case low = 0, normal = 1, high = 2

    static func < (lhs: AttentionImportance, rhs: AttentionImportance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// An actionable item surfaced on the Home screen from the user's local jobs
/// and classified provider-neutral email data.
struct AttentionItem: Identifiable, Hashable {
    let id: String
    var category: AttentionCategory
    var title: String
    var detail: String
    var timestamp: Date
    var importance: AttentionImportance
    var source: String
    var actionTitle: String?
    var isCompleted: Bool = false

    static func == (lhs: AttentionItem, rhs: AttentionItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Inbox

enum InboxSection: String, CaseIterable, Identifiable {
    case needsAction = "Needs Action"
    case important = "Important"
    case jobs = "Jobs"
    case everythingElse = "Everything Else"
    var id: String { rawValue }
}

/// AI-classified provider-neutral mail. Provider API payloads are normalized
/// before the Inbox, Home, Tasks, Jobs, or Assistant consumes them.
struct InboxMessage: Identifiable, Hashable {
    let id: String
    var provider: EmailProviderType
    var accountID: String
    var accountEmail: String
    var senderName: String
    var senderEmail: String
    var subject: String
    var aiSummary: String
    var receivedAt: Date
    var importance: AttentionImportance
    var actionRequired: Bool
    var section: InboxSection
    var isRead: Bool = false
    var threadID: String?
    var labels: [String] = []

    var mailboxEmail: String { accountEmail }
    var sender: String { senderName.isEmpty ? senderEmail : senderName }
}

// MARK: - Calendar

enum CalendarProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case google
    case outlook

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: "Apple Calendar"
        case .google: "Google Calendar"
        case .outlook: "Outlook Calendar"
        }
    }
    var systemImage: String {
        switch self {
        case .apple: "apple.logo"
        case .google: "g.circle"
        case .outlook: "building.2"
        }
    }
}

struct UnifiedCalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    var provider: CalendarProviderType
    var calendarID: String
    var title: String
    var start: Date
    var end: Date?
    var location: String?
    var notes: String?
    var meetingURL: URL?
    var isAllDay: Bool
    var relatedJobApplicationID: Int?
    var isImportant: Bool = false
}

typealias CalendarEvent = UnifiedCalendarEvent

protocol CalendarProviderService {
    var provider: CalendarProviderType { get }
    func upcomingEvents(token: String?) async throws -> [UnifiedCalendarEvent]
}

// MARK: - Health

struct HealthMetric: Identifiable, Hashable {
    let id: String
    var title: String
    var value: String
    var systemImage: String
}

struct HealthSummary: Hashable {
    var metrics: [HealthMetric]
    var isConnected: Bool
}

// MARK: - Automations

enum AutomationTrigger: String, Codable, CaseIterable, Identifiable {
    case importantEmail = "Important Email Watch"
    case jobFollowUp = "Job Follow-up"
    case morningBrief = "Morning Brief"
    case interviewReminder = "Interview Reminder"
    case weeklyHealth = "Weekly Health Summary"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .importantEmail: "envelope.badge"
        case .jobFollowUp: "clock.arrow.circlepath"
        case .morningBrief: "sun.max"
        case .interviewReminder: "bell.badge"
        case .weeklyHealth: "chart.line.uptrend.xyaxis"
        }
    }

    var detail: String {
        switch self {
        case .importantEmail: "Check for important messages and recruiter responses."
        case .jobFollowUp: "Identify applications inactive for a configured number of days."
        case .morningBrief: "Summarize what needs attention each morning."
        case .interviewReminder: "Remind you before scheduled interviews."
        case .weeklyHealth: "Summarize your health and activity trends."
        }
    }
}

/// Long-running/scheduled monitoring is ultimately a backend concern (with push
/// notifications to the device). This model represents the user-facing
/// configuration of an automation.
struct Automation: Identifiable, Hashable {
    let id: String
    var trigger: AutomationTrigger
    var enabled: Bool
    var frequency: String
    var lastRun: Date?
    var nextRun: Date?

    var title: String { trigger.rawValue }
    var detail: String { trigger.detail }
}

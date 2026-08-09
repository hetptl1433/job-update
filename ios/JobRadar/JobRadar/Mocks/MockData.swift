import Foundation

/// Sample data for SwiftUI previews and design iteration ONLY.
///
/// This must never be shown to a signed-in production user. Live screens read
/// from repositories that return real data or honest empty/disconnected states.
enum MockData {
    static func minutesAgo(_ m: Int) -> Date { Date().addingTimeInterval(TimeInterval(-m * 60)) }
    static func hoursFromNow(_ h: Double) -> Date { Date().addingTimeInterval(h * 3600) }

    static let attention: [AttentionItem] = [
        AttentionItem(id: "a1", category: .task, title: "Career Services requested a document",
                      detail: "Upload your updated resume by Friday.", timestamp: minutesAgo(35),
                      importance: .high, source: "Career Services", actionTitle: "Open"),
        AttentionItem(id: "a2", category: .email, title: "Recruiter replied — response recommended",
                      detail: "ARCO Design/Build wants to schedule a 30-minute call.", timestamp: minutesAgo(12),
                      importance: .high, source: "Gmail", actionTitle: "Reply"),
        AttentionItem(id: "a3", category: .calendar, title: "Interview tomorrow at 10:00 AM",
                      detail: "Technical screen with Northwind.", timestamp: hoursFromNow(20),
                      importance: .high, source: "Calendar", actionTitle: "View"),
        AttentionItem(id: "a4", category: .job, title: "Job application needs follow-up",
                      detail: "No response from Vertex in 9 days.", timestamp: minutesAgo(600),
                      importance: .normal, source: "Jobs", actionTitle: "Follow up")
    ]

    static let inbox: [InboxMessage] = [
        InboxMessage(id: "m1", sender: "ARCO Design/Build", subject: "Interview availability",
                     aiSummary: "They'd like to schedule a 30-minute interview next week.",
                     receivedAt: minutesAgo(12), importance: .high, actionRequired: true, section: .needsAction),
        InboxMessage(id: "m2", sender: "Career Services", subject: "Additional documentation requested",
                     aiSummary: "Upload an updated resume and transcript.",
                     receivedAt: minutesAgo(60), importance: .high, actionRequired: true, section: .needsAction),
        InboxMessage(id: "m3", sender: "Northwind Talent", subject: "Technical screen confirmed",
                     aiSummary: "Your screen is confirmed for tomorrow at 10:00 AM.",
                     receivedAt: minutesAgo(180), importance: .normal, actionRequired: false, section: .jobs),
        InboxMessage(id: "m4", sender: "LinkedIn", subject: "5 new jobs for you",
                     aiSummary: "Weekly job recommendations digest.",
                     receivedAt: minutesAgo(400), importance: .low, actionRequired: false, section: .everythingElse)
    ]

    static let events: [CalendarEvent] = [
        CalendarEvent(id: "e1", title: "Interview — Northwind", start: hoursFromNow(20), end: hoursFromNow(20.75),
                      location: "Google Meet", isImportant: true),
        CalendarEvent(id: "e2", title: "Class — Systems Design", start: hoursFromNow(25.5), end: hoursFromNow(27)),
        CalendarEvent(id: "e3", title: "Follow-up deadline — Vertex", start: hoursFromNow(29), isImportant: true)
    ]

    static let health = HealthSummary(metrics: [
        HealthMetric(id: "sleep", title: "Sleep", value: "7h 21m", systemImage: "bed.double"),
        HealthMetric(id: "steps", title: "Steps", value: "8,421", systemImage: "figure.walk"),
        HealthMetric(id: "workout", title: "Workout", value: "Completed", systemImage: "flame")
    ], isConnected: true)

    static func jobs() -> [JobApplication] {
        [
            sample(1, "ARCO Design/Build", "Project Engineer", .interview, "Reply to recruiter about availability"),
            sample(2, "Northwind", "Software Engineer", .screening, "Prepare for technical screen"),
            sample(3, "Vertex", "iOS Developer", .applied, "Follow up — no response in 9 days"),
            sample(4, "Helios Labs", "Backend Engineer", .offer, "Review offer details")
        ]
    }

    private static func sample(_ id: Int, _ company: String, _ role: String, _ status: JobStatus, _ action: String) -> JobApplication {
        let app = JobApplication(id: id, company: company, role: role, stage: status.rawValue,
                                 status: status, nextAction: action)
        return app
    }
}

import Foundation
import SwiftData
import SwiftUI

// MARK: - Job application model

/// A tracked job application.
///
/// Storage-level property names are kept stable for SwiftData + backend
/// compatibility; the richer field names from the product spec are exposed as
/// computed aliases so the rest of the app can use clear vocabulary.
@Model
final class JobApplication: Identifiable {
    @Attribute(.unique) var id: Int
    var company: String
    /// Stored as `role`; exposed as `position`.
    var role: String
    var stage: String
    var inviteDate: Date?
    var interviewDate: Date?
    var statusRaw: String
    var priorityRaw: String
    var nextAction: String
    var followUpDate: Date?
    /// Stored as `contact`; exposed as `recruiterName`.
    var contact: String
    /// Stored as `mode`; exposed as `location`.
    var mode: String
    var notes: String
    var updatedAt: Date

    // Richer fields (local-only until the backend contract is extended)
    var recruiterEmail: String = ""
    var source: String = ""
    var jobURL: String = ""
    var dateApplied: Date?
    var createdAt: Date = Date.now
    var relatedEmailThreadIDs: [String] = []
    var interviewDates: [Date] = []

    init(
        id: Int = Int(Date().timeIntervalSince1970),
        company: String = "",
        role: String = "",
        stage: String = "",
        inviteDate: Date? = nil,
        interviewDate: Date? = nil,
        status: JobStatus = .applied,
        priority: JobPriority = .medium,
        nextAction: String = "",
        followUpDate: Date? = nil,
        contact: String = "",
        mode: String = "",
        notes: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.company = company
        self.role = role
        self.stage = stage
        self.inviteDate = inviteDate
        self.interviewDate = interviewDate
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.nextAction = nextAction
        self.followUpDate = followUpDate
        self.contact = contact
        self.mode = mode
        self.notes = notes
        self.updatedAt = updatedAt
        self.createdAt = .now
    }

    // Spec-facing aliases over stable storage
    var position: String {
        get { role }
        set { role = newValue }
    }
    var location: String {
        get { mode }
        set { mode = newValue }
    }
    var recruiterName: String {
        get { contact }
        set { contact = newValue }
    }
    var nextActionDate: Date? {
        get { followUpDate }
        set { followUpDate = newValue }
    }
    var lastActivityDate: Date { updatedAt }

    var status: JobStatus {
        get { JobStatus(normalizing: statusRaw) }
        set { statusRaw = newValue.rawValue }
    }

    var priority: JobPriority {
        get { JobPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var isClosed: Bool { status.isClosed }
    var initials: String {
        company.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

// MARK: - Status

enum JobStatus: String, Codable, CaseIterable, Identifiable {
    case saved = "Saved"
    case applied = "Applied"
    case recruiterContact = "Recruiter Contact"
    case screening = "Screening"
    case interview = "Interview"
    case finalInterview = "Final Interview"
    case offer = "Offer"
    case rejected = "Rejected"
    case withdrawn = "Withdrawn"
    case closed = "Closed"

    var id: String { rawValue }

    /// Lenient parser that maps both current and legacy backend status strings
    /// onto the new status set, so existing synced data keeps working.
    init(normalizing raw: String) {
        if let direct = JobStatus(rawValue: raw) {
            self = direct
            return
        }
        switch raw {
        case "Interview Requested", "Interview Scheduled", "Interview Completed":
            self = .interview
        case "Assessment / Next Round":
            self = .screening
        case "Awaiting Response", "Need Status Update":
            self = .applied
        case "Offer Received", "Offer Accepted / Active":
            self = .offer
        case "Rejected":
            self = .rejected
        case "Withdrawn":
            self = .withdrawn
        default:
            self = .applied
        }
    }

    var isClosed: Bool { [.rejected, .withdrawn, .closed].contains(self) }
    var isOffer: Bool { self == .offer }
    var isActive: Bool { !isClosed }

    /// SF Symbol representing the stage. Restrained, monochrome by default.
    var systemImage: String {
        switch self {
        case .saved: "bookmark"
        case .applied: "paperplane"
        case .recruiterContact: "person.wave.2"
        case .screening: "text.magnifyingglass"
        case .interview: "person.2"
        case .finalInterview: "star"
        case .offer: "checkmark.seal"
        case .rejected: "xmark.circle"
        case .withdrawn: "arrow.uturn.backward"
        case .closed: "archivebox"
        }
    }

    /// Restrained semantic tint. Most statuses use neutral text; only genuinely
    /// meaningful states get a semantic color (offer = success, negative = red).
    var tint: Color {
        switch self {
        case .offer: AppTheme.success
        case .rejected, .withdrawn: AppTheme.destructive
        case .closed: AppTheme.tertiaryText
        case .interview, .finalInterview: AppTheme.primaryText
        default: AppTheme.secondaryText
        }
    }
}

enum JobPriority: String, Codable, CaseIterable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    var id: String { rawValue }
}

// MARK: - Backend transfer object

/// Wire format for the existing `/api/tracker` backend. Keys are kept exactly
/// as the backend expects; new local-only fields are not transmitted.
struct JobApplicationDTO: Codable, Identifiable {
    let id: Int
    let company: String
    let role: String
    let stage: String
    let inviteDate: String?
    let interviewDate: String?
    let status: String
    let priority: String
    let nextAction: String
    let followUpDate: String?
    let contact: String
    let mode: String
    let notes: String

    init(model: JobApplication) {
        id = model.id
        company = model.company
        role = model.role
        stage = model.stage
        inviteDate = Self.encodeDate(model.inviteDate)
        interviewDate = Self.encodeDate(model.interviewDate)
        status = model.status.rawValue
        priority = model.priorityRaw
        nextAction = model.nextAction
        followUpDate = Self.encodeDate(model.followUpDate)
        contact = model.contact
        mode = model.mode
        notes = model.notes
    }

    private static func encodeDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return DateFormatters.api.string(from: date)
    }
}

enum DateFormatters {
    static let api: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

import Foundation
import SwiftData

@Model
final class JobApplication: Identifiable {
    @Attribute(.unique) var id: Int
    var company: String
    var role: String
    var stage: String
    var inviteDate: Date?
    var interviewDate: Date?
    var statusRaw: String
    var priorityRaw: String
    var nextAction: String
    var followUpDate: Date?
    var contact: String
    var mode: String
    var notes: String
    var updatedAt: Date

    init(
        id: Int = Int(Date().timeIntervalSince1970),
        company: String = "",
        role: String = "",
        stage: String = "Recruiter Screen",
        inviteDate: Date? = nil,
        interviewDate: Date? = nil,
        status: JobStatus = .interviewRequested,
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
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .needsUpdate }
        set { statusRaw = newValue.rawValue }
    }

    var priority: JobPriority {
        get { JobPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var isClosed: Bool { status.isClosed }
}

enum JobStatus: String, Codable, CaseIterable, Identifiable {
    case interviewRequested = "Interview Requested"
    case interviewScheduled = "Interview Scheduled"
    case interviewCompleted = "Interview Completed"
    case assessment = "Assessment / Next Round"
    case awaitingResponse = "Awaiting Response"
    case offerReceived = "Offer Received"
    case active = "Offer Accepted / Active"
    case rejected = "Rejected"
    case withdrawn = "Withdrawn"
    case needsUpdate = "Need Status Update"

    var id: String { rawValue }
    var isClosed: Bool { [.active, .rejected, .withdrawn].contains(self) }
    var isOffer: Bool { [.offerReceived, .active].contains(self) }
}

enum JobPriority: String, Codable, CaseIterable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    var id: String { rawValue }
}

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
        status = model.statusRaw
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

import SwiftUI

extension Color {
    static let radarInk = Color(hex: 0x0D1B2A)
    static let radarNight = Color(hex: 0x10263B)
    static let radarCanvas = Color(hex: 0xF3F5F4)
    static let radarMint = Color(hex: 0x39D98A)
    static let radarAmber = Color(hex: 0xFFB84D)
    static let radarRed = Color(hex: 0xFF6673)
    static let radarBlue = Color(hex: 0x5A8BFF)

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension JobStatus {
    var color: Color {
        switch self {
        case .offerReceived, .active: .radarMint
        case .rejected, .withdrawn: .radarRed
        case .needsUpdate: .radarAmber
        default: .radarBlue
        }
    }

    var compactTitle: String {
        switch self {
        case .interviewRequested: "Requested"
        case .interviewScheduled: "Scheduled"
        case .interviewCompleted: "Completed"
        case .assessment: "Next round"
        case .awaitingResponse: "Waiting"
        case .offerReceived: "Offer"
        case .active: "Active"
        case .rejected: "Rejected"
        case .withdrawn: "Withdrawn"
        case .needsUpdate: "Needs update"
        }
    }
}

struct RadarPulse: View {
    var color: Color = .radarMint
    @State private var expands = false

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 1).scaleEffect(expands ? 1.35 : 0.65).opacity(expands ? 0 : 1)
            Circle().stroke(color.opacity(0.30), lineWidth: 1)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { expands = true }
        }
    }
}

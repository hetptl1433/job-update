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

enum InboxSection: String, Codable, CaseIterable, Identifiable {
    case needsAction = "Needs Action"
    case important = "Important"
    case jobs = "Jobs"
    case everythingElse = "Everything Else"
    var id: String { rawValue }
}

/// AI-classified provider-neutral mail. Provider API payloads are normalized
/// before the Inbox, Home, Tasks, Jobs, or Assistant consumes them.
struct InboxMessage: Identifiable, Codable, Hashable {
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

struct HealthTrendPoint: Identifiable, Hashable {
    var date: Date
    var value: Double

    var id: Date { date }
}

enum HealthTimeRange: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case sevenDays = "7 Days"

    var id: String { rawValue }
}

/// Numeric HealthKit series identifiers. Presentation metadata lives here so
/// every health surface formats the same underlying value consistently.
enum HealthTrendMetric: String, CaseIterable, Identifiable, Hashable {
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    case cardioFitness
    case walkingHeartRateAverage
    case heartRateRecovery
    case walkingSpeed
    case walkingStepLength
    case walkingAsymmetry
    case walkingDoubleSupport
    case walkingSteadiness
    case bodyMass
    case bodyMassIndex
    case bodyFatPercentage
    case mindfulMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heartRate: "Heart Rate"
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRateVariability: "Heart Rate Variability"
        case .respiratoryRate: "Respiratory Rate"
        case .oxygenSaturation: "Blood Oxygen"
        case .wristTemperature: "Wrist Temperature"
        case .cardioFitness: "Cardio Fitness"
        case .walkingHeartRateAverage: "Walking Heart Rate"
        case .heartRateRecovery: "Heart Rate Recovery"
        case .walkingSpeed: "Walking Speed"
        case .walkingStepLength: "Walking Step Length"
        case .walkingAsymmetry: "Walking Asymmetry"
        case .walkingDoubleSupport: "Walking Double Support"
        case .walkingSteadiness: "Walking Steadiness"
        case .bodyMass: "Weight"
        case .bodyMassIndex: "Body Mass Index"
        case .bodyFatPercentage: "Body Fat"
        case .mindfulMinutes: "Mindful Minutes"
        }
    }

    var unit: String {
        switch self {
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery: "bpm"
        case .heartRateVariability: "ms"
        case .respiratoryRate: "/min"
        case .oxygenSaturation, .walkingAsymmetry, .walkingDoubleSupport,
             .walkingSteadiness, .bodyFatPercentage: "%"
        case .wristTemperature: "°F"
        case .cardioFitness: "VO₂ max"
        case .walkingSpeed: "mph"
        case .walkingStepLength: "in"
        case .bodyMass: "lb"
        case .bodyMassIndex: "BMI"
        case .mindfulMinutes: "min"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .respiratoryRate, .wristTemperature, .cardioFitness,
             .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport,
             .bodyFatPercentage, .bodyMass, .bodyMassIndex: 1
        case .walkingSpeed: 2
        default: 0
        }
    }
}

struct HealthMetricSeries: Identifiable, Hashable {
    var metric: HealthTrendMetric
    var points: [HealthTrendPoint]

    var id: HealthTrendMetric { metric }

    var latest: HealthTrendPoint? {
        points.max { $0.date < $1.date }
    }

    func points(
        for range: HealthTimeRange,
        relativeTo date: Date = .now,
        calendar: Calendar = .current
    ) -> [HealthTrendPoint] {
        let end = date
        let start: Date
        switch range {
        case .today:
            start = calendar.startOfDay(for: date)
        case .sevenDays:
            let today = calendar.startOfDay(for: date)
            start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        }
        return points
            .filter { $0.date >= start && $0.date <= end && $0.value.isFinite }
            .sorted { $0.date < $1.date }
    }
}

enum HealthSleepStage: String, CaseIterable, Hashable {
    case awake
    case rem
    case core
    case deep
    case unspecified
}

struct HealthSleepStageSegment: Identifiable, Hashable {
    var stage: HealthSleepStage
    var startDate: Date
    var endDate: Date

    var id: String {
        "\(stage.rawValue):\(startDate.timeIntervalSinceReferenceDate):\(endDate.timeIntervalSinceReferenceDate)"
    }

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
}

struct HealthSleepNight: Identifiable, Hashable {
    /// Calendar day on which the noon-to-noon main-sleep window ends, matching
    /// the morning date people normally associate with an overnight sleep.
    var sleepDay: Date
    var startDate: Date
    var endDate: Date
    var asleepDuration: TimeInterval
    var inBedDuration: TimeInterval?
    var awakeDuration: TimeInterval
    var remDuration: TimeInterval
    var coreDuration: TimeInterval
    var deepDuration: TimeInterval
    var unspecifiedDuration: TimeInterval
    var awakenings: Int
    var stageSegments: [HealthSleepStageSegment]
    var sourceName: String? = nil

    var id: Date { sleepDay }

    /// Sleep efficiency is available only when HealthKit supplied a coherent
    /// in-bed duration. Invalid or mismatched source data remains unavailable.
    var efficiency: Double? {
        guard let inBedDuration,
              inBedDuration.isFinite,
              asleepDuration.isFinite,
              inBedDuration > 0,
              asleepDuration >= 0,
              asleepDuration <= inBedDuration else { return nil }
        return (asleepDuration / inBedDuration) * 100
    }
}

struct HealthMindfulnessSummary: Hashable {
    var todayMinutes: Double
    var sevenDayMinutes: Double
    var sevenDaySessions: Int
    var latestSessionDate: Date
}

struct HealthSummary: Hashable {
    var metrics: [HealthMetric]
    var isConnected: Bool
    var updatedAt: Date = .now
    var steps: Double?
    var activeEnergyKilocalories: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var moveGoalKilocalories: Double?
    var exerciseGoalMinutes: Double?
    var standGoalHours: Double?
    var walkingRunningDistanceMiles: Double?
    var flightsClimbed: Double?
    var stepTrend: [HealthTrendPoint] = []
    var activeEnergyTrend: [HealthTrendPoint] = []
    var exerciseTrend: [HealthTrendPoint] = []
    var latestHeartRate: Double?
    var latestHeartRateDate: Date?
    var restingHeartRate: Double?
    var restingHeartRateDate: Date?
    var heartRateVariability: Double?
    var heartRateVariabilityDate: Date?
    var respiratoryRate: Double?
    var respiratoryRateDate: Date?
    var oxygenSaturation: Double?
    var oxygenSaturationDate: Date?
    var wristTemperatureFahrenheit: Double?
    var wristTemperatureDate: Date?
    var cardioFitness: Double?
    var cardioFitnessDate: Date?
    var walkingHeartRateAverage: Double?
    var walkingHeartRateAverageDate: Date?
    var heartRateRecovery: Double?
    var heartRateRecoveryDate: Date?
    var walkingSpeedMilesPerHour: Double?
    var walkingSpeedDate: Date?
    var walkingStepLengthInches: Double?
    var walkingStepLengthDate: Date?
    var walkingAsymmetryPercentage: Double?
    var walkingAsymmetryDate: Date?
    var walkingDoubleSupportPercentage: Double?
    var walkingDoubleSupportDate: Date?
    var walkingSteadinessPercentage: Double?
    var walkingSteadinessDate: Date?
    var bodyMassPounds: Double?
    var bodyMassDate: Date?
    var bodyMassIndex: Double?
    var bodyMassIndexDate: Date?
    var bodyFatPercentage: Double?
    var bodyFatDate: Date?
    var sleepDuration: TimeInterval?
    var sleepEndDate: Date?
    var awakeDuration: TimeInterval?
    var remDuration: TimeInterval?
    var coreDuration: TimeInterval?
    var deepDuration: TimeInterval?
    var latestWorkout: HealthWorkoutSummary?
    var workouts: [HealthWorkoutSummary] = []
    var mindfulness: HealthMindfulnessSummary?
    var metricSeries: [HealthMetricSeries] = []
    var sleepHistory: [HealthSleepNight] = []

    func trend(for metric: HealthTrendMetric) -> HealthMetricSeries? {
        metricSeries.first { $0.metric == metric }
    }

    func trend(
        for metric: HealthTrendMetric,
        range: HealthTimeRange,
        relativeTo date: Date = .now,
        calendar: Calendar = .current
    ) -> [HealthTrendPoint] {
        trend(for: metric)?.points(for: range, relativeTo: date, calendar: calendar) ?? []
    }

    var sleepScore: Int? {
        guard let sleepDuration, sleepDuration > 0 else { return nil }
        return min(100, max(0, Int((sleepDuration / (8 * 3600)) * 100)))
    }

    var activityScore: Int? {
        let values = [
            steps.map { min($0 / 10_000, 1) },
            activeEnergyKilocalories.map { min($0 / max(moveGoalKilocalories ?? 600, 1), 1) },
            exerciseMinutes.map { min($0 / max(exerciseGoalMinutes ?? 30, 1), 1) },
            standHours.map { min($0 / max(standGoalHours ?? 12, 1), 1) }
        ].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)) * 100)
    }

    /// A transparent daily balance indicator based only on today's sleep and
    /// movement coverage. It is not a medical score or a diagnosis.
    var dailyBalanceScore: Int? {
        let values = [sleepScore, activityScore].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    var hasRecentData: Bool {
        !metrics.isEmpty || [
            steps, activeEnergyKilocalories, exerciseMinutes, standHours,
            walkingRunningDistanceMiles, flightsClimbed, latestHeartRate,
            restingHeartRate, heartRateVariability, respiratoryRate,
            oxygenSaturation, wristTemperatureFahrenheit, cardioFitness,
            walkingHeartRateAverage, heartRateRecovery, walkingSpeedMilesPerHour,
            walkingStepLengthInches, walkingAsymmetryPercentage,
            walkingDoubleSupportPercentage, walkingSteadinessPercentage,
            bodyMassPounds, bodyMassIndex, bodyFatPercentage, sleepDuration
        ].contains(where: { $0 != nil }) || latestWorkout != nil || mindfulness != nil
    }

    var availableSignalCount: Int {
        [
            steps, activeEnergyKilocalories, exerciseMinutes, standHours,
            walkingRunningDistanceMiles, flightsClimbed, latestHeartRate,
            restingHeartRate, heartRateVariability, respiratoryRate,
            oxygenSaturation, wristTemperatureFahrenheit, cardioFitness,
            walkingHeartRateAverage, heartRateRecovery, walkingSpeedMilesPerHour,
            walkingStepLengthInches, walkingAsymmetryPercentage,
            walkingDoubleSupportPercentage, walkingSteadinessPercentage,
            bodyMassPounds, bodyMassIndex, bodyFatPercentage, sleepDuration
        ].compactMap { $0 }.count
            + (latestWorkout == nil ? 0 : 1)
            + (mindfulness == nil ? 0 : 1)
    }

    func analytics(
        relativeTo date: Date = .now,
        calendar: Calendar = .current
    ) -> HealthAnalyticsResult {
        HealthAnalytics.analyze(self, relativeTo: date, calendar: calendar)
    }
}

enum HealthOverallDirection: String, Hashable {
    case building
    case steady
    case upward
    case downward
    case mixed
}

struct HealthTrendComparison: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var currentAverage: Double
    var previousAverage: Double
    var unit: String
    var percentChange: Double
}

struct HealthOverallTrend: Hashable {
    var direction: HealthOverallDirection
    var title: String
    var detail: String
    var comparisons: [HealthTrendComparison]

    var hasComparison: Bool { !comparisons.isEmpty }
}

enum HealthLoadLevel: String, Hashable {
    case collecting
    case lowerThanUsual
    case typical
    case higherThanUsual

    var title: String {
        switch self {
        case .collecting: "Building your baseline"
        case .lowerThanUsual: "Lower than usual"
        case .typical: "Near your baseline"
        case .higherThanUsual: "Higher than usual"
        }
    }
}

enum HealthLoadConfidence: String, Hashable {
    case low
    case medium
    case high
}

enum HealthLoadFactorState: String, Hashable {
    case addsLoad
    case nearBaseline
    case reducesLoad
}

struct HealthLoadFactor: Identifiable, Hashable {
    var id: String
    var title: String
    var currentValue: Double
    var baselineValue: Double
    var unit: String
    var percentDifference: Double
    var normalizedDeviation: Double
    var baselineDays: Int
    var state: HealthLoadFactorState
}

/// A transparent, non-diagnostic estimate derived locally from changes against
/// the owner's own recorded baseline. It does not measure psychological stress.
struct HealthLoadEstimate: Hashable {
    var level: HealthLoadLevel
    var index: Int?
    var confidence: HealthLoadConfidence?
    var factors: [HealthLoadFactor]
    var detail: String

    var isAvailable: Bool { index != nil }
}

struct HealthAnalyticsResult: Hashable {
    var overallTrend: HealthOverallTrend
    var bodyLoad: HealthLoadEstimate
}

enum HealthAnalytics {
    private struct LoadSpec {
        var id: String
        var title: String
        var metric: HealthTrendMetric?
        var unit: String
        var weight: Double
        var direction: Double
        var minimumScale: Double
        var isCore: Bool
        var usesAbsoluteDeviation: Bool = false
    }

    static func analyze(
        _ summary: HealthSummary,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> HealthAnalyticsResult {
        HealthAnalyticsResult(
            overallTrend: overallTrend(summary, relativeTo: now, calendar: calendar),
            bodyLoad: bodyLoad(summary, relativeTo: now, calendar: calendar)
        )
    }

    private static func overallTrend(
        _ summary: HealthSummary,
        relativeTo now: Date,
        calendar: Calendar
    ) -> HealthOverallTrend {
        let today = calendar.startOfDay(for: now)
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -14, to: today) ?? recentStart

        var comparisons: [HealthTrendComparison] = []
        appendComparison(
            title: "Steps",
            unit: "steps",
            points: summary.stepTrend,
            recentStart: recentStart,
            previousStart: previousStart,
            end: today,
            to: &comparisons
        )
        appendComparison(
            title: "Active energy",
            unit: "kcal",
            points: summary.activeEnergyTrend,
            recentStart: recentStart,
            previousStart: previousStart,
            end: today,
            to: &comparisons
        )
        appendComparison(
            title: "Exercise",
            unit: "min",
            points: summary.exerciseTrend,
            recentStart: recentStart,
            previousStart: previousStart,
            end: today,
            to: &comparisons
        )

        let sleepPoints = summary.sleepHistory.map {
            HealthTrendPoint(date: $0.sleepDay, value: $0.asleepDuration / 3600)
        }
        appendComparison(
            title: "Sleep",
            unit: "hr",
            points: sleepPoints,
            recentStart: recentStart,
            previousStart: previousStart,
            end: today,
            to: &comparisons
        )

        guard !comparisons.isEmpty else {
            return HealthOverallTrend(
                direction: .building,
                title: "Building your weekly trend",
                detail: "Orbit needs recorded days in both this week and the previous week before it can compare patterns.",
                comparisons: []
            )
        }

        let meaningful = comparisons.filter { abs($0.percentChange) >= 5 }
        let hasUp = meaningful.contains { $0.percentChange > 0 }
        let hasDown = meaningful.contains { $0.percentChange < 0 }
        let direction: HealthOverallDirection
        let title: String
        if meaningful.isEmpty {
            direction = .steady
            title = "Your weekly pattern is steady"
        } else if hasUp && hasDown {
            direction = .mixed
            title = "Your weekly pattern is mixed"
        } else if hasUp {
            direction = .upward
            title = "Recorded totals are trending up"
        } else {
            direction = .downward
            title = "Recorded totals are trending down"
        }

        let detail = comparisons.prefix(2).map { comparison in
            let direction = comparison.percentChange >= 0 ? "up" : "down"
            return "\(comparison.title) \(direction) \(abs(Int(comparison.percentChange.rounded())))%"
        }.joined(separator: " · ")

        return HealthOverallTrend(
            direction: direction,
            title: title,
            detail: detail + ". Comparisons use recorded completed days, not medical targets.",
            comparisons: comparisons
        )
    }

    private static func appendComparison(
        title: String,
        unit: String,
        points: [HealthTrendPoint],
        recentStart: Date,
        previousStart: Date,
        end: Date,
        to result: inout [HealthTrendComparison]
    ) {
        let recent = points.filter { $0.date >= recentStart && $0.date < end && $0.value.isFinite }
        let previous = points.filter { $0.date >= previousStart && $0.date < recentStart && $0.value.isFinite }
        guard recent.count >= 3, previous.count >= 3 else { return }
        let currentAverage = recent.reduce(0) { $0 + $1.value } / Double(recent.count)
        let previousAverage = previous.reduce(0) { $0 + $1.value } / Double(previous.count)
        guard previousAverage.isFinite, abs(previousAverage) > .ulpOfOne else { return }
        result.append(HealthTrendComparison(
            title: title,
            currentAverage: currentAverage,
            previousAverage: previousAverage,
            unit: unit,
            percentChange: (currentAverage - previousAverage) / abs(previousAverage) * 100
        ))
    }

    private static func bodyLoad(
        _ summary: HealthSummary,
        relativeTo now: Date,
        calendar: Calendar
    ) -> HealthLoadEstimate {
        let specs = [
            LoadSpec(id: "hrv", title: "Heart rate variability", metric: .heartRateVariability, unit: "ms", weight: 0.35, direction: -1, minimumScale: 5, isCore: true),
            LoadSpec(id: "resting-heart", title: "Resting heart rate", metric: .restingHeartRate, unit: "bpm", weight: 0.25, direction: 1, minimumScale: 3, isCore: true),
            LoadSpec(id: "respiratory", title: "Respiratory rate", metric: .respiratoryRate, unit: "/min", weight: 0.15, direction: 1, minimumScale: 0.75, isCore: true),
            LoadSpec(id: "sleep", title: "Sleep duration", metric: nil, unit: "hr", weight: 0.15, direction: -1, minimumScale: 0.5, isCore: false),
            LoadSpec(id: "temperature", title: "Wrist temperature", metric: .wristTemperature, unit: "°F", weight: 0.10, direction: 1, minimumScale: 0.2, isCore: false, usesAbsoluteDeviation: true)
        ]
        let today = calendar.startOfDay(for: now)
        let baselineStart = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        var factors: [HealthLoadFactor] = []
        var weightedDeviation = 0.0
        var availableWeight = 0.0
        var coreCount = 0

        for spec in specs {
            let currentAndBaseline: (Double, [Double])?
            if let metric = spec.metric {
                guard let series = summary.trend(for: metric) else { continue }
                let valid = series.points.filter { $0.value.isFinite }
                let current = valid
                    .filter { $0.date >= today && $0.date <= now }
                    .max { $0.date < $1.date }
                    ?? valid
                    .filter { $0.date >= (calendar.date(byAdding: .day, value: -2, to: today) ?? today) && $0.date < today }
                    .max { $0.date < $1.date }
                if let current {
                    let currentDay = calendar.startOfDay(for: current.date)
                    let baseline = valid
                        .filter { point in
                            point.date >= baselineStart
                                && point.date < today
                                && calendar.startOfDay(for: point.date) != currentDay
                        }
                        .map(\.value)
                    currentAndBaseline = (current.value, baseline)
                } else {
                    currentAndBaseline = nil
                }
            } else {
                let currentNight = summary.sleepHistory
                    .filter { $0.endDate >= (calendar.date(byAdding: .day, value: -2, to: now) ?? now) && $0.endDate <= now }
                    .max { $0.endDate < $1.endDate }
                let baseline = summary.sleepHistory
                    .filter {
                        $0.sleepDay >= baselineStart
                            && $0.sleepDay < today
                            && $0.id != currentNight?.id
                    }
                    .map { $0.asleepDuration / 3600 }
                    .filter(\.isFinite)
                currentAndBaseline = currentNight.map { ($0.asleepDuration / 3600, baseline) }
            }

            guard let (current, baselineValues) = currentAndBaseline,
                  current.isFinite,
                  baselineValues.count >= 7 else { continue }
            let baseline = median(baselineValues)
            let deviations = baselineValues.map { abs($0 - baseline) }
            let robustScale = max(1.4826 * median(deviations), spec.minimumScale)
            guard robustScale.isFinite, robustScale > 0 else { continue }
            let signedDifference = current - baseline
            var normalized = signedDifference / robustScale * spec.direction
            if spec.usesAbsoluteDeviation { normalized = abs(signedDifference) / robustScale }
            normalized = min(max(normalized, -2.5), 2.5)
            let percent = abs(baseline) > .ulpOfOne ? signedDifference / abs(baseline) * 100 : 0
            let state: HealthLoadFactorState = normalized > 0.5
                ? .addsLoad
                : normalized < -0.5 ? .reducesLoad : .nearBaseline
            factors.append(HealthLoadFactor(
                id: spec.id,
                title: spec.title,
                currentValue: current,
                baselineValue: baseline,
                unit: spec.unit,
                percentDifference: percent,
                normalizedDeviation: normalized,
                baselineDays: baselineValues.count,
                state: state
            ))
            weightedDeviation += normalized * spec.weight
            availableWeight += spec.weight
            if spec.isCore { coreCount += 1 }
        }

        guard coreCount >= 2, availableWeight > 0 else {
            return HealthLoadEstimate(
                level: .collecting,
                index: nil,
                confidence: nil,
                factors: factors,
                detail: "Keep wearing Apple Watch. Orbit needs at least seven baseline days for two of HRV, resting heart rate, and respiratory rate."
            )
        }

        let normalized = weightedDeviation / availableWeight
        let index = Int(min(max(50 + normalized * 15, 0), 100).rounded())
        let level: HealthLoadLevel = index >= 59 ? .higherThanUsual : index <= 41 ? .lowerThanUsual : .typical
        let minimumDays = factors.map(\.baselineDays).min() ?? 0
        let confidence: HealthLoadConfidence = factors.count >= 4 && minimumDays >= 14
            ? .high
            : factors.count >= 3 && minimumDays >= 10 ? .medium : .low
        let notable = factors.filter { $0.state != .nearBaseline }.count

        return HealthLoadEstimate(
            level: level,
            index: index,
            confidence: confidence,
            factors: factors.sorted { abs($0.normalizedDeviation) > abs($1.normalizedDeviation) },
            detail: "Compared with your own recent baseline from up to 28 prior calendar days using \(factors.count) signals; \(notable) currently differ meaningfully from baseline."
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

struct HealthWorkoutSummary: Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var energyKilocalories: Double?
    var distanceMiles: Double?
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

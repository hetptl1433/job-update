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
        InboxMessage(id: "m1", provider: .gmail, accountID: "gmail:1", accountEmail: "het@example.com", senderName: "ARCO Design/Build", senderEmail: "recruiting@arco.example", subject: "Interview availability",
                     aiSummary: "They'd like to schedule a 30-minute interview next week.",
                     receivedAt: minutesAgo(12), importance: .high, actionRequired: true, section: .needsAction),
        InboxMessage(id: "m2", provider: .gmail, accountID: "gmail:1", accountEmail: "het@example.com", senderName: "Career Services", senderEmail: "careers@example.edu", subject: "Additional documentation requested",
                     aiSummary: "Upload an updated resume and transcript.",
                     receivedAt: minutesAgo(60), importance: .high, actionRequired: true, section: .needsAction),
        InboxMessage(id: "m3", provider: .outlook, accountID: "outlook:1", accountEmail: "jobs@example.com", senderName: "Northwind Talent", senderEmail: "talent@northwind.example", subject: "Technical screen confirmed",
                     aiSummary: "Your screen is confirmed for tomorrow at 10:00 AM.",
                     receivedAt: minutesAgo(180), importance: .normal, actionRequired: false, section: .jobs),
        InboxMessage(id: "m4", provider: .outlook, accountID: "outlook:1", accountEmail: "jobs@example.com", senderName: "LinkedIn", senderEmail: "jobs@linkedin.example", subject: "5 new jobs for you",
                     aiSummary: "Weekly job recommendations digest.",
                     receivedAt: minutesAgo(400), importance: .low, actionRequired: false, section: .everythingElse)
    ]

    static let events: [CalendarEvent] = [
        CalendarEvent(id: "e1", provider: .google, calendarID: "primary", title: "Interview — Northwind", start: hoursFromNow(20), end: hoursFromNow(20.75),
                      location: "Google Meet", notes: nil, meetingURL: nil, isAllDay: false, relatedJobApplicationID: nil, isImportant: true),
        CalendarEvent(id: "e2", provider: .outlook, calendarID: "work", title: "Class — Systems Design", start: hoursFromNow(25.5), end: hoursFromNow(27), location: nil, notes: nil, meetingURL: nil, isAllDay: false, relatedJobApplicationID: nil),
        CalendarEvent(id: "e3", provider: .apple, calendarID: "local", title: "Follow-up deadline — Vertex", start: hoursFromNow(29), end: nil, location: nil, notes: nil, meetingURL: nil, isAllDay: false, relatedJobApplicationID: nil, isImportant: true)
    ]

    static let health = HealthSummary(metrics: [
        HealthMetric(id: "sleep", title: "Sleep", value: "7h 21m", systemImage: "bed.double"),
        HealthMetric(id: "steps", title: "Steps", value: "8,421", systemImage: "figure.walk"),
        HealthMetric(id: "workout", title: "Workout", value: "Completed", systemImage: "flame")
    ], isConnected: true,
       steps: 8_421,
       activeEnergyKilocalories: 482,
       exerciseMinutes: 32,
       standHours: 9,
       moveGoalKilocalories: 620,
       exerciseGoalMinutes: 35,
       standGoalHours: 12,
       walkingRunningDistanceMiles: 4.2,
       flightsClimbed: 8,
       stepTrend: mockDailyTrend([
           7_100, 6_800, 8_050, 7_420, 9_250, 6_940, 7_780,
           6_230, 9_120, 7_845, 10_432, 5_980, 8_760, 9_040, 8_421
       ]),
       activeEnergyTrend: mockDailyTrend([
           420, 405, 476, 438, 544, 401, 465,
           410, 588, 462, 635, 372, 524, 541, 482
       ]),
       exerciseTrend: mockDailyTrend([
           24, 18, 31, 27, 39, 20, 34,
           22, 41, 28, 48, 16, 36, 40, 32
       ]),
       latestHeartRate: 62,
       latestHeartRateDate: minutesAgo(2),
       restingHeartRate: 54,
       restingHeartRateDate: hoursFromNow(-9),
       heartRateVariability: 58,
       heartRateVariabilityDate: hoursFromNow(-9),
       respiratoryRate: 14.2,
       respiratoryRateDate: hoursFromNow(-8),
       oxygenSaturation: 97,
       oxygenSaturationDate: hoursFromNow(-8),
       wristTemperatureFahrenheit: 96.8,
       wristTemperatureDate: hoursFromNow(-8),
       cardioFitness: 42.8,
       cardioFitnessDate: hoursFromNow(-30),
       walkingHeartRateAverage: 91,
       walkingHeartRateAverageDate: hoursFromNow(-5),
       heartRateRecovery: 27,
       heartRateRecoveryDate: hoursFromNow(-26),
       walkingSpeedMilesPerHour: 3.1,
       walkingSpeedDate: hoursFromNow(-4),
       walkingStepLengthInches: 27.4,
       walkingStepLengthDate: hoursFromNow(-4),
       walkingAsymmetryPercentage: 1.8,
       walkingAsymmetryDate: hoursFromNow(-4),
       walkingDoubleSupportPercentage: 24.1,
       walkingDoubleSupportDate: hoursFromNow(-4),
       walkingSteadinessPercentage: 93,
       walkingSteadinessDate: hoursFromNow(-20),
       bodyMassPounds: 168.4,
       bodyMassDate: hoursFromNow(-48),
       bodyMassIndex: 23.5,
       bodyMassIndexDate: hoursFromNow(-48),
       bodyFatPercentage: 18.2,
       bodyFatDate: hoursFromNow(-48),
       sleepDuration: 26_460,
       sleepEndDate: hoursFromNow(-3),
       awakeDuration: 1_320,
       remDuration: 5_640,
       coreDuration: 15_900,
       deepDuration: 4_920,
       latestWorkout: HealthWorkoutSummary(
           title: "Outdoor Run",
           startedAt: hoursFromNow(-26),
           duration: 2_040,
           energyKilocalories: 286,
           distanceMiles: 3.1
       ),
       workouts: [
           HealthWorkoutSummary(
               title: "Outdoor Run",
               startedAt: hoursFromNow(-26),
               duration: 2_040,
               energyKilocalories: 286,
               distanceMiles: 3.1
           ),
           HealthWorkoutSummary(
               title: "Traditional Strength Training",
               startedAt: hoursFromNow(-74),
               duration: 2_760,
               energyKilocalories: 231,
               distanceMiles: nil
           )
       ],
       mindfulness: HealthMindfulnessSummary(
           todayMinutes: 10,
           sevenDayMinutes: 48,
           sevenDaySessions: 5,
           latestSessionDate: hoursFromNow(-2)
       ),
       metricSeries: mockHealthMetricSeries(),
       sleepHistory: mockSleepHistory())

    private static func mockDailyTrend(_ values: [Double]) -> [HealthTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return values.enumerated().map { index, value in
            let offset = index - (values.count - 1)
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let date = offset == 0 ? Date.now : calendar.date(byAdding: .hour, value: 12, to: day) ?? day
            return HealthTrendPoint(date: date, value: value)
        }
    }

    private static func mockHealthMetricSeries() -> [HealthMetricSeries] {
        [
            mockSeries(.heartRate, baseline: 63, today: 62, wobble: 4),
            mockSeries(.restingHeartRate, baseline: 51, today: 54, wobble: 1.4),
            mockSeries(.heartRateVariability, baseline: 65, today: 58, wobble: 3.5),
            mockSeries(.respiratoryRate, baseline: 13.4, today: 14.2, wobble: 0.35),
            mockSeries(.oxygenSaturation, baseline: 97.4, today: 97, wobble: 0.5),
            mockSeries(.wristTemperature, baseline: 96.45, today: 96.8, wobble: 0.12),
            mockSeries(.cardioFitness, baseline: 42.2, today: 42.8, wobble: 0.4),
            mockSeries(.walkingHeartRateAverage, baseline: 94, today: 91, wobble: 4),
            mockSeries(.heartRateRecovery, baseline: 25, today: 27, wobble: 2),
            mockSeries(.walkingSpeed, baseline: 3.0, today: 3.1, wobble: 0.12),
            mockSeries(.walkingStepLength, baseline: 27.0, today: 27.4, wobble: 0.35),
            mockSeries(.walkingAsymmetry, baseline: 2.0, today: 1.8, wobble: 0.25),
            mockSeries(.walkingDoubleSupport, baseline: 24.4, today: 24.1, wobble: 0.5),
            mockSeries(.walkingSteadiness, baseline: 92, today: 93, wobble: 1.2),
            mockSeries(.bodyMass, baseline: 168.8, today: 168.4, wobble: 0.7),
            mockSeries(.bodyMassIndex, baseline: 23.6, today: 23.5, wobble: 0.12),
            mockSeries(.bodyFatPercentage, baseline: 18.4, today: 18.2, wobble: 0.3),
            HealthMetricSeries(metric: .mindfulMinutes, points: mockDailyTrend([
                5, 8, 0, 10, 5, 7, 10
            ]).filter { $0.value > 0 })
        ]
    }

    private static func mockSeries(
        _ metric: HealthTrendMetric,
        baseline: Double,
        today: Double,
        wobble: Double
    ) -> HealthMetricSeries {
        let pattern = [-0.45, 0.2, 0.65, -0.1, 0.35, -0.7, 0.5]
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: .now)) ?? .now
        let points = (0...28).map { index -> HealthTrendPoint in
            let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
            let value = index == 28 ? today : baseline + pattern[index % pattern.count] * wobble
            let date = index == 28 ? Date.now : calendar.date(byAdding: .hour, value: 10, to: day) ?? day
            return HealthTrendPoint(date: date, value: value)
        }
        return HealthMetricSeries(metric: metric, points: points)
    }

    private static func mockSleepHistory() -> [HealthSleepNight] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let pattern = [-0.35, 0.1, 0.4, -0.15, 0.25, -0.5, 0.2]
        return (-28...0).map { offset in
            let sleepDay = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let asleepHours = offset == 0 ? 7.35 : 7.7 + pattern[(offset + 28) % pattern.count]
            let asleep = asleepHours * 3_600
            let awake: TimeInterval = Double(16 + ((offset + 28) % 4) * 3) * 60
            let end = offset == 0
                ? Date.now.addingTimeInterval(-3 * 3_600)
                : calendar.date(byAdding: .hour, value: 7, to: sleepDay) ?? sleepDay
            let start = end.addingTimeInterval(-(asleep + awake))
            let deep = asleep * 0.16
            let rem = asleep * 0.22
            let core = asleep - deep - rem
            var cursor = start
            var segments: [HealthSleepStageSegment] = []
            func add(_ stage: HealthSleepStage, _ duration: TimeInterval) {
                let next = cursor.addingTimeInterval(duration)
                segments.append(HealthSleepStageSegment(stage: stage, startDate: cursor, endDate: next))
                cursor = next
            }
            add(.core, core * 0.42)
            add(.deep, deep)
            add(.core, core * 0.58)
            add(.awake, awake)
            add(.rem, rem)
            return HealthSleepNight(
                sleepDay: sleepDay,
                startDate: start,
                endDate: cursor,
                asleepDuration: asleep,
                inBedDuration: asleep + awake,
                awakeDuration: awake,
                remDuration: rem,
                coreDuration: core,
                deepDuration: deep,
                unspecifiedDuration: 0,
                awakenings: Int(awake / (9 * 60)),
                stageSegments: segments,
                sourceName: "Apple Watch"
            )
        }
    }

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

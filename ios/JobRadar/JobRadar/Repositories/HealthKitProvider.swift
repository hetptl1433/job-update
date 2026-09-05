import Foundation

#if canImport(HealthKit)
import HealthKit

/// Read-only HealthKit provider. Every value remains optional so unavailable,
/// unsupported, declined, and not-yet-recorded data never appears as zero.
final class HealthKitProvider: HealthProviding {
    private let store = HKHealthStore()

    private let quantityTypes: [HKQuantityTypeIdentifier] = [
        .stepCount, .activeEnergyBurned, .appleExerciseTime,
        .distanceWalkingRunning, .flightsClimbed, .heartRate, .restingHeartRate,
        .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation,
        .appleSleepingWristTemperature, .vo2Max, .walkingHeartRateAverage,
        .heartRateRecoveryOneMinute, .walkingSpeed, .walkingStepLength,
        .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage,
        .appleWalkingSteadiness, .bodyMass, .bodyMassIndex, .bodyFatPercentage
    ]

    private var readTypes: Set<HKObjectType> {
        var values: Set<HKObjectType> = Set(quantityTypes.compactMap(HKObjectType.quantityType(forIdentifier:)))
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { values.insert(sleep) }
        if let stand = HKObjectType.categoryType(forIdentifier: .appleStandHour) { values.insert(stand) }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { values.insert(mindful) }
        values.insert(HKObjectType.activitySummaryType())
        values.insert(HKObjectType.workoutType())
        return values
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        guard status != .unnecessary else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func summary() async throws -> HealthSummary {
        async let steps = sumToday(.stepCount, unit: .count())
        async let energy = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let exercise = sumToday(.appleExerciseTime, unit: .minute())
        async let stand = standHoursToday()
        async let distance = sumToday(.distanceWalkingRunning, unit: .mile())
        async let flights = sumToday(.flightsClimbed, unit: .count())
        async let heart = latest(.heartRate, unit: .count().unitDivided(by: .minute()))
        async let restingHeart = latest(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let respiratory = latest(.respiratoryRate, unit: .count().unitDivided(by: .minute()))
        async let oxygen = latest(.oxygenSaturation, unit: .percent())
        async let wristTemperature = latest(.appleSleepingWristTemperature, unit: .degreeFahrenheit())
        async let cardioFitness = latest(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let walkingHeart = latest(.walkingHeartRateAverage, unit: .count().unitDivided(by: .minute()))
        async let heartRecovery = latest(.heartRateRecoveryOneMinute, unit: .count().unitDivided(by: .minute()))
        async let walkingSpeed = latest(.walkingSpeed, unit: .mile().unitDivided(by: .hour()))
        async let stepLength = latest(.walkingStepLength, unit: .inch())
        async let asymmetry = latest(.walkingAsymmetryPercentage, unit: .percent())
        async let doubleSupport = latest(.walkingDoubleSupportPercentage, unit: .percent())
        async let steadiness = latest(.appleWalkingSteadiness, unit: .percent())
        async let bodyMass = latest(.bodyMass, unit: .pound())
        async let bodyMassIndex = latest(.bodyMassIndex, unit: .count())
        async let bodyFat = latest(.bodyFatPercentage, unit: .percent())
        async let activity = activitySummaryToday()
        async let stepTrend = dailySums(.stepCount, unit: .count(), days: 15)
        async let energyTrend = dailySums(.activeEnergyBurned, unit: .kilocalorie(), days: 15)
        async let exerciseTrend = dailySums(.appleExerciseTime, unit: .minute(), days: 15)
        async let metricSeries = metricSeriesHistory()
        async let sleepHistory = sleepHistory(days: 29)
        async let workouts = latestWorkouts()
        async let mindfulness = mindfulnessSummary()
        async let mindfulnessTrend = mindfulnessDailyTrend(days: 29)

        let stepCount = try? await steps
        let summedEnergy = try? await energy
        let summedExercise = try? await exercise
        let countedStandHours = try? await stand
        let distanceMiles = try? await distance
        let flightCount = try? await flights
        let heartSample = try? await heart
        let restingSample = try? await restingHeart
        let hrvSample = try? await hrv
        let respiratorySample = try? await respiratory
        let oxygenSample = try? await oxygen
        let temperatureSample = try? await wristTemperature
        let cardioSample = try? await cardioFitness
        let walkingHeartSample = try? await walkingHeart
        let recoverySample = try? await heartRecovery
        let walkingSpeedSample = try? await walkingSpeed
        let stepLengthSample = try? await stepLength
        let asymmetrySample = try? await asymmetry
        let doubleSupportSample = try? await doubleSupport
        let steadinessSample = try? await steadiness
        let bodyMassSample = try? await bodyMass
        let bodyMassIndexSample = try? await bodyMassIndex
        let bodyFatSample = try? await bodyFat
        let activityValues = try? await activity
        let stepTrendValues = (try? await stepTrend) ?? []
        let energyTrendValues = (try? await energyTrend) ?? []
        let exerciseTrendValues = (try? await exerciseTrend) ?? []
        var metricSeriesValues = await metricSeries
        let sleepHistoryValues = (try? await sleepHistory) ?? []
        let sleepValues = sleepHistoryValues.max { $0.endDate < $1.endDate }.map(SleepValues.init)
        let workoutValues = (try? await workouts) ?? []
        let mindfulnessValues = try? await mindfulness
        let mindfulnessTrendValues = (try? await mindfulnessTrend) ?? []
        if !mindfulnessTrendValues.isEmpty {
            metricSeriesValues.append(HealthMetricSeries(metric: .mindfulMinutes, points: mindfulnessTrendValues))
        }

        let activeEnergy = activityValues?.activeEnergy ?? summedEnergy
        let exerciseMinutes = activityValues?.exerciseMinutes ?? summedExercise
        let standHours = activityValues?.standHours ?? countedStandHours
        let workoutValue = workoutValues.first

        var metrics: [HealthMetric] = []
        if let total = sleepValues?.asleep, total > 0 {
            metrics.append(HealthMetric(id: "sleep", title: "Sleep", value: durationString(total), systemImage: "bed.double"))
        }
        if let stepCount {
            metrics.append(HealthMetric(id: "steps", title: "Steps", value: numberString(stepCount), systemImage: "figure.walk"))
        }
        if let activeEnergy {
            metrics.append(HealthMetric(id: "energy", title: "Active Energy", value: "\(Int(activeEnergy)) kcal", systemImage: "flame"))
        }
        if let heartSample {
            metrics.append(HealthMetric(id: "heart", title: "Latest Heart Rate", value: "\(Int(heartSample.value)) bpm", systemImage: "heart.fill"))
        }
        if let workoutValue {
            metrics.append(HealthMetric(id: "workout", title: "Workout", value: workoutValue.title, systemImage: "figure.run"))
        }

        return HealthSummary(
            metrics: metrics,
            isConnected: true,
            updatedAt: .now,
            steps: stepCount,
            activeEnergyKilocalories: activeEnergy,
            exerciseMinutes: exerciseMinutes,
            standHours: standHours,
            moveGoalKilocalories: activityValues?.moveGoal,
            exerciseGoalMinutes: activityValues?.exerciseGoal,
            standGoalHours: activityValues?.standGoal,
            walkingRunningDistanceMiles: distanceMiles,
            flightsClimbed: flightCount,
            stepTrend: stepTrendValues,
            activeEnergyTrend: energyTrendValues,
            exerciseTrend: exerciseTrendValues,
            latestHeartRate: heartSample?.value,
            latestHeartRateDate: heartSample?.date,
            restingHeartRate: restingSample?.value,
            restingHeartRateDate: restingSample?.date,
            heartRateVariability: hrvSample?.value,
            heartRateVariabilityDate: hrvSample?.date,
            respiratoryRate: respiratorySample?.value,
            respiratoryRateDate: respiratorySample?.date,
            oxygenSaturation: oxygenSample.map { $0.value * 100 },
            oxygenSaturationDate: oxygenSample?.date,
            wristTemperatureFahrenheit: temperatureSample?.value,
            wristTemperatureDate: temperatureSample?.date,
            cardioFitness: cardioSample?.value,
            cardioFitnessDate: cardioSample?.date,
            walkingHeartRateAverage: walkingHeartSample?.value,
            walkingHeartRateAverageDate: walkingHeartSample?.date,
            heartRateRecovery: recoverySample?.value,
            heartRateRecoveryDate: recoverySample?.date,
            walkingSpeedMilesPerHour: walkingSpeedSample?.value,
            walkingSpeedDate: walkingSpeedSample?.date,
            walkingStepLengthInches: stepLengthSample?.value,
            walkingStepLengthDate: stepLengthSample?.date,
            walkingAsymmetryPercentage: asymmetrySample.map { $0.value * 100 },
            walkingAsymmetryDate: asymmetrySample?.date,
            walkingDoubleSupportPercentage: doubleSupportSample.map { $0.value * 100 },
            walkingDoubleSupportDate: doubleSupportSample?.date,
            walkingSteadinessPercentage: steadinessSample.map { $0.value * 100 },
            walkingSteadinessDate: steadinessSample?.date,
            bodyMassPounds: bodyMassSample?.value,
            bodyMassDate: bodyMassSample?.date,
            bodyMassIndex: bodyMassIndexSample?.value,
            bodyMassIndexDate: bodyMassIndexSample?.date,
            bodyFatPercentage: bodyFatSample.map { $0.value * 100 },
            bodyFatDate: bodyFatSample?.date,
            sleepDuration: sleepValues?.asleep,
            sleepEndDate: sleepValues?.endDate,
            awakeDuration: sleepValues?.awake,
            remDuration: sleepValues?.rem,
            coreDuration: sleepValues?.core,
            deepDuration: sleepValues?.deep,
            latestWorkout: workoutValue,
            workouts: workoutValues,
            mindfulness: mindfulnessValues,
            metricSeries: metricSeriesValues,
            sleepHistory: sleepHistoryValues
        )
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthDataError.unsupportedType
        }
        return type
    }

    private func sumToday(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        let type = try quantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latest(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> (value: Double, date: Date)? {
        let type = try quantityType(identifier)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate))
            }
            store.execute(query)
        }
    }

    private struct ActivityValues {
        var activeEnergy: Double
        var exerciseMinutes: Double
        var standHours: Double
        var moveGoal: Double    
        var exerciseGoal: Double
        var standGoal: Double
    }

    private func activitySummaryToday() async throws -> ActivityValues? {
        let dayComponents = Self.activitySummaryDayComponents()
        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: dayComponents,
            end: dayComponents
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error { continuation.resume(throwing: error); return }
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ActivityValues(
                    activeEnergy: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                    standHours: summary.appleStandHours.doubleValue(for: .count()),
                    moveGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseGoal: (summary.exerciseTimeGoal ?? summary.appleExerciseTimeGoal).doubleValue(for: .minute()),
                    standGoal: (summary.standHoursGoal ?? summary.appleStandHoursGoal).doubleValue(for: .count())
                ))
            }
            store.execute(query)
        }
    }

    /// HealthKit requires the embedded calendar on both activity-summary date
    /// components. Keeping construction centralized prevents the Objective-C
    /// exception raised by calendar-less components.
    static func activitySummaryDayComponents(
        for date: Date = .now,
        timeZone: TimeZone = .current
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDate = calendar.startOfDay(for: date)
        let components: Set<Calendar.Component> = [.era, .year, .month, .day]
        var dayComponents = calendar.dateComponents(components, from: startDate)
        dayComponents.calendar = calendar
        dayComponents.timeZone = calendar.timeZone
        return dayComponents
    }

    private func dailySums(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int = 7
    ) async throws -> [HealthTrendPoint] {
        let type = try quantityType(identifier)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var values: [HealthTrendPoint] = []
                collection.enumerateStatistics(from: start, to: .now) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    values.append(HealthTrendPoint(
                        date: statistics.startDate,
                        value: quantity.doubleValue(for: unit)
                    ))
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func dailyAverages(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int = 29,
        scale: Double = 1
    ) async throws -> [HealthTrendPoint] {
        let type = try quantityType(identifier)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .discreteAverage,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var values: [HealthTrendPoint] = []
                collection.enumerateStatistics(from: start, to: .now) { statistics, _ in
                    guard let quantity = statistics.averageQuantity() else { return }
                    let value = quantity.doubleValue(for: unit) * scale
                    guard value.isFinite else { return }
                    values.append(HealthTrendPoint(date: statistics.startDate, value: value))
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func metricSeriesHistory() async -> [HealthMetricSeries] {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        async let heartRate = dailyAverages(.heartRate, unit: beatsPerMinute)
        async let restingHeartRate = dailyAverages(.restingHeartRate, unit: beatsPerMinute)
        async let heartRateVariability = dailyAverages(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let respiratoryRate = dailyAverages(.respiratoryRate, unit: .count().unitDivided(by: .minute()))
        async let oxygenSaturation = dailyAverages(.oxygenSaturation, unit: .percent(), scale: 100)
        async let wristTemperature = dailyAverages(.appleSleepingWristTemperature, unit: .degreeFahrenheit())
        async let cardioFitness = dailyAverages(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let walkingHeartRate = dailyAverages(.walkingHeartRateAverage, unit: beatsPerMinute)
        async let heartRateRecovery = dailyAverages(.heartRateRecoveryOneMinute, unit: beatsPerMinute)
        async let walkingSpeed = dailyAverages(.walkingSpeed, unit: .mile().unitDivided(by: .hour()))
        async let walkingStepLength = dailyAverages(.walkingStepLength, unit: .inch())
        async let walkingAsymmetry = dailyAverages(.walkingAsymmetryPercentage, unit: .percent(), scale: 100)
        async let walkingDoubleSupport = dailyAverages(.walkingDoubleSupportPercentage, unit: .percent(), scale: 100)
        async let walkingSteadiness = dailyAverages(.appleWalkingSteadiness, unit: .percent(), scale: 100)
        async let bodyMass = dailyAverages(.bodyMass, unit: .pound())
        async let bodyMassIndex = dailyAverages(.bodyMassIndex, unit: .count())
        async let bodyFat = dailyAverages(.bodyFatPercentage, unit: .percent(), scale: 100)

        let collected: [(HealthTrendMetric, [HealthTrendPoint])] = [
            (.heartRate, (try? await heartRate) ?? []),
            (.restingHeartRate, (try? await restingHeartRate) ?? []),
            (.heartRateVariability, (try? await heartRateVariability) ?? []),
            (.respiratoryRate, (try? await respiratoryRate) ?? []),
            (.oxygenSaturation, (try? await oxygenSaturation) ?? []),
            (.wristTemperature, (try? await wristTemperature) ?? []),
            (.cardioFitness, (try? await cardioFitness) ?? []),
            (.walkingHeartRateAverage, (try? await walkingHeartRate) ?? []),
            (.heartRateRecovery, (try? await heartRateRecovery) ?? []),
            (.walkingSpeed, (try? await walkingSpeed) ?? []),
            (.walkingStepLength, (try? await walkingStepLength) ?? []),
            (.walkingAsymmetry, (try? await walkingAsymmetry) ?? []),
            (.walkingDoubleSupport, (try? await walkingDoubleSupport) ?? []),
            (.walkingSteadiness, (try? await walkingSteadiness) ?? []),
            (.bodyMass, (try? await bodyMass) ?? []),
            (.bodyMassIndex, (try? await bodyMassIndex) ?? []),
            (.bodyFatPercentage, (try? await bodyFat) ?? [])
        ]
        return collected.compactMap { metric, points in
            points.isEmpty ? nil : HealthMetricSeries(metric: metric, points: points)
        }
    }

    private func standHoursToday() async throws -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: .now),
            end: .now
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let achieved = (samples as? [HKCategorySample] ?? []).filter {
                    $0.value == HKCategoryValueAppleStandHour.stood.rawValue
                }.count
                continuation.resume(returning: achieved > 0 ? Double(achieved) : nil)
            }
            store.execute(query)
        }
    }

    private struct SleepValues {
        var asleep: TimeInterval = 0
        var awake: TimeInterval = 0
        var rem: TimeInterval = 0
        var core: TimeInterval = 0
        var deep: TimeInterval = 0
        var endDate: Date?

        init(_ night: HealthSleepNight) {
            asleep = night.asleepDuration
            awake = night.awakeDuration
            rem = night.remDuration
            core = night.coreDuration
            deep = night.deepDuration
            endDate = night.endDate
        }
    }

    private struct SleepSourceScore {
        var stagedDuration: TimeInterval
        var asleepDuration: TimeInterval
    }

    private struct InBedWindow {
        var startDate: Date
        var endDate: Date
        var duration: TimeInterval
    }

    private func sleepHistory(days: Int) async throws -> [HealthSleepNight] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let calendar = Calendar.current
        let now = Date.now
        let start = calendar.date(byAdding: .day, value: -(days + 1), to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let allSamples = samples as? [HKCategorySample] ?? []
                continuation.resume(returning: Self.buildSleepHistory(
                    from: allSamples,
                    days: days,
                    now: now,
                    calendar: calendar
                ))
            }
            store.execute(query)
        }
    }

    private static func buildSleepHistory(
        from samples: [HKCategorySample],
        days: Int,
        now: Date,
        calendar: Calendar
    ) -> [HealthSleepNight] {
        guard days > 0 else { return [] }
        let grouped = Dictionary(grouping: samples.filter { $0.endDate > $0.startDate }) { sample in
            let midpoint = sample.startDate.addingTimeInterval(sample.endDate.timeIntervalSince(sample.startDate) / 2)
            return sleepDay(containing: midpoint, calendar: calendar)
        }
        let currentSleepDay = sleepDay(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let firstSleepDay = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        return grouped.compactMap { sleepDay, daySamples -> HealthSleepNight? in
            guard sleepDay >= firstSleepDay, sleepDay <= currentSleepDay else { return nil }
            let sourceGroups = Dictionary(
                grouping: daySamples.filter { sleepStage(for: $0.value) != nil },
                by: sleepSourceKey
            )
            guard let primary = sourceGroups.max(by: { lhs, rhs in
                let left = sleepSourceScore(lhs.value)
                let right = sleepSourceScore(rhs.value)
                if left.stagedDuration != right.stagedDuration {
                    return left.stagedDuration < right.stagedDuration
                }
                if left.asleepDuration != right.asleepDuration {
                    return left.asleepDuration < right.asleepDuration
                }
                return lhs.key > rhs.key
            }) else { return nil }

            let canonical = canonicalSleepSegments(from: primary.value)
            guard let sessionSegments = mainSleepSession(from: canonical) else { return nil }
            let asleepSegments = sessionSegments.filter { $0.stage != .awake }
            guard let firstAsleep = asleepSegments.first,
                  let lastAsleep = asleepSegments.last else { return nil }

            let asleepDuration = asleepSegments.reduce(0) { $0 + $1.duration }
            guard asleepDuration > 0, asleepDuration.isFinite else { return nil }
            let awakeDuration = sessionSegments
                .filter { $0.stage == .awake }
                .reduce(0) { $0 + $1.duration }
            let inBed = coherentInBedWindow(
                from: daySamples,
                sleepStart: firstAsleep.startDate,
                sleepEnd: lastAsleep.endDate,
                asleepDuration: asleepDuration
            )
            let awakenings = sessionSegments.filter {
                $0.stage == .awake
                    && $0.duration >= 2 * 60
                    && $0.startDate > firstAsleep.startDate
                    && $0.endDate < lastAsleep.endDate
            }.count

            return HealthSleepNight(
                sleepDay: sleepDay,
                startDate: min(inBed?.startDate ?? firstAsleep.startDate, firstAsleep.startDate),
                endDate: max(inBed?.endDate ?? lastAsleep.endDate, lastAsleep.endDate),
                asleepDuration: asleepDuration,
                inBedDuration: inBed?.duration,
                awakeDuration: awakeDuration,
                remDuration: duration(of: .rem, in: sessionSegments),
                coreDuration: duration(of: .core, in: sessionSegments),
                deepDuration: duration(of: .deep, in: sessionSegments),
                unspecifiedDuration: duration(of: .unspecified, in: sessionSegments),
                awakenings: awakenings,
                stageSegments: sessionSegments,
                sourceName: primary.value.first?.sourceRevision.source.name
            )
        }
        .sorted { $0.endDate < $1.endDate }
    }

    private static func sleepDay(containing date: Date, calendar: Calendar) -> Date {
        // Use a noon-to-noon sleep day and label it by the morning the main
        // sleep ends. This keeps an overnight session together and makes last
        // night's sleep appear under Today.
        let shifted = calendar.date(byAdding: .hour, value: -12, to: date) ?? date.addingTimeInterval(-12 * 60 * 60)
        let periodStart = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .day, value: 1, to: periodStart) ?? periodStart
    }

    private static func sleepSourceKey(_ sample: HKCategorySample) -> String {
        let revision = sample.sourceRevision
        return revision.source.bundleIdentifier + "|" + (revision.productType ?? "unknown")
    }

    private static func sleepSourceScore(_ samples: [HKCategorySample]) -> SleepSourceScore {
        let segments = canonicalSleepSegments(from: samples)
        return SleepSourceScore(
            stagedDuration: segments
                .filter { [.rem, .core, .deep].contains($0.stage) }
                .reduce(0) { $0 + $1.duration },
            asleepDuration: segments
                .filter { $0.stage != .awake }
                .reduce(0) { $0 + $1.duration }
        )
    }

    private static func canonicalSleepSegments(from samples: [HKCategorySample]) -> [HealthSleepStageSegment] {
        let usable = samples.filter {
            $0.endDate > $0.startDate && sleepStage(for: $0.value) != nil
        }
        let boundaries = Array(Set(usable.flatMap { [$0.startDate, $0.endDate] })).sorted()
        guard boundaries.count >= 2 else { return [] }

        var segments: [HealthSleepStageSegment] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }
            let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let covering = usable.filter { $0.startDate <= midpoint && $0.endDate >= midpoint }
            guard let selected = covering.max(by: {
                sleepStagePriority($0.value) < sleepStagePriority($1.value)
            }), let stage = sleepStage(for: selected.value) else { continue }

            let next = HealthSleepStageSegment(stage: stage, startDate: start, endDate: end)
            if let lastIndex = segments.indices.last,
               segments[lastIndex].stage == next.stage,
               abs(segments[lastIndex].endDate.timeIntervalSince(next.startDate)) < 1 {
                segments[lastIndex].endDate = next.endDate
            } else {
                segments.append(next)
            }
        }
        return segments
    }

    private static func mainSleepSession(
        from segments: [HealthSleepStageSegment]
    ) -> [HealthSleepStageSegment]? {
        guard !segments.isEmpty else { return nil }
        var clusters: [[HealthSleepStageSegment]] = []
        for segment in segments.sorted(by: { $0.startDate < $1.startDate }) {
            if let lastEnd = clusters.last?.last?.endDate,
               segment.startDate.timeIntervalSince(lastEnd) <= 90 * 60 {
                clusters[clusters.count - 1].append(segment)
            } else {
                clusters.append([segment])
            }
        }
        guard let main = clusters.max(by: {
            asleepDuration(in: $0) < asleepDuration(in: $1)
        }) else { return nil }
        let asleep = main.filter { $0.stage != .awake }
        guard let first = asleep.first, let last = asleep.last else { return nil }
        return main.filter { $0.endDate > first.startDate && $0.startDate < last.endDate }
    }

    private static func asleepDuration(in segments: [HealthSleepStageSegment]) -> TimeInterval {
        segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
    }

    private static func duration(
        of stage: HealthSleepStage,
        in segments: [HealthSleepStageSegment]
    ) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    private static func coherentInBedWindow(
        from samples: [HKCategorySample],
        sleepStart: Date,
        sleepEnd: Date,
        asleepDuration: TimeInterval
    ) -> InBedWindow? {
        let candidates = samples.filter {
            HKCategoryValueSleepAnalysis(rawValue: $0.value) == .inBed
                && $0.endDate > sleepStart
                && $0.startDate < sleepEnd
        }
        let sourceGroups = Dictionary(grouping: candidates, by: sleepSourceKey)
        return sourceGroups.compactMap { _, sourceSamples -> InBedWindow? in
            let intervals = sourceSamples.map { ($0.startDate, $0.endDate) }
            let duration = unionDuration(of: intervals)
            guard let start = sourceSamples.map(\.startDate).min(),
                  let end = sourceSamples.map(\.endDate).max(),
                  duration >= asleepDuration,
                  duration <= 20 * 60 * 60 else { return nil }
            return InBedWindow(startDate: start, endDate: end, duration: duration)
        }
        .min { $0.duration < $1.duration }
    }

    private static func unionDuration(of intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return total
    }

    private static func sleepStage(for value: Int) -> HealthSleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .awake: .awake
        case .asleepREM: .rem
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepUnspecified: .unspecified
        default: nil
        }
    }

    private static func sleepStagePriority(_ value: Int) -> Int {
        switch sleepStage(for: value) {
        case .rem, .core, .deep: 3
        case .awake: 2
        case .unspecified: 1
        case nil: 0
        }
    }

    private func latestWorkouts() async throws -> [HealthWorkoutSummary] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: nil, limit: 20, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    HealthWorkoutSummary(
                        id: workout.uuid,
                        title: Self.workoutName(workout.workoutActivityType),
                        startedAt: workout.startDate,
                        duration: workout.duration,
                        energyKilocalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        distanceMiles: workout.totalDistance?.doubleValue(for: .mile())
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    private func mindfulnessSummary() async throws -> HealthMindfulnessSummary? {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let sessions = samples as? [HKCategorySample] ?? []
                guard let latest = sessions.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let todaySeconds = sessions
                    .filter { $0.endDate >= today }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let weekSeconds = sessions.reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                }
                continuation.resume(returning: HealthMindfulnessSummary(
                    todayMinutes: todaySeconds / 60,
                    sevenDayMinutes: weekSeconds / 60,
                    sevenDaySessions: sessions.count,
                    latestSessionDate: latest.endDate
                ))
            }
            store.execute(query)
        }
    }

    private func mindfulnessDailyTrend(days: Int) async throws -> [HealthTrendPoint] {
        guard days > 0,
              let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let sessions = samples as? [HKCategorySample] ?? []
                let grouped = Dictionary(grouping: sessions) {
                    calendar.startOfDay(for: $0.endDate)
                }
                let points = grouped.compactMap { day, values -> HealthTrendPoint? in
                    let minutes = values.reduce(0.0) {
                        $0 + max(0, $1.endDate.timeIntervalSince($1.startDate)) / 60
                    }
                    guard minutes.isFinite, minutes > 0 else { return nil }
                    return HealthTrendPoint(date: day, value: minutes)
                }
                .sorted { $0.date < $1.date }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycling"
        case .swimming: "Swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .hiking: "Hike"
        default: "Workout"
        }
    }

    private static func isAsleep(_ value: Int) -> Bool {
        [
            HKCategoryValueSleepAnalysis.asleepUnspecified,
            .asleepCore,
            .asleepDeep,
            .asleepREM
        ].map(\.rawValue).contains(value)
    }

    private func numberString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        "\(Int(seconds) / 3600)h \((Int(seconds) % 3600) / 60)m"
    }
}

private enum HealthDataError: Error { case unsupportedType }

#else

final class HealthKitProvider: HealthProviding {
    var isAvailable: Bool { false }
    func requestAuthorization() async throws {}
    func summary() async throws -> HealthSummary { HealthSummary(metrics: [], isConnected: false) }
}

#endif

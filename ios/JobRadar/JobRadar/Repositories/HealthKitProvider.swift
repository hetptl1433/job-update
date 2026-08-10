import Foundation

#if canImport(HealthKit)
import HealthKit

/// Real HealthKit-backed provider. Reads today's steps, active energy, sleep and
/// workout. Read-only — the app never writes health data.
final class HealthKitProvider: HealthProviding {
    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.heartRate),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType()
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func summary() async throws -> HealthSummary {
        async let steps = sumToday(HKQuantityType(.stepCount), unit: .count())
        async let energy = sumToday(HKQuantityType(.activeEnergyBurned), unit: .kilocalorie())
        async let sleep = sleepLastNight()
        async let workedOut = didWorkOutToday()
        async let heartRate = latestHeartRate()

        let stepCount = (try? await steps) ?? 0
        let energyKcal = (try? await energy) ?? 0
        let sleepSeconds = (try? await sleep) ?? 0
        let workout = (try? await workedOut) ?? false
        let bpm = (try? await heartRate) ?? 0

        var metrics: [HealthMetric] = [
            HealthMetric(id: "sleep", title: "Sleep",
                         value: sleepSeconds > 0 ? durationString(sleepSeconds) : "—",
                         systemImage: "bed.double"),
            HealthMetric(id: "steps", title: "Steps", value: numberString(stepCount), systemImage: "figure.walk"),
            HealthMetric(id: "energy", title: "Active Energy", value: "\(Int(energyKcal)) kcal", systemImage: "flame"),
            HealthMetric(id: "heart", title: "Latest Heart Rate", value: bpm > 0 ? "\(Int(bpm)) bpm" : "—", systemImage: "heart.fill"),
            HealthMetric(id: "workout", title: "Workout", value: workout ? "Completed" : "None", systemImage: "figure.run")
        ]
        // Drop metrics that returned no data at all so the UI stays honest.
        if stepCount == 0 && energyKcal == 0 && sleepSeconds == 0 && !workout && bpm == 0 {
            metrics = []
        }
        return HealthSummary(metrics: metrics, isConnected: true)
    }

    // MARK: Queries

    private func sumToday(_ type: HKQuantityType, unit: HKUnit) async throws -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func sleepLastNight() async throws -> TimeInterval {
        let type = HKCategoryType(.sleepAnalysis)
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let asleep = (samples as? [HKCategorySample])?.filter { Self.isAsleep($0.value) } ?? []
                let total = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: total)
            }
            store.execute(query)
        }
    }

    private func didWorkOutToday() async throws -> Bool {
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: !(samples?.isEmpty ?? true))
            }
            store.execute(query)
        }
    }

    private func latestHeartRate() async throws -> Double {
        let type = HKQuantityType(.heartRate)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let unit = HKUnit.count().unitDivided(by: .minute())
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private static func isAsleep(_ value: Int) -> Bool {
        [HKCategoryValueSleepAnalysis.asleepUnspecified,
         .asleepCore, .asleepDeep, .asleepREM].map(\.rawValue).contains(value)
    }

    private func numberString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

#else

/// Fallback if HealthKit is unavailable at compile time (not expected on iOS).
final class HealthKitProvider: HealthProviding {
    var isAvailable: Bool { false }
    func requestAuthorization() async throws {}
    func summary() async throws -> HealthSummary { HealthSummary(metrics: [], isConnected: false) }
}

#endif

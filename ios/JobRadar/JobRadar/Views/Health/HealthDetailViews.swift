import Charts
import SwiftUI

extension HealthTimeRange {
    var contextLabel: String {
        switch self {
        case .today: "Today so far"
        case .sevenDays: "Last 7 recorded days"
        }
    }

    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch self {
        case .today:
            return date >= calendar.startOfDay(for: now) && date <= now
        case .sevenDays:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return date >= start && date <= now
        }
    }
}

struct HealthRangePicker: View {
    @Binding var selection: HealthTimeRange

    var body: some View {
        Picker("Health time range", selection: $selection) {
            ForEach(HealthTimeRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(AppTheme.accent)
        .accessibilityHint("Changes the time range for health values and trends")
    }
}

struct HealthMiniTrend: View {
    let points: [HealthTrendPoint]
    let tint: Color
    let accessibilityTitle: String
    var emptyText: String = "No trend data"

    var body: some View {
        if points.count > 1 {
            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(accessibilityTitle, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)

                AreaMark(
                    x: .value("Time", point.date),
                    y: .value(accessibilityTitle, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.24), tint.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 42)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "waveform.slash")
                Text(emptyText)
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.tertiaryText)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var accessibilitySummary: String {
        guard let first = points.first?.value, let last = points.last?.value else {
            return "\(accessibilityTitle), no trend data"
        }
        let direction = last > first ? "increased" : last < first ? "decreased" : "was unchanged"
        return "\(accessibilityTitle) \(direction), from \(first.formatted()) to \(last.formatted()), across \(points.count) points"
    }
}

struct HealthTrendChart: View {
    let points: [HealthTrendPoint]
    let title: String
    let unit: String
    let tint: Color
    let range: HealthTimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(range.contextLabel.uppercased()).sectionLabel()
                    Text(summaryText).font(.title3.weight(.bold))
                    Text(points.isEmpty ? "No samples in this range" : "\(points.count) recorded point\(points.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            if points.count > 1 {
                Chart(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(title, point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint)

                    PointMark(
                        x: .value("Time", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(tint)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .today ? 4 : 7)) {
                        AxisGridLine().foregroundStyle(AppTheme.separator)
                        if range == .today {
                            AxisValueLabel(format: .dateTime.hour())
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(AppTheme.separator)
                        AxisValueLabel().foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
            } else {
                noSampleMessage("A trend needs at least two recorded samples in this range.")
            }
        }
        .cardSurface()
    }

    private var summaryText: String {
        guard !points.isEmpty else { return "—" }
        let average = points.reduce(0) { $0 + $1.value } / Double(points.count)
        let formatted = average.formatted(.number.precision(.fractionLength(average >= 100 ? 0 : 1)))
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    private var accessibilitySummary: String {
        guard let first = points.first?.value, let last = points.last?.value else {
            return "\(title), no trend data in \(range.rawValue)"
        }
        let direction = last > first ? "increased" : last < first ? "decreased" : "was unchanged"
        return "\(title), \(range.rawValue), \(direction) from \(first.formatted()) to \(last.formatted()) \(unit)"
    }
}

func healthPoints(_ points: [HealthTrendPoint], in range: HealthTimeRange) -> [HealthTrendPoint] {
    points.filter { range.contains($0.date) }.sorted { $0.date < $1.date }
}

struct HealthActivityDetailView: View {
    let summary: HealthSummary
    @State private var selectedTrend: ActivityTrend = .steps
    @State private var selectedRange: HealthTimeRange

    init(summary: HealthSummary, initialRange: HealthTimeRange = .today) {
        self.summary = summary
        _selectedRange = State(initialValue: initialRange)
    }

    private enum ActivityTrend: String, CaseIterable, Identifiable {
        case steps = "Steps"
        case move = "Move"
        case exercise = "Exercise"

        var id: String { rawValue }
    }

    private var trendPoints: [HealthTrendPoint] {
        switch selectedTrend {
        case .steps: summary.stepTrend
        case .move: summary.activeEnergyTrend
        case .exercise: summary.exerciseTrend
        }
    }

    private var trendTint: Color {
        switch selectedTrend {
        case .steps: AppTheme.success
        case .move: AppTheme.coral
        case .exercise: AppTheme.warning
        }
    }

    private var trendUnit: String {
        switch selectedTrend {
        case .steps: "steps"
        case .move: "kcal"
        case .exercise: "min"
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                HealthRangePicker(selection: $selectedRange)

                VStack(spacing: AppTheme.Spacing.lg) {
                    activityGoal(
                        "Move",
                        value: rangeValue(summary.activeEnergyKilocalories, points: summary.activeEnergyTrend),
                        goal: summary.moveGoalKilocalories ?? 600,
                        unit: "kcal",
                        tint: AppTheme.coral
                    )
                    activityGoal(
                        "Exercise",
                        value: rangeValue(summary.exerciseMinutes, points: summary.exerciseTrend),
                        goal: summary.exerciseGoalMinutes ?? 30,
                        unit: "min",
                        tint: AppTheme.warning
                    )
                    if selectedRange == .today {
                        activityGoal(
                            "Stand",
                            value: summary.standHours,
                            goal: summary.standGoalHours ?? 12,
                            unit: "hr",
                            tint: AppTheme.info
                        )
                    }
                }
                .cardSurface()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    Text("CHOOSE A SIGNAL").sectionLabel()
                    Picker("Activity trend", selection: $selectedTrend) {
                        ForEach(ActivityTrend.allCases) { trend in
                            Text(trend.rawValue).tag(trend)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .cardSurface()

                HealthTrendChart(
                    points: healthPoints(trendPoints, in: selectedRange),
                    title: selectedTrend.rawValue,
                    unit: trendUnit,
                    tint: trendTint,
                    range: selectedRange
                )

                HStack(spacing: 0) {
                    if selectedRange == .today {
                        detailCompactMetric(summary.steps, title: "Steps", unit: "")
                        detailCompactMetric(summary.walkingRunningDistanceMiles, title: "Distance", unit: "mi", digits: 1)
                        detailCompactMetric(summary.flightsClimbed, title: "Floors", unit: "")
                    } else {
                        detailCompactMetric(rangeValue(summary.steps, points: summary.stepTrend), title: "Avg steps", unit: "")
                        detailCompactMetric(rangeValue(summary.activeEnergyKilocalories, points: summary.activeEnergyTrend), title: "Avg move", unit: "kcal")
                        detailCompactMetric(rangeValue(summary.exerciseMinutes, points: summary.exerciseTrend), title: "Avg exercise", unit: "min")
                    }
                }
                .cardSurface()
            }
            .padding(AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.background)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func activityGoal(_ title: String, value: Double?, goal: Double, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Label(title, systemImage: "circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(value.map { "\(Int($0)) / \(Int(goal)) \(unit)" } ?? "No sample")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
            }
            ProgressView(value: min(value ?? 0, goal), total: max(goal, 1)).tint(tint)
        }
    }

    private func rangeValue(_ current: Double?, points: [HealthTrendPoint]) -> Double? {
        guard selectedRange == .sevenDays else { return current }
        let values = healthPoints(points, in: .sevenDays).map(\.value).filter(\.isFinite)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct HealthSignalDetailView: View {
    let vital: HealthVital
    @State private var selectedRange: HealthTimeRange

    init(vital: HealthVital, initialRange: HealthTimeRange = .today) {
        self.vital = vital
        _selectedRange = State(initialValue: initialRange)
    }

    private var rangePoints: [HealthTrendPoint] {
        healthPoints(vital.trend, in: selectedRange)
    }

    private var displayedValue: String {
        guard selectedRange == .sevenDays, !rangePoints.isEmpty else { return vital.value }
        let average = rangePoints.reduce(0) { $0 + $1.value } / Double(rangePoints.count)
        return average.formatted(.number.precision(.fractionLength(vital.fractionDigits)))
    }

    private var displayedDetail: String {
        if selectedRange == .sevenDays, !rangePoints.isEmpty {
            return "Average across \(rangePoints.count) recorded day\(rangePoints.count == 1 ? "" : "s")"
        }
        return vital.detail == "No sample" ? "No recent sample" : "Recorded \(vital.detail)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                HealthRangePicker(selection: $selectedRange)

                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: vital.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(vital.tint)
                        .frame(width: 64, height: 64)
                        .background(vital.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(displayedValue).font(.system(size: 46, weight: .bold, design: .rounded))
                        Text(vital.unit).font(.headline).foregroundStyle(AppTheme.secondaryText)
                    }
                    Text(displayedDetail)
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .cardSurface()

                HealthTrendChart(
                    points: rangePoints,
                    title: vital.title,
                    unit: vital.unit,
                    tint: vital.tint,
                    range: selectedRange
                )

                detailInformationCard(title: "About this signal", symbol: "info.circle", text: vital.explanation)
                detailInformationCard(
                    title: "From Apple Health",
                    symbol: "heart.text.square",
                    text: "Orbit displays only samples returned by Apple Health. A missing value can mean there is no recorded sample or that read access was not granted. Trends are informational and are not medical advice."
                )
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle(vital.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HealthSleepDetailView: View {
    let summary: HealthSummary
    @State private var selectedRange: HealthTimeRange
    @State private var selectedTrend: SleepTrend = .duration

    private enum SleepTrend: String, CaseIterable, Identifiable {
        case duration = "Duration"
        case deep = "Deep"
        case rem = "REM"
        case efficiency = "Efficiency"

        var id: String { rawValue }

        var unit: String {
            switch self {
            case .duration, .deep, .rem: "hr"
            case .efficiency: "%"
            }
        }

        var tint: Color {
            switch self {
            case .duration: AppTheme.purple
            case .deep: AppTheme.accent
            case .rem: AppTheme.purple.opacity(0.72)
            case .efficiency: AppTheme.success
            }
        }
    }

    init(summary: HealthSummary, initialRange: HealthTimeRange = .today) {
        self.summary = summary
        _selectedRange = State(initialValue: initialRange)
    }

    private var sortedNights: [HealthSleepNight] {
        summary.sleepHistory.sorted { $0.sleepDay < $1.sleepDay }
    }

    private var latestNight: HealthSleepNight? { sortedNights.last }

    private var displayedNights: [HealthSleepNight] {
        switch selectedRange {
        case .today:
            return latestNight.map { [$0] } ?? []
        case .sevenDays:
            return sortedNights.filter { selectedRange.contains($0.sleepDay) }
        }
    }

    private var rangeDuration: TimeInterval? {
        if !displayedNights.isEmpty {
            return displayedNights.reduce(0) { $0 + $1.asleepDuration } / Double(displayedNights.count)
        }
        return selectedRange == .today ? summary.sleepDuration : nil
    }

    private var rangeDurationScore: Int? {
        guard let rangeDuration, rangeDuration > 0 else { return nil }
        return min(100, max(0, Int((rangeDuration / (8 * 3_600)) * 100)))
    }

    private var selectedTrendPoints: [HealthTrendPoint] {
        displayedNights.compactMap { night in
            let value: Double?
            switch selectedTrend {
            case .duration: value = night.asleepDuration / 3600
            case .deep: value = night.deepDuration > 0 ? night.deepDuration / 3600 : nil
            case .rem: value = night.remDuration > 0 ? night.remDuration / 3600 : nil
            case .efficiency: value = night.efficiency
            }
            return value.map { HealthTrendPoint(date: night.sleepDay, value: $0) }
        }
    }

    private var stages: [SleepDetailStage] {
        let stagedNights = displayedNights.filter {
            $0.remDuration > 0 || $0.coreDuration > 0 || $0.deepDuration > 0
        }
        if !stagedNights.isEmpty {
            let count = Double(stagedNights.count)
            let asleep = stagedNights.reduce(0) { $0 + $1.asleepDuration } / count
            let inBedValues = stagedNights.compactMap(\.inBedDuration)
            let inBed = inBedValues.isEmpty ? nil : inBedValues.reduce(0, +) / Double(inBedValues.count)
            return [
                SleepDetailStage(title: "REM", duration: stagedNights.reduce(0) { $0 + $1.remDuration } / count, tint: AppTheme.purple.opacity(0.78), denominator: asleep),
                SleepDetailStage(title: "Core", duration: stagedNights.reduce(0) { $0 + $1.coreDuration } / count, tint: AppTheme.purple, denominator: asleep),
                SleepDetailStage(title: "Deep", duration: stagedNights.reduce(0) { $0 + $1.deepDuration } / count, tint: AppTheme.accent.opacity(0.82), denominator: asleep),
                SleepDetailStage(title: "Awake", duration: stagedNights.reduce(0) { $0 + $1.awakeDuration } / count, tint: AppTheme.secondaryText, denominator: inBed)
            ]
        }
        return [
            SleepDetailStage(title: "REM", duration: summary.remDuration, tint: AppTheme.purple.opacity(0.78), denominator: summary.sleepDuration),
            SleepDetailStage(title: "Core", duration: summary.coreDuration, tint: AppTheme.purple, denominator: summary.sleepDuration),
            SleepDetailStage(title: "Deep", duration: summary.deepDuration, tint: AppTheme.accent.opacity(0.82), denominator: summary.sleepDuration),
            SleepDetailStage(title: "Awake", duration: summary.awakeDuration, tint: AppTheme.secondaryText, denominator: optionalSum(summary.sleepDuration, summary.awakeDuration))
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                HealthRangePicker(selection: $selectedRange)

                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "bed.double.fill")
                        .font(.title2).foregroundStyle(AppTheme.accent)
                        .frame(width: 54, height: 54)
                        .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    Text(rangeDuration.map(healthDurationText) ?? "—")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(selectedRange == .today ? "Latest recorded sleep" : "Average across \(displayedNights.count) recorded night\(displayedNights.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center)
                    if let score = rangeDurationScore {
                        Label("Duration score \(score) / 100 · \(selectedRange.contextLabel)", systemImage: "moon.stars.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.purple)
                    }
                }
                .frame(maxWidth: .infinity)
                .cardSurface()

                if let latestNight {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LATEST SLEEP").sectionLabel()
                                Text(latestNight.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.headline)
                            }
                            Spacer()
                            if let source = latestNight.sourceName, !source.isEmpty {
                                Label(source, systemImage: "applewatch")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        HStack {
                            Label(latestNight.startDate.formatted(date: .omitted, time: .shortened), systemImage: "moon.fill")
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundStyle(AppTheme.tertiaryText)
                            Spacer()
                            Label(latestNight.endDate.formatted(date: .omitted, time: .shortened), systemImage: "sun.max.fill")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: AppTheme.Spacing.sm)], spacing: AppTheme.Spacing.sm) {
                            sleepSummaryMetric("Asleep", value: healthDurationText(latestNight.asleepDuration), symbol: "bed.double")
                            sleepSummaryMetric("In bed", value: latestNight.inBedDuration.map(healthDurationText) ?? "Not recorded", symbol: "rectangle.inset.filled")
                            sleepSummaryMetric("Efficiency", value: latestNight.efficiency.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "Not available", symbol: "gauge.with.dots.needle.67percent")
                            sleepSummaryMetric("Awakenings", value: "\(latestNight.awakenings)", symbol: "eye")
                        }
                    }
                    .cardSurface()
                }

                if let latestNight, !latestNight.stageSegments.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("STAGE TIMELINE").sectionLabel()
                        SleepStageTimeline(night: latestNight)
                    }
                    .cardSurface()
                } else {
                    detailInformationCard(
                        title: "Stage timeline unavailable",
                        symbol: "waveform.slash",
                        text: "Apple Health returned stage totals without enough timestamped segments to draw the night."
                    )
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    Text(selectedRange == .today ? "LATEST SLEEP STAGES" : "AVERAGE SLEEP STAGES").sectionLabel()
                    ForEach(stages) { stage in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label(stage.title, systemImage: "circle.fill")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(stage.tint)
                                Spacer()
                                Text(stage.valueText)
                                    .font(.subheadline.weight(.semibold))
                            }
                            ProgressView(value: stage.duration ?? 0, total: max(stage.denominator ?? 1, 1)).tint(stage.tint)
                                .accessibilityLabel(stage.accessibilityText)
                        }
                    }
                }
                .cardSurface()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Text("CHOOSE A SLEEP TREND").sectionLabel()
                    Picker("Sleep trend", selection: $selectedTrend) {
                        ForEach(SleepTrend.allCases) { trend in
                            Text(trend.rawValue).tag(trend)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AppTheme.accent)
                }
                .cardSurface()

                HealthTrendChart(
                    points: selectedTrendPoints,
                    title: selectedTrend.rawValue,
                    unit: selectedTrend.unit,
                    tint: selectedTrend.tint,
                    range: selectedRange
                )

                if selectedRange == .sevenDays, !displayedNights.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("RECENT NIGHTS").sectionLabel()
                        ForEach(Array(displayedNights.suffix(7).reversed())) { night in
                            HStack(spacing: AppTheme.Spacing.md) {
                                Image(systemName: "moon.fill")
                                    .foregroundStyle(AppTheme.purple)
                                    .frame(width: 34, height: 34)
                                    .background(AppTheme.purple.opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(night.sleepDay.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline.weight(.semibold))
                                    Text("Deep \(healthDurationText(night.deepDuration)) · REM \(healthDurationText(night.remDuration))")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(healthDurationText(night.asleepDuration))
                                        .font(.subheadline.weight(.bold))
                                    Text(night.efficiency.map { "\(Int($0.rounded()))% efficient" } ?? "Efficiency unavailable")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            if night.id != displayedNights.suffix(7).first?.id {
                                Divider().overlay(AppTheme.separator)
                            }
                        }
                    }
                    .cardSurface()
                }

                detailInformationCard(
                    title: "How Orbit summarizes sleep",
                    symbol: "info.circle",
                    text: "The duration score compares recorded sleep with eight hours. Efficiency appears only when Apple Health supplies coherent in-bed data. These summaries are not clinical sleep-quality, recovery, or medical assessments."
                )
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sleepSummaryMetric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).font(.caption).foregroundStyle(AppTheme.accent)
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.72)
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct HealthBodyLoadDetailView: View {
    let estimate: HealthLoadEstimate

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(levelTint)
                        .frame(width: 64, height: 64)
                        .background(levelTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(estimate.index.map(String.init) ?? "—")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text(estimate.level.title)
                        .font(.title3.weight(.bold))
                    if let confidence = estimate.confidence {
                        Text("\(confidence.rawValue.capitalized) confidence · personal-baseline estimate")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    } else {
                        Text("Collecting a personal baseline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    ProgressView(value: Double(estimate.index ?? 0), total: 100)
                        .tint(levelTint)
                        .accessibilityLabel("Body Load index")
                        .accessibilityValue(estimate.index.map { "\($0) out of 100" } ?? "Still collecting")
                    Text(estimate.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .cardSurface()

                if !estimate.factors.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        Text("SIGNALS IN THIS ESTIMATE").sectionLabel()
                        ForEach(estimate.factors) { factor in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                HStack(spacing: AppTheme.Spacing.sm) {
                                    Image(systemName: factorSymbol(factor.state))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(factorTint(factor.state))
                                        .frame(width: 28, height: 28)
                                        .background(factorTint(factor.state).opacity(0.1), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(factor.title).font(.subheadline.weight(.semibold))
                                        Text(factorStateText(factor.state))
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    Spacer()
                                    Text(signedPercent(factor.percentDifference))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(factorTint(factor.state))
                                }

                                HStack(spacing: 0) {
                                    detailTextMetric(loadValue(factor.currentValue, unit: factor.unit), "Current")
                                    detailTextMetric(loadValue(factor.baselineValue, unit: factor.unit), "28-day median")
                                    detailTextMetric("\(factor.baselineDays)", "Baseline days")
                                }
                            }
                            .accessibilityElement(children: .combine)
                            if factor.id != estimate.factors.last?.id {
                                Divider().overlay(AppTheme.separator)
                            }
                        }
                    }
                    .cardSurface()
                }

                detailInformationCard(
                    title: "How Body Load works",
                    symbol: "function",
                    text: "Orbit calculates this locally from deviations in HRV, resting heart rate, respiratory rate, sleep duration, and wrist temperature versus up to 28 prior recorded days. At least seven baseline days for two core signals are required. The index is centered near 50 for your own baseline; it is not a universal health range."
                )

                detailInformationCard(
                    title: "Important limitation",
                    symbol: "exclamationmark.shield",
                    text: "Body Load is an app estimate of physiological patterns. It does not directly measure psychological stress, readiness, illness, or recovery, and it cannot provide a diagnosis or medical advice."
                )
            }
            .padding(AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.background)
        .navigationTitle("Body Load")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var levelTint: Color {
        switch estimate.level {
        case .collecting: AppTheme.secondaryText
        case .lowerThanUsual: AppTheme.info
        case .typical: AppTheme.success
        case .higherThanUsual: AppTheme.accent
        }
    }

    private func factorTint(_ state: HealthLoadFactorState) -> Color {
        switch state {
        case .addsLoad: AppTheme.accent
        case .nearBaseline: AppTheme.success
        case .reducesLoad: AppTheme.info
        }
    }

    private func factorSymbol(_ state: HealthLoadFactorState) -> String {
        switch state {
        case .addsLoad: "arrow.up"
        case .nearBaseline: "equal"
        case .reducesLoad: "arrow.down"
        }
    }

    private func factorStateText(_ state: HealthLoadFactorState) -> String {
        switch state {
        case .addsLoad: "Above this signal's usual variation"
        case .nearBaseline: "Near this signal's personal baseline"
        case .reducesLoad: "Below this signal's usual load pattern"
        }
    }

    private func signedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func loadValue(_ value: Double, unit: String) -> String {
        let digits = unit == "°F" || unit == "/min" || unit == "hr" ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(digits))) + " " + unit
    }
}

struct HealthWorkoutsDetailView: View {
    let summary: HealthSummary
    @State private var selectedRange: HealthTimeRange

    init(summary: HealthSummary, initialRange: HealthTimeRange = .today) {
        self.summary = summary
        _selectedRange = State(initialValue: initialRange)
    }

    private var allWorkouts: [HealthWorkoutSummary] {
        let values = !summary.workouts.isEmpty ? summary.workouts : summary.latestWorkout.map { [$0] } ?? []
        return values.sorted { $0.startedAt > $1.startedAt }
    }

    private var workouts: [HealthWorkoutSummary] {
        allWorkouts.filter { selectedRange.contains($0.startedAt) }
    }

    private var totalDuration: TimeInterval {
        workouts.reduce(0) { $0 + $1.duration }
    }

    private var totalEnergy: Double? {
        let values = workouts.compactMap(\.energyKilocalories)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HealthRangePicker(selection: $selectedRange)

                HStack(spacing: 0) {
                    detailTextMetric("\(workouts.count)", "Workouts")
                    detailTextMetric(healthDurationText(totalDuration), "Total time")
                    detailTextMetric(totalEnergy.map { "\(Int($0)) kcal" } ?? "—", "Energy")
                }
                .cardSurface()

                if workouts.isEmpty {
                    noSampleMessage("No workout samples were returned for \(selectedRange.contextLabel.lowercased()).")
                        .cardSurface()
                } else {
                    Text("\(selectedRange.contextLabel.uppercased()) · \(workouts.count) WORKOUT\(workouts.count == 1 ? "" : "S")").sectionLabel()
                    ForEach(workouts) { workout in
                        HStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: workoutSymbol(workout.title))
                                .font(.title3.weight(.semibold)).foregroundStyle(AppTheme.warning)
                                .frame(width: 48, height: 48)
                                .background(AppTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title).font(.headline)
                                Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(healthDurationText(workout.duration)).font(.subheadline.weight(.bold))
                                Text(workoutSecondaryText(workout)).font(.caption2).foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        .cardSurface()
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.background)
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HealthMobilityDetailView: View {
    let summary: HealthSummary
    @State private var selectedRange: HealthTimeRange

    init(summary: HealthSummary, initialRange: HealthTimeRange = .today) {
        self.summary = summary
        _selectedRange = State(initialValue: initialRange)
    }

    private var metrics: [HealthDetailMetric] {
        [
            metric("Walking Speed", summary.walkingSpeedMilesPerHour, "mph", summary.walkingSpeedDate, "speedometer", AppTheme.info, 2,
                   "Your average walking speed for the latest recorded sample.", trend: summary.trend(for: .walkingSpeed)?.points ?? []),
            metric("Step Length", summary.walkingStepLengthInches, "in", summary.walkingStepLengthDate, "ruler", AppTheme.info, 1,
                   "The distance between the heel strikes of opposite feet while walking.", trend: summary.trend(for: .walkingStepLength)?.points ?? []),
            metric("Walking Asymmetry", summary.walkingAsymmetryPercentage, "%", summary.walkingAsymmetryDate, "figure.walk", AppTheme.warning, 1,
                   "The percentage of walking time in which steps from one foot are faster or slower than the other.", trend: summary.trend(for: .walkingAsymmetry)?.points ?? []),
            metric("Double Support", summary.walkingDoubleSupportPercentage, "%", summary.walkingDoubleSupportDate, "shoeprints.fill", AppTheme.warning, 1,
                   "The percentage of a walk when both feet are touching the ground.", trend: summary.trend(for: .walkingDoubleSupport)?.points ?? []),
            metric("Walking Steadiness", summary.walkingSteadinessPercentage, "%", summary.walkingSteadinessDate, "figure.walk.motion", AppTheme.success, 0,
                   "Apple's estimate of walking steadiness based on mobility data from a supported iPhone.", trend: summary.trend(for: .walkingSteadiness)?.points ?? [])
        ]
    }

    var body: some View {
        HealthMetricDetailPage(
            title: "Mobility",
            introduction: "Walking measurements can add useful context about everyday movement. Values depend on compatible devices and recorded samples.",
            metrics: metrics,
            selectedRange: $selectedRange
        )
    }
}

struct HealthBodyDetailView: View {
    let summary: HealthSummary
    @State private var selectedRange: HealthTimeRange

    init(summary: HealthSummary, initialRange: HealthTimeRange = .today) {
        self.summary = summary
        _selectedRange = State(initialValue: initialRange)
    }

    private var metrics: [HealthDetailMetric] {
        [
            metric("Weight", summary.bodyMassPounds, "lb", summary.bodyMassDate, "scalemass", AppTheme.success, 1,
                   "The latest body-mass measurement stored in Apple Health.", trend: summary.trend(for: .bodyMass)?.points ?? []),
            metric("Body Mass Index", summary.bodyMassIndex, "BMI", summary.bodyMassIndexDate, "person", AppTheme.info, 1,
                   "The latest body mass index value recorded in Apple Health.", trend: summary.trend(for: .bodyMassIndex)?.points ?? []),
            metric("Body Fat", summary.bodyFatPercentage, "%", summary.bodyFatDate, "percent", AppTheme.purple, 1,
                   "The latest recorded percentage of total body mass that is body fat.", trend: summary.trend(for: .bodyFatPercentage)?.points ?? [])
        ]
    }

    var body: some View {
        HealthMetricDetailPage(
            title: "Body Measurements",
            introduction: "These are the latest measurements stored by Apple Health. Orbit does not interpret them or assign health ranges.",
            metrics: metrics,
            selectedRange: $selectedRange
        )
    }
}

struct HealthMindfulnessDetailView: View {
    let summary: HealthSummary
    @State private var selectedRange: HealthTimeRange

    init(summary: HealthSummary, initialRange: HealthTimeRange = .today) {
        self.summary = summary
        _selectedRange = State(initialValue: initialRange)
    }

    private var trend: [HealthTrendPoint] {
        healthPoints(summary.trend(for: .mindfulMinutes)?.points ?? [], in: selectedRange)
    }

    private var totalMinutes: Double? {
        if !trend.isEmpty { return trend.reduce(0) { $0 + $1.value } }
        guard let mindfulness = summary.mindfulness else { return nil }
        return selectedRange == .today ? mindfulness.todayMinutes : mindfulness.sevenDayMinutes
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                HealthRangePicker(selection: $selectedRange)

                if let mindfulness = summary.mindfulness {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2).foregroundStyle(AppTheme.purple)
                            .frame(width: 56, height: 56)
                            .background(AppTheme.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        Text(totalMinutes.map { "\(Int($0.rounded())) min" } ?? "—")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(selectedRange == .today ? "Mindful time today so far" : "Mindful time across the last 7 recorded days")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                        Divider().overlay(AppTheme.separator)
                        HStack(spacing: 0) {
                            detailTextMetric("\(trend.count)", "Recorded days")
                            detailTextMetric(selectedRange == .sevenDays ? "\(mindfulness.sevenDaySessions)" : "—", "7-day sessions")
                            detailTextMetric(mindfulness.latestSessionDate.relativeShort, "Latest")
                        }
                    }
                    .cardSurface()
                } else {
                    noSampleMessage("No mindful-session samples were returned for the last seven days.")
                        .cardSurface()
                }

                HealthTrendChart(
                    points: trend,
                    title: "Mindful minutes",
                    unit: "min",
                    tint: AppTheme.purple,
                    range: selectedRange
                )

                detailInformationCard(
                    title: "Mindful sessions",
                    symbol: "leaf.fill",
                    text: "This includes mindful minutes written to Apple Health by supported meditation, breathing, and mindfulness apps."
                )
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .navigationTitle("Mindfulness")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HealthDetailMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let date: Date?
    let symbol: String
    let tint: Color
    let fractionDigits: Int
    let trend: [HealthTrendPoint]
    let explanation: String
}

private struct HealthMetricDetailPage: View {
    let title: String
    let introduction: String
    let metrics: [HealthDetailMetric]
    @Binding var selectedRange: HealthTimeRange

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                HealthRangePicker(selection: $selectedRange)
                detailInformationCard(title: title, symbol: "info.circle", text: introduction)
                ForEach(metrics) { item in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                            Image(systemName: item.symbol)
                                .font(.headline).foregroundStyle(item.tint)
                                .frame(width: 40, height: 40)
                                .background(item.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.headline)
                                Text(item.date?.formatted(date: .abbreviated, time: .shortened) ?? "No recent sample")
                                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(item.value).font(.title3.weight(.bold))
                                Text(item.unit).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                        Text(item.explanation).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        metricRangeSummary(item)
                    }
                    .cardSurface()

                    HealthTrendChart(
                        points: healthPoints(item.trend, in: selectedRange),
                        title: item.title,
                        unit: item.unit,
                        tint: item.tint,
                        range: selectedRange
                    )
                }
            }
            .padding(AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func metricRangeSummary(_ item: HealthDetailMetric) -> some View {
        let points = healthPoints(item.trend, in: selectedRange)
        if !points.isEmpty {
            let average = points.reduce(0) { $0 + $1.value } / Double(points.count)
            let change = (points.last?.value ?? average) - (points.first?.value ?? average)
            Divider().overlay(AppTheme.separator)
            HStack(spacing: 0) {
                detailTextMetric(format(average, item), "Range average")
                detailTextMetric(format(points.last?.value ?? average, item), "Latest in range")
                detailTextMetric(signedValue(change, item), "First to latest")
            }
        }
    }

    private func format(_ value: Double, _ item: HealthDetailMetric) -> String {
        value.formatted(.number.precision(.fractionLength(item.fractionDigits))) + (item.unit.isEmpty ? "" : " \(item.unit)")
    }

    private func signedValue(_ value: Double, _ item: HealthDetailMetric) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + format(value, item)
    }
}

private struct SleepDetailStage: Identifiable {
    let title: String
    let duration: TimeInterval?
    let tint: Color
    let denominator: TimeInterval?
    var id: String { title }

    var percentage: Double? {
        guard let duration, let denominator, denominator > 0 else { return nil }
        return min(max(duration / denominator * 100, 0), 100)
    }

    var valueText: String {
        guard let duration else { return "—" }
        let percent = percentage.map { " · \(Int($0.rounded()))%" } ?? ""
        return healthDurationText(duration) + percent
    }

    var accessibilityText: String {
        "\(title), \(valueText)"
    }
}

private struct SleepStageTimeline: View {
    let night: HealthSleepNight

    private var segments: [HealthSleepStageSegment] {
        night.stageSegments
            .filter { $0.duration > 0 }
            .sorted { $0.startDate < $1.startDate }
    }

    private var totalDuration: TimeInterval {
        max(night.endDate.timeIntervalSince(night.startDate), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.secondarySurface)

                    ForEach(segments) { segment in
                        let offset = max(0, segment.startDate.timeIntervalSince(night.startDate)) / totalDuration
                        let width = min(segment.duration / totalDuration, 1 - offset)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tint(for: segment.stage))
                            .frame(width: max(2, proxy.size.width * width))
                            .offset(x: proxy.size.width * offset)
                    }
                }
            }
            .frame(height: 30)

            HStack {
                Text(night.startDate.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text(night.endDate.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: AppTheme.Spacing.md) {
                legend("Deep", .deep)
                legend("Core", .core)
                legend("REM", .rem)
                legend("Awake", .awake)
            }
            .font(.caption2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Sleep stage timeline from \(night.startDate.formatted(date: .omitted, time: .shortened)) to \(night.endDate.formatted(date: .omitted, time: .shortened)); \(night.awakenings) recorded awakening\(night.awakenings == 1 ? "" : "s")"
        )
    }

    private func legend(_ title: String, _ stage: HealthSleepStage) -> some View {
        Label {
            Text(title)
        } icon: {
            Circle().fill(tint(for: stage)).frame(width: 6, height: 6)
        }
        .foregroundStyle(AppTheme.secondaryText)
    }

    private func tint(for stage: HealthSleepStage) -> Color {
        switch stage {
        case .deep: AppTheme.accent.opacity(0.82)
        case .core: AppTheme.purple
        case .rem: AppTheme.purple.opacity(0.68)
        case .awake: AppTheme.secondaryText
        case .unspecified: AppTheme.tertiaryText
        }
    }
}

private func metric(
    _ title: String,
    _ value: Double?,
    _ unit: String,
    _ date: Date?,
    _ symbol: String,
    _ tint: Color,
    _ digits: Int,
    _ explanation: String,
    trend: [HealthTrendPoint] = []
) -> HealthDetailMetric {
    HealthDetailMetric(
        id: title,
        title: title,
        value: value?.formatted(.number.precision(.fractionLength(digits))) ?? "—",
        unit: value == nil ? "" : unit,
        date: date,
        symbol: symbol,
        tint: value == nil ? AppTheme.secondaryText : tint,
        fractionDigits: digits,
        trend: trend,
        explanation: explanation
    )
}

private func detailInformationCard(title: String, symbol: String, text: String) -> some View {
    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
        Image(systemName: symbol).foregroundStyle(AppTheme.info).frame(width: 24)
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
}

private func noSampleMessage(_ text: String) -> some View {
    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
        Image(systemName: "waveform.slash").foregroundStyle(AppTheme.secondaryText)
        Text(text).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func detailCompactMetric(_ value: Double?, title: String, unit: String, digits: Int = 0) -> some View {
    let text = value.map { $0.formatted(.number.precision(.fractionLength(digits))) + (unit.isEmpty ? "" : " \(unit)") } ?? "—"
    return detailTextMetric(text, title)
}

private func detailTextMetric(_ value: String, _ title: String) -> some View {
    VStack(spacing: 4) {
        Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.65)
        Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
    }
    .frame(maxWidth: .infinity)
}

private func healthDurationText(_ seconds: TimeInterval) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}

private func optionalSum(_ lhs: TimeInterval?, _ rhs: TimeInterval?) -> TimeInterval? {
    guard lhs != nil || rhs != nil else { return nil }
    return (lhs ?? 0) + (rhs ?? 0)
}

private func workoutSymbol(_ title: String) -> String {
    if title.localizedCaseInsensitiveContains("run") { return "figure.run" }
    if title.localizedCaseInsensitiveContains("walk") { return "figure.walk" }
    if title.localizedCaseInsensitiveContains("cycle") { return "figure.outdoor.cycle" }
    if title.localizedCaseInsensitiveContains("swim") { return "figure.pool.swim" }
    return "figure.strengthtraining.traditional"
}

private func workoutSecondaryText(_ workout: HealthWorkoutSummary) -> String {
    if let distance = workout.distanceMiles {
        return distance.formatted(.number.precision(.fractionLength(1))) + " mi"
    }
    if let energy = workout.energyKilocalories { return "\(Int(energy)) kcal" }
    return "Apple Health"
}

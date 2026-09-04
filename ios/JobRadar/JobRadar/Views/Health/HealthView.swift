import SwiftUI

/// A private, read-only Apple Health dashboard. Calculations stay on device;
/// health context reaches Orbit AI only after the separate opt-in is enabled.
struct HealthView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var health: HealthRepository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedRange: HealthTimeRange = .today
    @State private var showSources = false
    @State private var showAIConsent = false
    @AppStorage("orbit.ai.healthContextEnabled") private var shareHealthWithAssistant = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    switch health.state {
                    case .loaded(let summary):
                        dashboard(summary)
                    case .loading:
                        LoadingStateView(message: "Reading Apple Health…")
                    case .empty:
                        emptyState
                    case .failed(let message):
                        InfoStateView(
                            systemImage: "exclamationmark.triangle",
                            title: "Couldn't load Health",
                            message: message,
                            actionTitle: "Try again"
                        ) { Task { await app.connectHealth() } }
                        .cardSurface()
                    default:
                        connectState
                    }
                }
                .padding(AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xl)
            }
            .background(AppTheme.background)
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSources = true } label: {
                        Image(systemName: "applewatch")
                    }
                    .accessibilityLabel("Health sources and privacy")
                }
            }
            .refreshable { await app.connectHealth() }
            .sheet(isPresented: $showSources) {
                if case let .loaded(summary) = health.state {
                    HealthSourcesView(summary: summary)
                }
            }
            .confirmationDialog(
                "Analyze this Health summary with Orbit AI?",
                isPresented: $showAIConsent,
                titleVisibility: .visible
            ) {
                Button("Share Summary & Analyze") {
                    shareHealthWithAssistant = true
                    openHealthAnalysis()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This enables a Settings preference that shares derived summaries, trends, and baseline comparisons with your configured OpenAI account. Raw HealthKit samples and identifiers are not included.")
            }
            .task {
                // Re-request the complete read-only set after new categories are
                // added. HealthKit prompts only for choices not seen before.
                if app.connections.healthConnected { await app.connectHealth() }
            }
        }
    }

    @ViewBuilder
    private func dashboard(_ summary: HealthSummary) -> some View {
        sourceChip(summary)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("VIEW").sectionLabel()
            HealthRangePicker(selection: $selectedRange)
                .tint(AppTheme.accent)
        }

        overallTrendHero(summary)
        bodyLoadSection(summary)
        insightCard(summary)
        activitySection(summary)
        vitalsSection(summary)
        sleepSection(summary)
        workoutSection(summary)
        mobilitySection(summary)
        bodySection(summary)
        mindfulnessSection(summary)

        Text("Orbit shows recorded patterns for awareness only. Body Load is an app estimate—not measured psychological stress, readiness, medical advice, or a diagnosis.")
            .font(.caption2)
            .foregroundStyle(AppTheme.tertiaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.Spacing.lg)
    }

    private func sourceChip(_ summary: HealthSummary) -> some View {
        Button { showSources = true } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "applewatch")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health").font(.subheadline.weight(.semibold))
                    Text("Refreshed \(summary.updatedAt.relativeShort)")
                        .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Circle().fill(AppTheme.success).frame(width: 6, height: 6)
                Text("Connected").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func overallTrendHero(_ summary: HealthSummary) -> some View {
        let analytics = summary.analytics()
        let score = summary.dailyBalanceScore
        let isToday = selectedRange == .today
        let title = isToday ? balanceTitle(score) : analytics.overallTrend.title
        let value = isToday ? score.map(String.init) ?? "—" : trendSymbol(analytics.overallTrend.direction)
        let detail = isToday
            ? "A snapshot from available sleep and activity recorded today so far."
            : analytics.overallTrend.detail

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                Label("OVERALL TREND", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                Text(selectedRange.contextLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.5))
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: AppTheme.Spacing.xl) {
                    trendBadge(value: value, progress: isToday ? Double(score ?? 0) / 100 : nil)
                    trendCopy(title: title, detail: detail, summary: summary, analytics: analytics)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HStack {
                        trendBadge(value: value, progress: isToday ? Double(score ?? 0) / 100 : nil)
                        Spacer()
                    }
                    trendCopy(title: title, detail: detail, summary: summary, analytics: analytics)
                }
            }

            HealthMiniTrend(
                points: healthPoints(summary.stepTrend, in: selectedRange),
                tint: AppTheme.accent,
                accessibilityTitle: "Step trend",
                emptyText: isToday ? "Today is still being recorded" : "More recorded days are needed"
            )
            .padding(AppTheme.Spacing.md)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x111114), Color(hex: 0x190C10), Color(hex: 0x0B0B0D)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.32), lineWidth: 1)
        )
    }

    private func trendBadge(value: String, progress: Double?) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.09), lineWidth: 8)
            if let progress {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0.08, to: 0.92)
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(value)
                .font(.system(size: value.count > 2 ? 31 : 39, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
    }

    private func trendCopy(
        title: String,
        detail: String,
        summary: HealthSummary,
        analytics: HealthAnalyticsResult
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            if selectedRange == .today {
                trendFactor("Sleep", value: summary.sleepScore.map { "\($0) / 100" } ?? "Collecting")
                trendFactor("Activity", value: summary.activityScore.map { "\($0) / 100" } ?? "Collecting")
            } else if !analytics.overallTrend.comparisons.isEmpty {
                ForEach(analytics.overallTrend.comparisons.prefix(2)) { comparison in
                    trendFactor(comparison.title, value: signedPercent(comparison.percentChange))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func trendFactor(_ title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(AppTheme.accent).frame(width: 5, height: 5)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text(value).font(.caption.weight(.bold)).foregroundStyle(.white)
        }
    }

    private func bodyLoadSection(_ summary: HealthSummary) -> some View {
        let estimate = summary.analytics().bodyLoad
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeader(title: "Stress Signals")
            NavigationLink(destination: HealthBodyLoadDetailView(estimate: estimate)) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(bodyLoadTint(estimate).opacity(0.12))
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(bodyLoadTint(estimate))
                        }
                        .frame(width: 54, height: 54)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("BODY LOAD ESTIMATE").sectionLabel()
                            Text(estimate.level.title).font(.title3.weight(.bold))
                            Text(estimate.detail)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(estimate.index.map(String.init) ?? "—")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(bodyLoadTint(estimate))
                            Text(estimate.index == nil ? "COLLECTING" : "INDEX")
                                .font(.system(size: 7, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                    }

                    if !estimate.factors.isEmpty {
                        Divider().overlay(AppTheme.separator)
                        ForEach(estimate.factors.prefix(3)) { factor in
                            loadFactorRow(factor)
                        }
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "info.circle").foregroundStyle(AppTheme.accent)
                        Text("Compares HRV, resting heart rate, breathing, sleep, and wrist temperature with your personal baseline. It cannot measure mental stress or diagnose illness.")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                }
                .cardSurface()
            }
            .buttonStyle(.plain)
        }
    }

    private func loadFactorRow(_ factor: HealthLoadFactor) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: loadFactorSymbol(factor.state))
                .font(.caption.weight(.bold))
                .foregroundStyle(loadFactorTint(factor.state))
                .frame(width: 24, height: 24)
                .background(loadFactorTint(factor.state).opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.title).font(.caption.weight(.semibold))
                Text("Now \(factorValue(factor.currentValue, factor.unit)) · baseline \(factorValue(factor.baselineValue, factor.unit))")
                    .font(.caption2).foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Text(signedPercent(factor.percentDifference))
                .font(.caption.weight(.bold))
                .foregroundStyle(loadFactorTint(factor.state))
        }
        .accessibilityElement(children: .combine)
    }

    private func insightCard(_ summary: HealthSummary) -> some View {
        let insight = localInsight(summary)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("ORBIT INSIGHT").sectionLabel()
                    Text(insight.title).font(.headline)
                    Text(insight.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                if shareHealthWithAssistant {
                    openHealthAnalysis()
                } else {
                    showAIConsent = true
                }
            } label: {
                Label("Analyze with Orbit", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            .accessibilityHint("Uses your optional Health sharing preference and opens Orbit Chat")
        }
        .cardSurface()
    }

    private func activitySection(_ summary: HealthSummary) -> some View {
        let points = healthPoints(summary.stepTrend, in: selectedRange)
        let moveValue = activityRangeValue(summary.activeEnergyKilocalories, points: summary.activeEnergyTrend)
        let exerciseValue = activityRangeValue(summary.exerciseMinutes, points: summary.exerciseTrend)
        let standValue = selectedRange == .today ? summary.standHours : nil
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle("Activity")
            NavigationLink(destination: HealthActivityDetailView(summary: summary, initialRange: selectedRange)) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppTheme.Spacing.xl) {
                            HealthRings(
                                move: moveValue,
                                exercise: exerciseValue,
                                stand: standValue,
                                moveGoal: summary.moveGoalKilocalories ?? 600,
                                exerciseGoal: summary.exerciseGoalMinutes ?? 30,
                                standGoal: summary.standGoalHours ?? 12
                            )
                            .frame(width: 122, height: 122)
                            activityGoals(summary)
                        }
                        VStack(spacing: AppTheme.Spacing.lg) {
                            HealthRings(
                                move: moveValue,
                                exercise: exerciseValue,
                                stand: standValue,
                                moveGoal: summary.moveGoalKilocalories ?? 600,
                                exerciseGoal: summary.exerciseGoalMinutes ?? 30,
                                standGoal: summary.standGoalHours ?? 12
                            )
                            .frame(width: 122, height: 122)
                            activityGoals(summary)
                        }
                    }

                    Divider().overlay(AppTheme.separator)
                    HStack(spacing: 0) {
                        compactMetric(activityMetric(summary.steps, points: summary.stepTrend, digits: 0), "Steps")
                        compactMetric(activityMetric(summary.activeEnergyKilocalories, points: summary.activeEnergyTrend, digits: 0, suffix: " kcal"), "Move")
                        compactMetric(activityMetric(summary.exerciseMinutes, points: summary.exerciseTrend, digits: 0, suffix: " min"), "Exercise")
                    }
                    HealthMiniTrend(points: points, tint: AppTheme.accent, accessibilityTitle: "Steps")
                }
                .cardSurface()
            }
            .buttonStyle(.plain)
        }
    }

    private func activityGoals(_ summary: HealthSummary) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            goalRow("Move", value: activityRangeValue(summary.activeEnergyKilocalories, points: summary.activeEnergyTrend), goal: summary.moveGoalKilocalories ?? 600, unit: "kcal", tint: AppTheme.coral)
            goalRow("Exercise", value: activityRangeValue(summary.exerciseMinutes, points: summary.exerciseTrend), goal: summary.exerciseGoalMinutes ?? 30, unit: "min", tint: AppTheme.warning)
            if selectedRange == .today {
                goalRow("Stand", value: summary.standHours, goal: summary.standGoalHours ?? 12, unit: "hr", tint: AppTheme.info)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func vitalsSection(_ summary: HealthSummary) -> some View {
        let vitals = vitalItems(summary)
        let minimum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 260 : 150
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle("Vitals")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: AppTheme.Spacing.sm)], spacing: AppTheme.Spacing.sm) {
                ForEach(vitals) { vital in
                    NavigationLink(destination: HealthSignalDetailView(vital: vital, initialRange: selectedRange)) {
                        HealthVitalCard(vital: vital, range: selectedRange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sleepSection(_ summary: HealthSummary) -> some View {
        let nights = sleepNights(summary)
        let latest = summary.sleepHistory.max { $0.endDate < $1.endDate }
        let duration = selectedRange == .today
            ? latest?.asleepDuration ?? summary.sleepDuration
            : average(nights.map(\.asleepDuration))
        let trend = nights.map { HealthTrendPoint(date: $0.sleepDay, value: $0.asleepDuration / 3600) }

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle("Sleep")
            NavigationLink(destination: HealthSleepDetailView(summary: summary, initialRange: selectedRange)) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(duration.map(durationText) ?? "—")
                                .font(.largeTitle.weight(.bold))
                            Text(selectedRange == .today ? "LATEST SLEEP" : "AVERAGE · \(nights.count) RECORDED NIGHTS")
                                .sectionLabel()
                        }
                        Spacer()
                        Image(systemName: "moon.stars.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.purple)
                            .frame(width: 52, height: 52)
                            .background(AppTheme.purple.opacity(0.1), in: Circle())
                    }

                    if let latest {
                        Text("LATEST NIGHT STAGES").sectionLabel()
                        SleepStageBar(night: latest)
                        HStack(spacing: 0) {
                            sleepMetric(latest.remDuration, "REM", AppTheme.purple.opacity(0.72), total: latest.asleepDuration)
                            sleepMetric(latest.coreDuration, "Core", AppTheme.purple, total: latest.asleepDuration)
                            sleepMetric(latest.deepDuration, "Deep", AppTheme.accent.opacity(0.8), total: latest.asleepDuration)
                            sleepMetric(latest.awakeDuration, "Awake", AppTheme.secondaryText, total: latest.inBedDuration)
                        }
                    } else {
                        Text("No recent sleep stages were returned by Apple Health.")
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }

                    HealthMiniTrend(points: trend, tint: AppTheme.purple, accessibilityTitle: "Sleep duration")
                }
                .cardSurface()
            }
            .buttonStyle(.plain)
        }
    }

    private func workoutSection(_ summary: HealthSummary) -> some View {
        let workouts = filteredWorkouts(summary)
        let latest = workouts.first
        let minutes = workouts.reduce(0) { $0 + $1.duration } / 60
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle("Workouts")
            NavigationLink(destination: HealthWorkoutsDetailView(summary: summary, initialRange: selectedRange)) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: latest.map { workoutSymbol($0.title) } ?? "figure.run")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(latest?.title ?? "No workout in this range").font(.headline)
                        Text(latest?.startedAt.formatted(date: .abbreviated, time: .shortened) ?? selectedRange.contextLabel)
                            .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(workouts.count)").font(.title3.weight(.bold))
                        Text("\(Int(minutes)) min total").font(.caption2).foregroundStyle(AppTheme.secondaryText)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
                }
                .cardSurface()
            }
            .buttonStyle(.plain)
        }
    }

    private func mobilitySection(_ summary: HealthSummary) -> some View {
        return categorySection(
            title: "Mobility",
            destination: HealthMobilityDetailView(summary: summary, initialRange: selectedRange),
            symbol: "figure.walk.motion",
            tint: AppTheme.info,
            description: "Walking quality and steadiness",
            metrics: [
                (rangeValue(summary.walkingSpeedMilesPerHour, metric: .walkingSpeed, summary: summary, digits: 1, unit: " mph"), "Speed"),
                (rangeValue(summary.walkingStepLengthInches, metric: .walkingStepLength, summary: summary, digits: 1, unit: " in"), "Step length"),
                (rangeValue(summary.walkingSteadinessPercentage, metric: .walkingSteadiness, summary: summary, digits: 0, unit: "%"), "Steadiness")
            ],
            trend: summary.trend(for: .walkingSpeed)?.points ?? []
        )
    }

    private func bodySection(_ summary: HealthSummary) -> some View {
        categorySection(
            title: "Body Measurements",
            destination: HealthBodyDetailView(summary: summary, initialRange: selectedRange),
            symbol: "scalemass",
            tint: AppTheme.success,
            description: "Measurements returned by Apple Health",
            metrics: [
                (rangeValue(summary.bodyMassPounds, metric: .bodyMass, summary: summary, digits: 1, unit: " lb"), "Weight"),
                (rangeValue(summary.bodyMassIndex, metric: .bodyMassIndex, summary: summary, digits: 1), "BMI"),
                (rangeValue(summary.bodyFatPercentage, metric: .bodyFatPercentage, summary: summary, digits: 1, unit: "%"), "Body fat")
            ],
            trend: summary.trend(for: .bodyMass)?.points ?? []
        )
    }

    private func mindfulnessSection(_ summary: HealthSummary) -> some View {
        let points = healthPoints(summary.trend(for: .mindfulMinutes)?.points ?? [], in: selectedRange)
        let selectedMinutes: Double? = if selectedRange == .today {
            summary.mindfulness?.todayMinutes
        } else if !points.isEmpty {
            points.reduce(0) { $0 + $1.value }
        } else {
            summary.mindfulness?.sevenDayMinutes
        }
        let averageMinutes = average(points.map(\.value))
        return categorySection(
            title: "Mindfulness",
            destination: HealthMindfulnessDetailView(summary: summary, initialRange: selectedRange),
            symbol: "brain.head.profile",
            tint: AppTheme.purple,
            description: "Recorded mindful minutes",
            metrics: [
                (selectedMinutes.map { "\(Int($0.rounded())) min" } ?? "—", selectedRange == .today ? "Today" : "7-day total"),
                (averageMinutes.map { "\(Int($0.rounded())) min" } ?? "—", "Daily average"),
                (selectedRange == .sevenDays ? summary.mindfulness.map { "\($0.sevenDaySessions)" } ?? "—" : "—", "7-day sessions")
            ],
            trend: summary.trend(for: .mindfulMinutes)?.points ?? []
        )
    }

    private func categorySection<Destination: View>(
        title: String,
        destination: Destination,
        symbol: String,
        tint: Color,
        description: String,
        metrics: [(value: String, title: String)],
        trend: [HealthTrendPoint]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle(title)
            NavigationLink(destination: destination) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: symbol)
                            .font(.title3.weight(.semibold)).foregroundStyle(tint)
                            .frame(width: 44, height: 44)
                            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.headline)
                            Text(description).font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                            compactMetric(metric.value, metric.title)
                        }
                    }
                    HealthMiniTrend(
                        points: healthPoints(trend, in: selectedRange),
                        tint: tint,
                        accessibilityTitle: "\(title) trend"
                    )
                }
                .cardSurface()
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            Text(selectedRange.contextLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func goalRow(_ title: String, value: Double?, goal: Double, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(AppTheme.secondaryText)
                Spacer()
                Text(value.map { "\(Int($0)) / \(Int(goal)) \(unit)" } ?? "No data")
                    .font(.caption2.weight(.semibold))
            }
            ProgressView(value: min(value ?? 0, max(goal, 1)), total: max(goal, 1)).tint(tint)
        }
    }

    private func compactMetric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.65)
            Text(title).font(.caption2).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func sleepMetric(_ duration: TimeInterval, _ title: String, _ tint: Color, total: TimeInterval?) -> some View {
        let percent = total.flatMap { $0 > 0 ? duration / $0 * 100 : nil }
        return VStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(durationText(duration)).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.65)
            Text(percent.map { "\(title) · \(Int($0.rounded()))%" } ?? title)
                .font(.caption2).foregroundStyle(AppTheme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var connectState: some View {
        InfoStateView(
            systemImage: "heart",
            title: "Connect Apple Health",
            message: "See sleep, activity, workouts, trends, and supported Watch signals in one private dashboard. Orbit requests read access only.",
            actionTitle: "Connect Apple Health"
        ) { Task { await app.connectHealth() } }
        .cardSurface()
    }

    private var emptyState: some View {
        InfoStateView(
            systemImage: "applewatch",
            title: "No recent health data",
            message: "Apple Health is connected, but no approved category has a readable recent sample. Wear your Watch normally or manage data access in Health.",
            actionTitle: "Review Access"
        ) { Task { await app.connectHealth() } }
        .cardSurface()
    }

    private func openHealthAnalysis() {
        app.openAssistant(
            prompt: "Analyze my current Health summary, Today versus the last 7 recorded days, my Body Load baseline factors, and my recent sleep. Explain only the supplied data, highlight missing coverage, and do not diagnose me or give medical advice."
        )
    }

    private func localInsight(_ summary: HealthSummary) -> (title: String, detail: String) {
        let analytics = summary.analytics()
        if analytics.bodyLoad.level == .higherThanUsual {
            let factor = analytics.bodyLoad.factors.first?.title.lowercased() ?? "multiple recorded signals"
            return ("Body-load signals are above baseline", "The largest recorded difference is in \(factor). Open Stress Signals to see the exact comparison and coverage.")
        }
        if let latest = summary.sleepHistory.max(by: { $0.endDate < $1.endDate }) {
            return ("Latest sleep: \(durationText(latest.asleepDuration))", "Apple Health recorded sleep ending \(latest.endDate.relativeShort), including \(latest.awakenings) awakening\(latest.awakenings == 1 ? "" : "s") in the selected source.")
        }
        if let steps = summary.steps {
            return ("\(Int(steps).formatted()) steps today", "This is today's recorded total so far; the Activity detail compares it with other recorded days.")
        }
        return ("Your health picture is taking shape", "Keep wearing Apple Watch to build trend coverage and a personal baseline.")
    }

    private func activityMetric(
        _ current: Double?,
        points: [HealthTrendPoint],
        digits: Int,
        suffix: String = ""
    ) -> String {
        let value = activityRangeValue(current, points: points)
        return value.map { $0.formatted(.number.precision(.fractionLength(digits))) + suffix } ?? "—"
    }

    private func activityRangeValue(
        _ current: Double?,
        points: [HealthTrendPoint]
    ) -> Double? {
        selectedRange == .today
            ? current
            : average(healthPoints(points, in: .sevenDays).map(\.value))
    }

    private func rangeValue(
        _ current: Double?,
        metric: HealthTrendMetric,
        summary: HealthSummary,
        digits: Int,
        unit: String = ""
    ) -> String {
        let value: Double?
        if selectedRange == .today {
            value = current
        } else {
            value = average(healthPoints(summary.trend(for: metric)?.points ?? [], in: .sevenDays).map(\.value))
        }
        return value.map { $0.formatted(.number.precision(.fractionLength(digits))) + unit } ?? "—"
    }

    private func sleepNights(_ summary: HealthSummary) -> [HealthSleepNight] {
        let sorted = summary.sleepHistory.sorted { $0.sleepDay < $1.sleepDay }
        if selectedRange == .today { return sorted.last.map { [$0] } ?? [] }
        return sorted.filter { HealthTimeRange.sevenDays.contains($0.sleepDay) }
    }

    private func filteredWorkouts(_ summary: HealthSummary) -> [HealthWorkoutSummary] {
        let values = summary.workouts.isEmpty ? summary.latestWorkout.map { [$0] } ?? [] : summary.workouts
        return values
            .filter { selectedRange.contains($0.startedAt) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func average(_ values: [Double]) -> Double? {
        let valid = values.filter(\.isFinite)
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private func factorValue(_ value: Double, _ unit: String) -> String {
        let digits = abs(value) >= 100 ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(digits))) + (unit.isEmpty ? "" : " \(unit)")
    }

    private func signedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func bodyLoadTint(_ estimate: HealthLoadEstimate) -> Color {
        switch estimate.level {
        case .collecting: AppTheme.secondaryText
        case .lowerThanUsual: AppTheme.info
        case .typical: AppTheme.success
        case .higherThanUsual: AppTheme.warning
        }
    }

    private func loadFactorTint(_ state: HealthLoadFactorState) -> Color {
        switch state {
        case .addsLoad: AppTheme.warning
        case .nearBaseline: AppTheme.success
        case .reducesLoad: AppTheme.info
        }
    }

    private func loadFactorSymbol(_ state: HealthLoadFactorState) -> String {
        switch state {
        case .addsLoad: "arrow.up"
        case .nearBaseline: "equal"
        case .reducesLoad: "arrow.down"
        }
    }

    private func trendSymbol(_ direction: HealthOverallDirection) -> String {
        switch direction {
        case .building: "…"
        case .steady: "→"
        case .upward: "↗"
        case .downward: "↘"
        case .mixed: "↕"
        }
    }

    private func balanceTitle(_ score: Int?) -> String {
        guard let score else { return "Building today's picture" }
        return switch score {
        case 85...: "Strong goal progress"
        case 65..<85: "Today's signals are balanced"
        default: "Today is still developing"
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func workoutSymbol(_ title: String) -> String {
        if title.localizedCaseInsensitiveContains("run") { return "figure.run" }
        if title.localizedCaseInsensitiveContains("walk") { return "figure.walk" }
        if title.localizedCaseInsensitiveContains("cycle") { return "figure.outdoor.cycle" }
        if title.localizedCaseInsensitiveContains("swim") { return "figure.pool.swim" }
        return "figure.strengthtraining.traditional"
    }

    private func vitalItems(_ summary: HealthSummary) -> [HealthVital] {
        [
            vital(id: "heart", title: "Heart Rate", value: summary.latestHeartRate, unit: "bpm", date: summary.latestHeartRateDate, symbol: "heart.fill", tint: AppTheme.coral, trend: summary.trend(for: .heartRate)?.points ?? []),
            vital(id: "hrv", title: "HRV", value: summary.heartRateVariability, unit: "ms", date: summary.heartRateVariabilityDate, symbol: "waveform.path.ecg", tint: AppTheme.success, trend: summary.trend(for: .heartRateVariability)?.points ?? []),
            vital(id: "resting", title: "Resting HR", value: summary.restingHeartRate, unit: "bpm", date: summary.restingHeartRateDate, symbol: "heart", tint: AppTheme.coral, trend: summary.trend(for: .restingHeartRate)?.points ?? []),
            vital(id: "respiratory", title: "Respiratory", value: summary.respiratoryRate, unit: "/min", date: summary.respiratoryRateDate, symbol: "lungs.fill", tint: AppTheme.info, fractionDigits: 1, trend: summary.trend(for: .respiratoryRate)?.points ?? []),
            vital(id: "oxygen", title: "Blood Oxygen", value: summary.oxygenSaturation, unit: "%", date: summary.oxygenSaturationDate, symbol: "drop.fill", tint: AppTheme.info, trend: summary.trend(for: .oxygenSaturation)?.points ?? []),
            vital(id: "temperature", title: "Wrist Temp", value: summary.wristTemperatureFahrenheit, unit: "°F", date: summary.wristTemperatureDate, symbol: "thermometer.medium", tint: AppTheme.warning, fractionDigits: 1, trend: summary.trend(for: .wristTemperature)?.points ?? []),
            vital(id: "fitness", title: "Cardio Fitness", value: summary.cardioFitness, unit: "VO₂", date: summary.cardioFitnessDate, symbol: "heart.text.square", tint: AppTheme.purple, fractionDigits: 1, trend: summary.trend(for: .cardioFitness)?.points ?? []),
            vital(id: "walking-heart", title: "Walking HR", value: summary.walkingHeartRateAverage, unit: "bpm", date: summary.walkingHeartRateAverageDate, symbol: "figure.walk", tint: AppTheme.coral, trend: summary.trend(for: .walkingHeartRateAverage)?.points ?? []),
            vital(id: "recovery", title: "Heart Recovery", value: summary.heartRateRecovery, unit: "bpm", date: summary.heartRateRecoveryDate, symbol: "heart.circle", tint: AppTheme.success, trend: summary.trend(for: .heartRateRecovery)?.points ?? [])
        ]
    }

    private func vital(
        id: String,
        title: String,
        value: Double?,
        unit: String,
        date: Date?,
        symbol: String,
        tint: Color,
        fractionDigits: Int = 0,
        trend: [HealthTrendPoint],
        explanation: String? = nil
    ) -> HealthVital {
        HealthVital(
            id: id,
            title: title,
            value: value?.formatted(.number.precision(.fractionLength(fractionDigits))) ?? "—",
            unit: value == nil ? "" : unit,
            fractionDigits: fractionDigits,
            detail: date?.relativeShort ?? "No sample",
            symbol: symbol,
            tint: value == nil ? AppTheme.secondaryText : tint,
            trend: trend,
            explanation: explanation ?? healthExplanation(id)
        )
    }

    private func healthExplanation(_ id: String) -> String {
        switch id {
        case "heart": "Your most recent heart-rate sample recorded in Apple Health."
        case "hrv": "Heart-rate variability is variation between heartbeats. Orbit shows Apple Health's SDNN values and personal trend only."
        case "resting": "Resting heart rate is recorded while you are inactive."
        case "respiratory": "Respiratory rate is the recorded number of breaths per minute."
        case "oxygen": "Blood oxygen is the latest oxygen-saturation percentage returned by Apple Health."
        case "temperature": "Wrist temperature is an Apple Watch wrist measurement, not core body temperature."
        case "fitness": "Cardio fitness is Apple Health's estimated VO₂ max value."
        case "walking-heart": "Walking heart rate is the recorded average while walking."
        case "recovery": "Heart-rate recovery records the decrease one minute after exercise."
        default: "This is a sample returned by Apple Health."
        }
    }
}

private struct HealthRings: View {
    let move: Double?
    let exercise: Double?
    let stand: Double?
    let moveGoal: Double
    let exerciseGoal: Double
    let standGoal: Double

    var body: some View {
        ZStack {
            ring(progress: (move ?? 0) / max(moveGoal, 1), color: AppTheme.coral, width: 10).padding(3)
            ring(progress: (exercise ?? 0) / max(exerciseGoal, 1), color: AppTheme.warning, width: 9).padding(17)
            ring(progress: (stand ?? 0) / max(standGoal, 1), color: AppTheme.info, width: 8).padding(30)
            Image(systemName: "bolt.fill").font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity progress for Move, Exercise, and Stand")
    }

    private func ring(progress: Double, color: Color, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(AppTheme.secondarySurface, lineWidth: width)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct HealthVital: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let fractionDigits: Int
    let detail: String
    let symbol: String
    let tint: Color
    let trend: [HealthTrendPoint]
    let explanation: String
}

private struct HealthVitalCard: View {
    let vital: HealthVital
    let range: HealthTimeRange

    private var rangePoints: [HealthTrendPoint] {
        healthPoints(vital.trend, in: range)
    }

    private var displayedValue: String {
        guard range == .sevenDays, !rangePoints.isEmpty else { return vital.value }
        let value = rangePoints.reduce(0) { $0 + $1.value } / Double(rangePoints.count)
        return value.formatted(.number.precision(.fractionLength(vital.fractionDigits)))
    }

    private var displayedDetail: String {
        range == .sevenDays && !rangePoints.isEmpty
            ? "Average · \(rangePoints.count) recorded day\(rangePoints.count == 1 ? "" : "s")"
            : vital.detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Image(systemName: vital.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(vital.tint)
                    .frame(width: 30, height: 30)
                    .background(vital.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            Text(vital.title.uppercased()).sectionLabel()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(displayedValue).font(.title2.weight(.bold)).contentTransition(.numericText())
                Text(vital.unit).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
            }
            Text(displayedDetail).font(.caption2).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
            HealthMiniTrend(
                points: rangePoints,
                tint: vital.tint,
                accessibilityTitle: vital.title
            )
        }
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .leading)
        .cardSurface(padding: AppTheme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(vital.title) details")
    }
}

private struct SleepStageBar: View {
    let night: HealthSleepNight

    var body: some View {
        let stages: [(String, Double, Color)] = [
            ("Deep", night.deepDuration, AppTheme.accent.opacity(0.8)),
            ("Core", night.coreDuration, AppTheme.purple),
            ("REM", night.remDuration, AppTheme.purple.opacity(0.7)),
            ("Awake", night.awakeDuration, AppTheme.secondaryText.opacity(0.55))
        ]
        let total = max(stages.reduce(0) { $0 + $1.1 }, 1)
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stage.2)
                        .frame(width: max(3, proxy.size.width * stage.1 / total))
                }
            }
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            stages.map { "\($0.0) \(Int($0.1 / 60)) minutes" }.joined(separator: ", ")
        )
    }
}

private struct HealthSourcesView: View {
    let summary: HealthSummary
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @AppStorage("orbit.ai.healthContextEnabled") private var shareHealthWithAssistant = false

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Label("Connected to Apple Health", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                    LabeledContent("Latest refresh", value: summary.updatedAt.relativeShort)
                    LabeledContent("Signals with data", value: "\(summary.availableSignalCount)")
                    LabeledContent("Nightly sleep records", value: "\(summary.sleepHistory.count)")
                }
                Section("Privacy") {
                    Label("Read only", systemImage: "eye")
                    Label("Health calculations stay on device", systemImage: "lock.fill")
                    Toggle("Share derived summaries with Orbit AI", isOn: $shareHealthWithAssistant)
                    Text("When enabled, derived summaries and trends may be sent to your configured OpenAI account only when you use the assistant. Orbit does not send raw HealthKit samples or identifiers.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                Section("Manage access") {
                    Button {
                        dismiss()
                        Task { await app.connectHealth() }
                    } label: {
                        Label("Check for New Categories", systemImage: "checklist")
                    }
                    Text("Open Health → profile picture → Apps → Orbit to review access. Apple does not tell apps whether a category was declined or simply has no data.")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Health & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    let app = PreviewSupport.appState()
    return HealthView()
        .environmentObject(app)
        .environmentObject(app.health)
}

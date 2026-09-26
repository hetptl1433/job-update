import SwiftUI

/// A private, read-only Apple Health dashboard. Calculations stay on device;
/// health context reaches Orbit AI only after the separate opt-in is enabled.
struct HealthView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var health: HealthRepository
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orbitWideLayout) private var isWide
    @State private var selectedRange: HealthTimeRange = .today
    @State private var showSources = false
    @State private var showAIConsent = false
    @AppStorage("orbit.ai.healthContextEnabled") private var shareHealthWithAssistant = false

    var body: some View {
        NavigationStack {
            ScrollView {
                // The dashboard holds many charts. A lazy stack lays out only
                // what's on screen; measuring every chart at once in
                // OrbitColumns made the phone layout slow enough to freeze.
                // Only a wide iPad, with room for two columns, uses it.
                Group {
                    if isWide {
                        OrbitColumns { pageContent }
                    } else {
                        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xl) { pageContent }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.xxl)
                // Switching Today / 7 Days morphs values, rings, and charts.
                .animation(.smooth(duration: 0.35), value: selectedRange)
            }
            .background(AppTheme.background)
            .orbitNavigationChrome()
            // Pull to refresh re-reads data. Permission checks stay with the
            // connect buttons and "Check for New Categories".
            .refreshable {
                if app.connections.healthConnected { await health.refresh() } else { await app.connectHealth() }
            }
            // Opens from the heading in every state, so it must never be blank.
            .sheet(isPresented: $showSources) {
                HealthSourcesView(summary: health.state.value, isConnected: app.connections.healthConnected)
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
                // Coming back from a detail page within a minute keeps what's shown.
                guard app.connections.healthConnected else { return }
                if let updated = health.state.value?.updatedAt, Date.now.timeIntervalSince(updated) < 60 { return }
                await app.connectHealth()
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        OrbitPageHeading(
            title: "Health",
            subtitle: "A clearer picture of you.",
            actionTitle: "Health sources and privacy",
            symbol: "applewatch",
            action: { showSources = true }
        )
        switch health.state {
        case .loaded(let summary):
            dashboard(summary)
        case .loading:
            HealthLoadingSkeleton()
                .transition(.opacity)
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

    @ViewBuilder
    private func dashboard(_ summary: HealthSummary) -> some View {
        // Computed once per render; three sections read it.
        let analytics = summary.analytics()
        sourceChip(summary).orbitAppear(0)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("VIEW").sectionLabel()
            HealthRangePicker(selection: $selectedRange)
                .tint(AppTheme.accent)
        }
        .orbitAppear(1)

        overallTrendHero(summary, analytics: analytics).orbitAppear(2)
        // On a wide iPad: movement and vitals on the left, recovery on the right.
        activitySection(summary).orbitAppear(3).orbitColumn(.leading)
        bodyLoadSection(analytics.bodyLoad).orbitAppear(3).orbitColumn(.trailing)
        vitalsSection(summary).orbitAppear(4).orbitColumn(.leading)
        sleepSection(summary).orbitAppear(4).orbitColumn(.trailing)
        insightCard(summary, analytics: analytics).orbitAppear(5).orbitColumn(.leading)
        workoutSection(summary).orbitAppear(5).orbitColumn(.trailing)
        mobilitySection(summary).orbitAppear(6).orbitColumn(.leading)
        bodySection(summary).orbitAppear(6).orbitColumn(.trailing)
        mindfulnessSection(summary).orbitAppear(7).orbitColumn(.leading)

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
                    Text(health.isRefreshing ? "Refreshing…" : "Refreshed \(summary.updatedAt.relativeShort)")
                        .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                        .contentTransition(.opacity)
                }
                Spacer()
                if health.isRefreshing {
                    ProgressView().controlSize(.mini).tint(AppTheme.secondaryText)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Circle().fill(AppTheme.success).frame(width: 6, height: 6)
                        .transition(.opacity.combined(with: .scale))
                }
                Text("Connected").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
            }
            .animation(.easeInOut(duration: 0.25), value: health.isRefreshing)
            .contentShape(Rectangle())
        }
        .buttonStyle(OrbitPressStyle())
    }

    private func overallTrendHero(_ summary: HealthSummary, analytics: HealthAnalyticsResult) -> some View {
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
        HealthTrendBadge(value: value, progress: progress)
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

    private func bodyLoadSection(_ estimate: HealthLoadEstimate) -> some View {
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
            .buttonStyle(OrbitPressStyle())
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

    private func insightCard(_ summary: HealthSummary, analytics: HealthAnalyticsResult) -> some View {
        let insight = localInsight(summary, analytics: analytics)
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
            .buttonStyle(OrbitPressStyle())
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
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: vitals.count, by: columnCount).map {
            Array(vitals[$0..<min($0 + columnCount, vitals.count)])
        }
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            sectionTitle("Vitals")
            // A plain Grid, not LazyVGrid: a lazy grid measured inside
            // OrbitColumns can re-measure without end and freeze the screen.
            Grid(horizontalSpacing: AppTheme.Spacing.sm, verticalSpacing: AppTheme.Spacing.sm) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index]) { vital in
                            NavigationLink(destination: HealthSignalDetailView(vital: vital, initialRange: selectedRange)) {
                                HealthVitalCard(vital: vital, range: selectedRange)
                            }
                            .buttonStyle(OrbitPressStyle())
                        }
                        if rows[index].count < columnCount {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
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
                                .contentTransition(.numericText())
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
            .buttonStyle(OrbitPressStyle())
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
                        Text("\(workouts.count)").font(.title3.weight(.bold)).contentTransition(.numericText())
                        Text("\(Int(minutes)) min total").font(.caption2).foregroundStyle(AppTheme.secondaryText)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.tertiaryText)
                }
                .cardSurface()
            }
            .buttonStyle(OrbitPressStyle())
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
            .buttonStyle(OrbitPressStyle())
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
                    .contentTransition(.numericText())
            }
            ProgressView(value: min(value ?? 0, max(goal, 1)), total: max(goal, 1)).tint(tint)
        }
    }

    private func compactMetric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.65)
                .contentTransition(.numericText())
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

    private func localInsight(_ summary: HealthSummary, analytics: HealthAnalyticsResult) -> (title: String, detail: String) {
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

/// The daily score ring. It fills from empty the first time it appears.
private struct HealthTrendBadge: View {
    let value: String
    let progress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.09), lineWidth: 8)
            Circle()
                .trim(from: progress == nil ? 0.08 : 0, to: revealed ? end : (progress == nil ? 0.08 : 0))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: AppTheme.accent.opacity(revealed ? 0.35 : 0), radius: 6)
            Text(value)
                .font(.system(size: value.count > 2 ? 31 : 39, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: end)
        .onAppear { reveal($revealed, reduceMotion: reduceMotion) }
    }

    private var end: Double {
        guard let progress else { return 0.92 }
        return min(max(progress, 0), 1)
    }
}

private struct HealthRings: View {
    let move: Double?
    let exercise: Double?
    let stand: Double?
    let moveGoal: Double
    let exerciseGoal: Double
    let standGoal: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            ring(progress: (move ?? 0) / max(moveGoal, 1), color: AppTheme.coral, width: 10).padding(3)
            ring(progress: (exercise ?? 0) / max(exerciseGoal, 1), color: AppTheme.warning, width: 9).padding(17)
            ring(progress: (stand ?? 0) / max(standGoal, 1), color: AppTheme.info, width: 8).padding(30)
            Image(systemName: "bolt.fill").font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: [move, exercise, stand])
        .onAppear { reveal($revealed, reduceMotion: reduceMotion) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity progress for Move, Exercise, and Stand")
    }

    private func ring(progress: Double, color: Color, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(AppTheme.secondarySurface, lineWidth: width)
            Circle()
                .trim(from: 0, to: revealed ? min(max(progress, 0), 1) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Sweeps a ring from empty to its value once, like Apple's activity rings.
@MainActor
private func reveal(_ revealed: Binding<Bool>, reduceMotion: Bool) {
    guard !revealed.wrappedValue else { return }
    if reduceMotion {
        revealed.wrappedValue = true
    } else {
        withAnimation(.spring(response: 1.1, dampingFraction: 0.82).delay(0.15)) {
            revealed.wrappedValue = true
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

/// Stands in for the dashboard during the first read, in the same shapes, so
/// the page settles into place instead of jumping from a spinner.
private struct HealthLoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            block(height: 34, width: 190)
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppTheme.primarySurface)
                .frame(height: 230)
                .overlay(alignment: .leading) {
                    HStack(spacing: AppTheme.Spacing.xl) {
                        Circle()
                            .stroke(AppTheme.secondarySurface, lineWidth: 8)
                            .frame(width: 112, height: 112)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            block(height: 18, width: 150)
                            block(height: 12, width: 190)
                            block(height: 12, width: 120)
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                }
            HStack(spacing: AppTheme.Spacing.sm) {
                card
                card
            }
            card
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading Apple Health…")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
        }
        .opacity(pulsing ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading Apple Health")
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            .fill(AppTheme.primarySurface)
            .frame(height: 150)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    block(height: 28, width: 28)
                    block(height: 12, width: 80)
                    block(height: 20, width: 60)
                }
                .padding(AppTheme.Spacing.md)
            }
    }

    private func block(height: CGFloat, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(AppTheme.secondarySurface)
            .frame(width: width, height: height)
    }
}

private struct HealthSourcesView: View {
    /// Nil until a summary has loaded.
    let summary: HealthSummary?
    let isConnected: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @AppStorage("orbit.ai.healthContextEnabled") private var shareHealthWithAssistant = false

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    if isConnected {
                        Label("Connected to Apple Health", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                    } else {
                        Label("Not connected", systemImage: "heart.slash")
                            .foregroundStyle(AppTheme.secondaryText)
                        Button {
                            dismiss()
                            Task { await app.connectHealth() }
                        } label: {
                            Label("Connect Apple Health", systemImage: "heart.fill")
                        }
                    }
                    if let summary {
                        LabeledContent("Latest refresh", value: summary.updatedAt.relativeShort)
                        LabeledContent("Signals with data", value: "\(summary.availableSignalCount)")
                        LabeledContent("Nightly sleep records", value: "\(summary.sleepHistory.count)")
                    } else if isConnected {
                        Text("No summary has loaded yet.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
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

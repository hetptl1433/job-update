import Foundation

/// Builds the same privacy-filtered Orbit snapshot for typed chat, iPhone live
/// voice, and the paired Watch. Finance details are included only after the
/// user explicitly enables assistant sharing.
@MainActor
struct AssistantContextBuilder {
    let app: AppState
    let inbox: EmailRepository
    let jobs: [JobApplication]
    let shareFinance: Bool

    init(
        app: AppState,
        inbox: EmailRepository,
        jobs: [JobApplication],
        shareFinance: Bool
    ) {
        self.app = app
        self.inbox = inbox
        self.jobs = jobs
        self.shareFinance = shareFinance
    }

    /// A full session snapshot. The probe opts into each finance detail branch,
    /// but the builder still omits all Finance data unless sharing is enabled.
    func liveContext() -> AssistantContext {
        context(for: "finance money account balance transaction income paycheck salary")
    }

    func context(for prompt: String) -> AssistantContext {
        var lines: [String] = []
        lines.append("Connections: Gmail \(app.connections.gmailConnected ? "connected" : "not connected"), Outlook \(app.connections.outlookConnected ? "connected" : "not connected"), Calendar \(app.calendar.connectedProviders.map(\.label).sorted().joined(separator: ", ")), Health \(app.connections.healthConnected ? "connected" : "not connected").")

        if shareFinance, case let .loaded(finance) = app.finance.state {
            let code = finance.currencyCode
            lines.append("User-approved Finance summary (currency \(code)):")
            lines.append("- cash=\(finance.totalCash); credit-card balance=\(finance.totalCreditBalance); investments=\(finance.totalInvestments); current-month inflow=\(finance.monthlyInflow); outflow=\(finance.monthlyOutflow); net=\(finance.monthlyNetFlow)")

            let lowerPrompt = prompt.lowercased()
            let asksAboutFinance = [
                "money", "finance", "account", "balance", "cash", "card", "credit",
                "spend", "spent", "transaction", "bill", "subscription", "income",
                "earn", "paid", "paycheck", "salary", "wage", "inflow", "outflow"
            ].contains { lowerPrompt.contains($0) }
            let asksAboutIncome = [
                "income", "earn", "paid", "paycheck", "salary", "wage", "employer",
                "annual", "year to date", "ytd"
            ].contains { lowerPrompt.contains($0) }

            if asksAboutFinance {
                for account in finance.accounts.prefix(20) {
                    lines.append("- account: \(account.maskedName); institution=\(account.institutionName); type=\(account.kind.label); balance=\(account.currentBalance) \(account.currencyCode)")
                }
            }

            if asksAboutFinance, !asksAboutIncome, !finance.recentTransactions.isEmpty {
                lines.append("Recent normalized transactions:")
                for transaction in finance.recentTransactions.prefix(15) {
                    lines.append("- \(transaction.date); \(transaction.displayName); \(transaction.direction.rawValue)=\(transaction.amount) \(transaction.currencyCode); category=\(transaction.category ?? "unknown")")
                }
            }

            if asksAboutIncome, case let .loaded(income) = app.finance.incomeState {
                lines.append("DETERMINISTIC INCOME TOOL RESULT (do not recompute or relabel inflow as income):")
                for summary in income.summaries {
                    lines.append("- currency=\(summary.currencyCode); confirmed posted this month=\(summary.thisMonth.confirmed); pending income=\(summary.thisMonth.pending); needs review excluded=\(summary.thisMonth.needsReview); confirmed last month=\(summary.lastMonth.confirmed); change amount=\(summary.changeAmount.map { String(describing: $0) } ?? "undefined"); change percent=\(summary.changePercent.map { String(describing: $0) } ?? "undefined"); confirmed YTD=\(summary.yearToDate); average monthly=\(summary.averageMonthly); estimated annual=\(summary.estimatedAnnual.map { String(describing: $0) } ?? "unavailable")")
                    for source in summary.sources.prefix(20) {
                        lines.append("- income source: \(source.name); type=\(source.type.rawValue); frequency=\(source.frequency.rawValue); this month=\(source.thisMonth); YTD=\(source.yearToDate); average deposit=\(source.averagePayment); next expected=\(source.nextExpectedPaymentDate ?? "unavailable"); user confirmed=\(source.userConfirmed)")
                    }
                    if !summary.history.isEmpty {
                        lines.append("- confirmed income history: " + summary.history.map { "\($0.month)=\($0.confirmed)" }.joined(separator: "; "))
                    }
                    for transaction in summary.confirmedTransactions.prefix(10) {
                        lines.append("- confirmed observed net deposit: \(transaction.date); \(transaction.sourceName ?? transaction.merchantName ?? transaction.name); amount=\(transaction.amount) \(transaction.currencyCode); pending=\(transaction.pending)")
                    }
                    for paycheck in summary.expectedPaychecks.prefix(8) {
                        lines.append("- expected (not guaranteed): \(paycheck.sourceName); date=\(paycheck.date); estimated amount=\(paycheck.estimatedAmount) \(summary.currencyCode)")
                    }
                }
            }
        }

        if !app.tasks.prioritizedOpen.isEmpty {
            lines.append("Open To Do items (dated items are linked to Apple Calendar when enabled):")
            for task in app.tasks.prioritizedOpen.prefix(25) {
                let due = task.dueDate.map { "; due \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
                lines.append("- id=\(task.id.uuidString); \(task.title); priority=\(task.priority.rawValue); source=\(task.source.rawValue)\(due)")
            }
        }

        if !app.tasks.suggestions.isEmpty {
            lines.append("Unreviewed To Do suggestions extracted from email:")
            for task in app.tasks.suggestions.prefix(15) {
                lines.append("- \(task.title)")
            }
        }

        let recentCompleted = app.tasks.completed.prefix(10)
        if !recentCompleted.isEmpty {
            lines.append("Recently completed To Dos:")
            for task in recentCompleted {
                lines.append("- \(task.title); completed or updated \(task.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }

        if !app.detectedJobUpdates.isEmpty {
            lines.append("Unreviewed job updates detected from connected email:")
            for update in app.detectedJobUpdates.prefix(15) {
                let role = update.role.isEmpty ? "" : " — \(update.role)"
                let next = update.nextAction.isEmpty ? "" : "; next: \(update.nextAction)"
                lines.append("- \(update.company)\(role) [\(update.status.rawValue)]\(next); evidence: \(update.reason)")
            }
        }

        if !jobs.isEmpty {
            lines.append("Job applications (\(jobs.count) total):")
            for job in jobs.prefix(25) {
                let role = job.position.isEmpty ? "?" : job.position
                let next = job.nextAction.isEmpty ? "" : "; next: \(job.nextAction)"
                lines.append("- \(job.company) — \(role) [\(job.status.rawValue)]\(next)")
            }
        }

        if case let .loaded(messages) = inbox.state, !messages.isEmpty {
            lines.append("Recent important emails:")
            for message in messages.prefix(10) {
                lines.append("- [\(message.provider.label); \(message.mailboxEmail)] \(message.sender): \(message.subject) — \(message.aiSummary)\(message.actionRequired ? " [action required]" : "")")
            }
        }

        let events = app.calendar.events
        if !events.isEmpty {
            lines.append("Upcoming unified calendar events:")
            for event in events.prefix(20) {
                lines.append("- [\(event.provider.label)] \(event.start.formatted(date: .abbreviated, time: .shortened)): \(event.title)")
            }
        }

        if case let .loaded(summary) = app.health.state {
            lines.append("Current Apple Health summary:")
            lines.append(summary.metrics.map { "\($0.title): \($0.value)" }.joined(separator: "; "))
        }

        let enabledAutomations = app.automations.automations.filter(\.enabled)
        if !enabledAutomations.isEmpty {
            lines.append("Enabled Orbit automations:")
            for automation in enabledAutomations {
                lines.append("- \(automation.title); \(automation.frequency)")
            }
        }

        return AssistantContext(
            userName: app.user?.firstName ?? "the user",
            lines: lines
        )
    }
}

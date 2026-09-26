import Foundation
import XCTest
@testable import JobRadar

final class LocalAssistantPromptTests: XCTestCase {
    func testFitKeepsEveryLineWhenEverythingFits() {
        let lines = [
            "Connections: Gmail connected.",
            "Open To Do items:",
            "- Call Dana",
            "- Send portfolio"
        ]

        XCTAssertEqual(LocalAssistantPrompt.fit(lines, to: 1_000, question: "What's next?"), lines)
    }

    func testFitRepresentsEveryListAndCountsWhatWasLeftOut() {
        let lines = ["Connections: Gmail connected."]
            + ["Open To Do items:"] + (1...30).map { "- task \($0) with a fairly long description to use space" }
            + ["Recent important emails:"] + (1...30).map { "- email \($0) about something relevant here" }
            + ["Upcoming unified calendar events:"] + (1...30).map { "- event \($0) at some time" }

        let fitted = LocalAssistantPrompt.fit(lines, to: 900, question: "Summarize")

        XCTAssertLessThanOrEqual(fitted.reduce(0) { $0 + $1.count + 1 }, 900)
        for header in [
            "Connections: Gmail connected.",
            "Open To Do items:",
            "Recent important emails:",
            "Upcoming unified calendar events:"
        ] {
            XCTAssertTrue(fitted.contains(header), header)
        }
        let markers = fitted.filter { $0.hasPrefix("- (+") && $0.hasSuffix(" more not shown)") }
        XCTAssertEqual(markers.count, 3)
    }

    func testFitGivesMoreRoomToListsTheQuestionIsAbout() {
        let lines = ["Open To Do items:"] + (1...20).map { "- task \($0)" }
            + ["Recent important emails:"] + (1...20).map { "- email \($0)" }

        let fitted = LocalAssistantPrompt.fit(
            lines,
            to: 300,
            question: "Did anything important arrive in my inbox?"
        )

        let emails = fitted.filter { $0.hasPrefix("- email") }.count
        let tasks = fitted.filter { $0.hasPrefix("- task") }.count
        XCTAssertGreaterThan(emails, tasks)
        XCTAssertGreaterThan(tasks, 0)
    }

    func testFitReturnsNothingWithoutABudget() {
        XCTAssertEqual(LocalAssistantPrompt.fit(["Open To Do items:", "- Call Dana"], to: 0, question: ""), [])
    }

    func testCompactDropsTaskIdentifiersAndCapsLongLines() {
        XCTAssertEqual(
            LocalAssistantPrompt.compact("- id=AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE; Call Dana; priority=high"),
            "- Call Dana; priority=high"
        )

        let compacted = LocalAssistantPrompt.compact("- " + String(repeating: "x", count: 500))
        XCTAssertEqual(compacted.count, LocalAssistantPrompt.maxDataLineCharacters)
        XCTAssertTrue(compacted.hasSuffix("…"))
    }

    func testRecentTurnsStartWithTheUserAndStayWithinLimits() {
        var history = [ChatMessage(role: .assistant, text: "Welcome back")]
        for index in 1...10 {
            history.append(ChatMessage(role: .user, text: "Question \(index)"))
            history.append(ChatMessage(role: .assistant, text: "Answer \(index)"))
        }

        let turns = LocalAssistantPrompt.recentTurns(from: history)

        XCTAssertLessThanOrEqual(turns.count, LocalAssistantPrompt.maxHistoryMessages)
        XCTAssertEqual(turns.first?.role, .user)
        XCTAssertEqual(turns.last, LocalAssistantPrompt.Turn(role: .assistant, text: "Answer 10"))
    }

    func testVisibleReplyNeverShowsReasoning() {
        XCTAssertEqual(
            LocalAssistantPrompt.visibleReply(from: "<think>\nplan\n</think>\n\nYou have two interviews."),
            "You have two interviews."
        )
        XCTAssertEqual(LocalAssistantPrompt.visibleReply(from: "<think>still reasoning"), "")
        XCTAssertEqual(LocalAssistantPrompt.visibleReply(from: "  Hello  "), "Hello")
    }

    func testSnapshotSplitsThinkingFromTheAnswer() {
        let thinking = LocalAssistantPrompt.snapshot(from: "<think>\nCheck the calendar", thinking: true)
        XCTAssertTrue(thinking.isThinking)
        XCTAssertEqual(thinking.reasoning, "Check the calendar")
        XCTAssertEqual(thinking.text, "")

        let answered = LocalAssistantPrompt.snapshot(
            from: "<think>\nCheck the calendar\n</think>\n\nYou have two interviews.",
            thinking: true
        )
        XCTAssertFalse(answered.isThinking)
        XCTAssertEqual(answered.reasoning, "Check the calendar")
        XCTAssertEqual(answered.text, "You have two interviews.")
    }

    func testSnapshotBeforeThinkingAndWithoutIt() {
        // Nothing yet, or only the start of the tag: still thinking.
        XCTAssertTrue(LocalAssistantPrompt.snapshot(from: "", thinking: true).isThinking)
        XCTAssertTrue(LocalAssistantPrompt.snapshot(from: "<th", thinking: true).isThinking)

        // A model that skips thinking goes straight to its answer.
        let direct = LocalAssistantPrompt.snapshot(from: "You're free today.", thinking: true)
        XCTAssertFalse(direct.isThinking)
        XCTAssertNil(direct.reasoning)
        XCTAssertEqual(direct.text, "You're free today.")

        // An empty thinking block leaves nothing to show.
        let empty = LocalAssistantPrompt.snapshot(from: "<think>\n\n</think>\n\nHi", thinking: true)
        XCTAssertNil(empty.reasoning)
        XCTAssertEqual(empty.text, "Hi")

        // A template that opens the block itself leaves only the closing tag.
        let prefilled = LocalAssistantPrompt.snapshot(from: "plan\n</think>\n\nHi", thinking: true)
        XCTAssertEqual(prefilled.reasoning, "plan")
        XCTAssertEqual(prefilled.text, "Hi")

        // With thinking off, a stray reasoning block is dropped.
        let off = LocalAssistantPrompt.snapshot(from: "<think>plan</think>Hi", thinking: false)
        XCTAssertNil(off.reasoning)
        XCTAssertEqual(off.text, "Hi")
    }

    func testSnapshotAfterOrbitEndsThinkingEarly() {
        let raw = "<think>\nA long plan" + LocalAssistantPrompt.thinkingEnd + "Here's the answer."

        let snapshot = LocalAssistantPrompt.snapshot(from: raw, thinking: true)

        XCTAssertFalse(snapshot.isThinking)
        XCTAssertEqual(snapshot.reasoning, "A long plan")
        XCTAssertEqual(snapshot.text, "Here's the answer.")
    }

    func testRequestCarriesOwnerMemoryDataAndQuestion() {
        let context = AssistantContext(
            userName: "Het",
            lines: ["Open To Do items:", "- Call Dana"],
            memoryLines: ["- [communication] Prefers concise answers"]
        )

        let request = LocalAssistantPrompt.request(
            question: "What should I do first?",
            context: context,
            history: [],
            dataCharacterBudget: 2_000
        )

        XCTAssertEqual(request.instructions, LocalAssistantPrompt.instructions)
        XCTAssertTrue(request.message.contains("Owner: Het"))
        XCTAssertTrue(request.message.contains("Prefers concise answers"))
        XCTAssertTrue(request.message.contains("- Call Dana"))
        XCTAssertTrue(request.message.hasSuffix("What should I do first?"))
        XCTAssertTrue(request.history.isEmpty)
    }

    func testRequestSaysWhenOrbitDataWasLeftOut() {
        let context = AssistantContext(userName: "Het", lines: ["Open To Do items:", "- Call Dana"])

        let request = LocalAssistantPrompt.request(
            question: "Hi",
            context: context,
            history: [],
            dataCharacterBudget: 0
        )

        XCTAssertTrue(request.message.contains("left out"))
        XCTAssertFalse(request.message.contains("- Call Dana"))
    }
}

final class LocalModelCatalogTests: XCTestCase {
    private let suiteName = "LocalModelCatalogTests"
    /// An iPhone 15 (A16), the device the catalog's speeds are estimated for.
    private let a16 = DevicePerformance.reference
    private let a17Pro = DevicePerformance.estimate(gpuGeneration: 9, isDesktopClass: false)
    private let m4 = DevicePerformance.estimate(gpuGeneration: 9, isDesktopClass: true)

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCatalogPinsExactCommits() {
        for option in LocalModelOption.catalog {
            XCTAssertEqual(option.revision.count, 40, option.id)
            XCTAssertTrue(option.revision.allSatisfy(\.isHexDigit), option.id)
            XCTAssertEqual(option.repository.split(separator: "/").count, 2, option.id)
        }
        XCTAssertEqual(Set(LocalModelOption.catalog.map(\.id)).count, LocalModelOption.catalog.count)
    }

    func testSelectionFallsBackToAModelTheDeviceCanRun() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        func selected(_ physicalMemory: UInt64) -> String? {
            LocalModelOption.selected(
                defaults: defaults,
                physicalMemory: physicalMemory,
                appMemoryLimit: nil,
                performance: a16,
                measured: [:],
                isDownloaded: { _ in false }
            )?.id
        }

        XCTAssertEqual(selected(6_000_000_000), LocalModelOption.qwen3_1_7B.id)
        XCTAssertEqual(selected(4_000_000_000), LocalModelOption.qwen3_0_6B.id)
        XCTAssertNil(selected(2_000_000_000))

        defaults.set(LocalModelOption.qwen3_0_6B.id, forKey: AppConfig.localModelPreferenceKey)
        XCTAssertEqual(selected(6_000_000_000), LocalModelOption.qwen3_0_6B.id)

        // A saved choice this device can't run falls back instead of failing.
        defaults.set(LocalModelOption.qwen3_1_7B.id, forKey: AppConfig.localModelPreferenceKey)
        XCTAssertEqual(selected(4_000_000_000), LocalModelOption.qwen3_0_6B.id)
    }

    func testWithoutASavedChoiceADownloadedModelIsKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        func selected(downloaded: Set<String>) -> String? {
            LocalModelOption.selected(
                defaults: defaults,
                physicalMemory: 6_000_000_000,
                appMemoryLimit: 3_000_000_000,
                performance: a16,
                measured: [:],
                isDownloaded: { downloaded.contains($0.id) }
            )?.id
        }

        // The recommendation would need a download, but 0.6B is already here.
        XCTAssertEqual(selected(downloaded: [LocalModelOption.qwen3_0_6B.id]), LocalModelOption.qwen3_0_6B.id)
        // Once the recommendation is downloaded too, it wins.
        XCTAssertEqual(
            selected(downloaded: [LocalModelOption.qwen3_0_6B.id, LocalModelOption.qwen3_1_7B.id]),
            LocalModelOption.qwen3_1_7B.id
        )
        XCTAssertEqual(selected(downloaded: []), LocalModelOption.qwen3_1_7B.id)
    }

    func testLargerModelsFollowThePerAppMemoryLimit() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        func recommended(_ physicalMemory: UInt64, limit: UInt64) -> String? {
            LocalModelOption.recommended(
                physicalMemory: physicalMemory,
                appMemoryLimit: limit,
                performance: m4,
                measured: [:]
            )?.id
        }
        func selected(_ physicalMemory: UInt64, limit: UInt64) -> String? {
            LocalModelOption.selected(
                defaults: defaults,
                physicalMemory: physicalMemory,
                appMemoryLimit: limit,
                performance: m4,
                measured: [:],
                isDownloaded: { _ in false }
            )?.id
        }

        // At the default limit of about 3 GB, a 6 GB iPhone can't hold 4B.
        XCTAssertEqual(
            LocalModelOption.available(physicalMemory: 6_000_000_000, appMemoryLimit: 3_000_000_000).map(\.id),
            [LocalModelOption.qwen3_1_7B.id, LocalModelOption.qwen3_0_6B.id]
        )

        // The raised limit of about 4 GB offers 4B there, but 1.7B stays
        // recommended.
        XCTAssertEqual(
            LocalModelOption.available(physicalMemory: 6_000_000_000, appMemoryLimit: 4_000_000_000).map(\.id),
            [LocalModelOption.qwen3_4B.id, LocalModelOption.qwen3_1_7B.id, LocalModelOption.qwen3_0_6B.id]
        )
        XCTAssertEqual(recommended(6_000_000_000, limit: 4_000_000_000), LocalModelOption.qwen3_1_7B.id)

        // An 8 GB iPad at the default limit runs Qwen3 4B but not 8B.
        XCTAssertEqual(
            LocalModelOption.available(physicalMemory: 8_000_000_000, appMemoryLimit: 5_000_000_000).map(\.id),
            [LocalModelOption.qwen3_4B.id, LocalModelOption.qwen3_1_7B.id, LocalModelOption.qwen3_0_6B.id]
        )
        XCTAssertEqual(selected(8_000_000_000, limit: 5_000_000_000), LocalModelOption.qwen3_4B.id)

        // A raised limit adds 8B, but 4B stays recommended on 8 GB.
        XCTAssertEqual(
            LocalModelOption.available(physicalMemory: 8_000_000_000, appMemoryLimit: 6_500_000_000).first?.id,
            LocalModelOption.qwen3_8B.id
        )
        XCTAssertEqual(recommended(8_000_000_000, limit: 6_500_000_000), LocalModelOption.qwen3_4B.id)
        XCTAssertEqual(recommended(16_000_000_000, limit: 12_000_000_000), LocalModelOption.qwen3_8B.id)

        // A saved 8B choice that no longer fits falls back to the recommendation.
        defaults.set(LocalModelOption.qwen3_8B.id, forKey: AppConfig.localModelPreferenceKey)
        XCTAssertEqual(selected(8_000_000_000, limit: 5_000_000_000), LocalModelOption.qwen3_4B.id)
    }

    func testRecommendationFollowsTheChip() {
        func recommended(_ performance: DevicePerformance) -> String? {
            LocalModelOption.recommended(
                physicalMemory: 8_000_000_000,
                appMemoryLimit: 5_000_000_000,
                performance: performance,
                measured: [:]
            )?.id
        }

        // With the same memory, an A17 Pro answers with Qwen3 4B in time but
        // an A16-class chip would take too long, so it gets 1.7B.
        XCTAssertEqual(recommended(a17Pro), LocalModelOption.qwen3_4B.id)
        XCTAssertEqual(recommended(a16), LocalModelOption.qwen3_1_7B.id)
    }

    func testMeasuredSpeedReplacesTheEstimate() {
        let slow = [
            LocalModelOption.qwen3_4B.id: LocalModelSpeed(
                promptTokensPerSecond: 90,
                replyTokensPerSecond: 6,
                isMeasured: true
            )
        ]

        // Orbit measured 4B running slowly here, so it's no longer recommended.
        XCTAssertEqual(
            LocalModelOption.recommended(
                physicalMemory: 8_000_000_000,
                appMemoryLimit: 5_000_000_000,
                performance: m4,
                measured: slow
            )?.id,
            LocalModelOption.qwen3_1_7B.id
        )
        XCTAssertTrue(LocalModelOption.qwen3_4B.speed(on: m4, measured: slow).isMeasured)
        XCTAssertFalse(LocalModelOption.qwen3_4B.speed(on: m4, measured: [:]).isMeasured)
    }

    func testSpeedStoreBlendsMeasurements() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        LocalModelSpeedStore.record(
            LocalModelSpeed(promptTokensPerSecond: 400, replyTokensPerSecond: 30),
            for: "model",
            defaults: defaults
        )
        let speeds = LocalModelSpeedStore.record(
            LocalModelSpeed(promptTokensPerSecond: 200, replyTokensPerSecond: 20),
            for: "model",
            defaults: defaults
        )

        let speed = try XCTUnwrap(speeds["model"])
        XCTAssertEqual(speed.promptTokensPerSecond, 320, accuracy: 0.001)
        XCTAssertEqual(speed.replyTokensPerSecond, 26, accuracy: 0.001)
        XCTAssertTrue(speed.isMeasured)
        XCTAssertEqual(LocalModelSpeedStore.load(defaults: defaults), speeds)
    }

    func testDevicePerformanceByChip() {
        XCTAssertEqual(DevicePerformance.estimate(gpuGeneration: 8, isDesktopClass: false), .reference)
        XCTAssertNil(DevicePerformance.estimate(gpuGeneration: nil, isDesktopClass: false).chipClass)
        XCTAssertEqual(m4.chipClass, "M3/M4")
        XCTAssertGreaterThan(m4.replySpeed, a17Pro.replySpeed)
        // A newer generation than Orbit knows counts as the newest it knows.
        XCTAssertEqual(DevicePerformance.estimate(gpuGeneration: 11, isDesktopClass: false).chipClass, "A19")
    }

    func testThinkingSupportAndLimits() {
        XCTAssertFalse(LocalModelOption.qwen3_4B.supportsThinking)
        XCTAssertTrue(LocalModelOption.qwen3_1_7B.supportsThinking)

        // On a fast device the token limit ends thinking first; on a slow
        // one, the time limit does.
        let fast = LocalModelSpeed(promptTokensPerSecond: 1_000, replyTokensPerSecond: 100)
        XCTAssertEqual(
            LocalModelOption.qwen3_1_7B.maxThinkingSeconds(speed: fast),
            Double(LocalModelOption.thinkingTokenLimit) / 100,
            accuracy: 0.001
        )
        let slow = LocalModelSpeed(promptTokensPerSecond: 100, replyTokensPerSecond: 10)
        XCTAssertEqual(
            LocalModelOption.qwen3_1_7B.maxThinkingSeconds(speed: slow),
            LocalModelOption.thinkingTimeLimit
        )
    }
}

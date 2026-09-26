import Foundation
import XCTest
@testable import JobRadar

final class ChatModelSelectionTests: XCTestCase {
    private let suiteName = "ChatModelSelectionTests"

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testReasoningEffortsByModel() {
        let every = OpenAIClient.ReasoningEffort.allCases
        XCTAssertEqual(OpenAIClient.reasoningEfforts(forModel: "gpt-6-luna"), every)
        XCTAssertEqual(OpenAIClient.reasoningEfforts(forModel: "gpt-5.6-terra"), every)
        XCTAssertFalse(OpenAIClient.reasoningEfforts(forModel: "gpt-6-astra").contains(.off))
        XCTAssertEqual(OpenAIClient.reasoningEfforts(forModel: "gpt-4o-mini"), [])
        // A similar-looking name isn't a reasoning model.
        XCTAssertEqual(OpenAIClient.reasoningEfforts(forModel: "gpt-5.60"), [])
    }

    func testThinkingModesUseTheClosestEffortAModelAccepts() {
        XCTAssertEqual(OpenAIClient.effort(ChatThinkingMode.instant.reasoningEffort, forModel: "gpt-6-luna"), .off)
        XCTAssertEqual(OpenAIClient.effort(ChatThinkingMode.instant.reasoningEffort, forModel: "gpt-6-astra"), .low)
        XCTAssertEqual(OpenAIClient.effort(ChatThinkingMode.balanced.reasoningEffort, forModel: "gpt-5.6-luna"), .medium)
        XCTAssertEqual(OpenAIClient.effort(ChatThinkingMode.deep.reasoningEffort, forModel: "gpt-6-sol"), .xhigh)
        XCTAssertNil(OpenAIClient.effort(.medium, forModel: "gpt-4o-mini"))
    }

    func testRequestPayloadSendsTheAcceptedEffort() {
        func effort(model: String, requested: OpenAIClient.ReasoningEffort) -> String? {
            let payload = OpenAIClient(apiKey: "test", model: model)
                .requestPayload(system: "System", user: "User", reasoningEffort: requested)
            return (payload["reasoning"] as? [String: Any])?["effort"] as? String
        }

        XCTAssertEqual(effort(model: "gpt-6-luna", requested: .off), "none")
        XCTAssertEqual(effort(model: "gpt-6-astra", requested: .off), "low")
        XCTAssertNil(effort(model: "gpt-4o-mini", requested: .xhigh))
    }

    func testLongerThinkingGetsMoreRoomToAnswer() {
        XCTAssertEqual(ChatThinkingMode.deep.maxOutputTokens(reasons: false), 4_000)
        XCTAssertGreaterThan(
            ChatThinkingMode.deep.maxOutputTokens(reasons: true),
            ChatThinkingMode.balanced.maxOutputTokens(reasons: true)
        )
        XCTAssertGreaterThan(ChatThinkingMode.deep.requestTimeout, ChatThinkingMode.instant.requestTimeout)
    }

    func testChatModelFollowsTheEmailModelUntilChosen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("gpt-5.6-sol", forKey: AppConfig.openAIModelPreferenceKey)

        XCTAssertEqual(AppConfig.selectedOpenAIChatModel(defaults: defaults), "gpt-5.6-sol")

        defaults.set("gpt-6-luna", forKey: AppConfig.openAIChatModelPreferenceKey)
        XCTAssertEqual(AppConfig.selectedOpenAIChatModel(defaults: defaults), "gpt-6-luna")
        XCTAssertEqual(AppConfig.selectedOpenAIModel(defaults: defaults), "gpt-5.6-sol")
    }

    func testChatModelChoicesNameUnlistedModels() {
        XCTAssertEqual(AppConfig.chatModelChoice(for: "gpt-6-luna").name, "GPT-6 Luna")
        XCTAssertTrue(AppConfig.chatModelChoice(for: "gpt-6-luna").isRecommended)
        XCTAssertEqual(AppConfig.chatModelChoices(including: "ft:custom").first?.id, "ft:custom")
    }

    func testThinkingPreferencesDefaultAndStayValid() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(ChatPreferences.openAIThinking(defaults: defaults), .balanced)
        XCTAssertEqual(ChatPreferences.onDeviceThinking(defaults: defaults), .instant)

        // On-device models only answer right away or think first.
        defaults.set(ChatThinkingMode.deep.rawValue, forKey: ChatPreferences.onDeviceThinkingKey)
        XCTAssertEqual(ChatPreferences.onDeviceThinking(defaults: defaults), .instant)

        defaults.set(ChatThinkingMode.thinking.rawValue, forKey: ChatPreferences.onDeviceThinkingKey)
        XCTAssertEqual(ChatPreferences.onDeviceThinking(for: LocalModelOption.qwen3_1_7B, defaults: defaults), .thinking)
        XCTAssertNil(ChatPreferences.onDeviceThinking(for: LocalModelOption.qwen3_4B, defaults: defaults))
        XCTAssertNil(ChatPreferences.openAIThinking(for: "gpt-4o-mini", defaults: defaults))
    }

    func testSavedConversationsWithoutReplyDetailsStillLoad() throws {
        // As saved before replies recorded their model and thinking.
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","role":"assistant","text":"Hi","createdAt":"2026-09-01T12:00:00Z"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let messages = try decoder.decode([ChatMessage].self, from: Data(json.utf8))

        XCTAssertEqual(messages.first?.text, "Hi")
        XCTAssertNil(messages.first?.reasoning)
        XCTAssertNil(messages.first?.thinkingSeconds)
        XCTAssertNil(messages.first?.detail)
    }
}

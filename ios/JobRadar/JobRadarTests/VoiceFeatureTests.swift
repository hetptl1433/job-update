import Foundation
import XCTest
@testable import JobRadar

final class WatchVoiceProtocolTests: XCTestCase {
    func testRequestRoundTripsThroughPropertyListMessage() throws {
        let request = WatchVoiceRequest(
            requestID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )

        let message = WatchVoiceProtocol.requestMessage(request)

        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(WatchVoiceProtocol.request(from: message), request)
        XCTAssertNil(WatchVoiceProtocol.bootstrap(from: message))
        XCTAssertNil(WatchVoiceProtocol.failure(from: message))
        XCTAssertNoThrow(try PropertyListSerialization.data(
            fromPropertyList: message,
            format: .binary,
            options: 0
        ))
    }

    func testBootstrapRoundTripsWithoutLosingCredentialMetadata() {
        let bootstrap = WatchVoiceBootstrap(
            clientSecretValue: "ek_test_short_lived",
            expiresAt: Date(timeIntervalSince1970: 1_786_439_400),
            model: "gpt-realtime-test",
            requestID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )

        let decoded = WatchVoiceProtocol.bootstrap(
            from: WatchVoiceProtocol.bootstrapMessage(bootstrap)
        )

        XCTAssertEqual(decoded, bootstrap)
    }

    func testFailureRoundTripsWithTypedCodeAndLocalizedMessage() {
        let failure = WatchVoiceFailure(
            requestID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            code: .phoneNotReady,
            message: "Connect OpenAI on your iPhone."
        )

        let decoded = WatchVoiceProtocol.failure(
            from: WatchVoiceProtocol.failureMessage(failure)
        )

        XCTAssertEqual(decoded, failure)
        XCTAssertEqual(decoded?.errorDescription, failure.message)
    }

    func testUnsupportedVersionsAreRejectedForEveryMessageType() {
        var request = WatchVoiceRequest()
        request.version = WatchVoiceRequest.currentVersion + 1

        var bootstrap = WatchVoiceBootstrap(
            clientSecretValue: "ek_test",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            model: "gpt-realtime-test",
            requestID: request.requestID
        )
        bootstrap.version = WatchVoiceBootstrap.currentVersion + 1

        var failure = WatchVoiceFailure(
            requestID: request.requestID,
            code: .bootstrapFailed,
            message: "Unsupported"
        )
        failure.version = WatchVoiceFailure.currentVersion + 1

        XCTAssertNil(WatchVoiceProtocol.request(
            from: WatchVoiceProtocol.requestMessage(request)
        ))
        XCTAssertNil(WatchVoiceProtocol.bootstrap(
            from: WatchVoiceProtocol.bootstrapMessage(bootstrap)
        ))
        XCTAssertNil(WatchVoiceProtocol.failure(
            from: WatchVoiceProtocol.failureMessage(failure)
        ))
    }

    func testBootstrapUsabilityRequiresValidityBeyondSafetyWindow() {
        let now = Date(timeIntervalSince1970: 1_786_435_200)
        let requestID = UUID()

        let comfortablyValid = WatchVoiceBootstrap(
            clientSecretValue: "ek_test",
            expiresAt: now.addingTimeInterval(16),
            model: "gpt-realtime-test",
            requestID: requestID
        )
        let exactlyAtBoundary = WatchVoiceBootstrap(
            clientSecretValue: "ek_test",
            expiresAt: now.addingTimeInterval(15),
            model: "gpt-realtime-test",
            requestID: requestID
        )
        let expired = WatchVoiceBootstrap(
            clientSecretValue: "ek_test",
            expiresAt: now.addingTimeInterval(-1),
            model: "gpt-realtime-test",
            requestID: requestID
        )

        XCTAssertTrue(comfortablyValid.isUsable(at: now, minimumValidity: 15))
        XCTAssertFalse(exactlyAtBoundary.isUsable(at: now, minimumValidity: 15))
        XCTAssertFalse(expired.isUsable(at: now, minimumValidity: 0))
        XCTAssertTrue(exactlyAtBoundary.isUsable(at: now, minimumValidity: 14))
    }

    func testBootstrapUsabilityRejectsMissingCredentialOrModel() {
        let now = Date(timeIntervalSince1970: 1_786_435_200)
        let expiry = now.addingTimeInterval(600)

        XCTAssertFalse(WatchVoiceBootstrap(
            clientSecretValue: "",
            expiresAt: expiry,
            model: "gpt-realtime-test",
            requestID: UUID()
        ).isUsable(at: now))
        XCTAssertFalse(WatchVoiceBootstrap(
            clientSecretValue: "ek_test",
            expiresAt: expiry,
            model: "",
            requestID: UUID()
        ).isUsable(at: now))
    }
}

final class RealtimeSessionConfigurationPayloadTests: XCTestCase {
    func testMintingPayloadContainsFullDuplexPCMAndServerVADConfiguration() throws {
        let payload = RealtimeSessionConfigurationPayload.make(
            model: "gpt-realtime-test",
            instructions: "Use the supplied Orbit context."
        )

        XCTAssertEqual(payload["type"] as? String, "realtime")
        XCTAssertEqual(payload["model"] as? String, "gpt-realtime-test")
        XCTAssertEqual(payload["instructions"] as? String, "Use the supplied Orbit context.")
        XCTAssertEqual(payload["output_modalities"] as? [String], ["audio"])
        XCTAssertEqual(payload["max_output_tokens"] as? Int, 1_200)

        let audio = try XCTUnwrap(payload["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let inputFormat = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(inputFormat["type"] as? String, "audio/pcm")
        XCTAssertEqual(inputFormat["rate"] as? Int, 24_000)

        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "semantic_vad")
        XCTAssertEqual(turnDetection["create_response"] as? Bool, true)
        XCTAssertEqual(turnDetection["interrupt_response"] as? Bool, true)

        let output = try XCTUnwrap(audio["output"] as? [String: Any])
        let outputFormat = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(outputFormat["type"] as? String, "audio/pcm")
        XCTAssertEqual(outputFormat["rate"] as? Int, 24_000)
        XCTAssertEqual(output["voice"] as? String, "marin")
    }

    func testSessionUpdatePayloadOmitsAnAbsentOrEmptyModel() {
        let nilModel = RealtimeSessionConfigurationPayload.make(
            model: nil,
            instructions: "Instructions"
        )
        let emptyModel = RealtimeSessionConfigurationPayload.make(
            model: "",
            instructions: "Instructions"
        )

        XCTAssertNil(nilModel["model"])
        XCTAssertNil(emptyModel["model"])
    }
}

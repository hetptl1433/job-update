import Foundation

/// A one-shot request for a short-lived Realtime credential. The raw OpenAI
/// API key must remain on the companion iPhone (or the production backend).
struct WatchVoiceRequest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var requestID: UUID

    init(requestID: UUID = UUID()) {
        self.requestID = requestID
    }
}

/// Everything the Watch needs to open its own direct Realtime connection.
/// Session instructions and audio configuration are bound to the short-lived
/// credential before it is sent to the Watch.
struct WatchVoiceBootstrap: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var clientSecretValue: String
    var expiresAt: Date
    var model: String
    var requestID: UUID

    /// Reject credentials that may expire while the socket is being opened.
    func isUsable(at date: Date = .now, minimumValidity: TimeInterval = 15) -> Bool {
        !clientSecretValue.isEmpty
            && !model.isEmpty
            && expiresAt.timeIntervalSince(date) > minimumValidity
    }
}

struct WatchVoiceFailure: Error, Codable, Equatable, Sendable {
    enum Code: String, Codable, Equatable, Sendable {
        case phoneNotReady = "phone_not_ready"
        case phoneUnreachable = "phone_unreachable"
        case requestEncodingFailed = "request_encoding_failed"
        case requestDeliveryFailed = "request_delivery_failed"
        case credentialExpired = "credential_expired"
        case bootstrapFailed = "bootstrap_failed"
    }

    static let currentVersion = 1

    var version = currentVersion
    var requestID: UUID
    var code: Code
    var message: String

    init(requestID: UUID, code: Code, message: String) {
        self.requestID = requestID
        self.code = code
        self.message = message
    }
}

extension WatchVoiceFailure: LocalizedError {
    var errorDescription: String? { message }
}

enum WatchVoiceProtocol {
    static let requestKey = "orbit.watch.voice.request.v1"
    static let bootstrapKey = "orbit.watch.voice.bootstrap.v1"
    static let failureKey = "orbit.watch.voice.failure.v1"

    static func requestMessage(_ request: WatchVoiceRequest) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(request) else { return [:] }
        return [requestKey: data]
    }

    static func bootstrapMessage(_ bootstrap: WatchVoiceBootstrap) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(bootstrap) else { return [:] }
        return [bootstrapKey: data]
    }

    static func failureMessage(_ failure: WatchVoiceFailure) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(failure) else { return [:] }
        return [failureKey: data]
    }

    static func request(from message: [String: Any]) -> WatchVoiceRequest? {
        decode(WatchVoiceRequest.self, key: requestKey, from: message) { request in
            request.version == WatchVoiceRequest.currentVersion
        }
    }

    static func bootstrap(from message: [String: Any]) -> WatchVoiceBootstrap? {
        decode(WatchVoiceBootstrap.self, key: bootstrapKey, from: message) { bootstrap in
            bootstrap.version == WatchVoiceBootstrap.currentVersion
        }
    }

    static func failure(from message: [String: Any]) -> WatchVoiceFailure? {
        decode(WatchVoiceFailure.self, key: failureKey, from: message) { failure in
            failure.version == WatchVoiceFailure.currentVersion
        }
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        key: String,
        from message: [String: Any],
        validate: (Value) -> Bool
    ) -> Value? {
        guard let data = message[key] as? Data,
              let value = try? JSONDecoder().decode(type, from: data),
              validate(value) else {
            return nil
        }
        return value
    }
}

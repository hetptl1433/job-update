import Foundation

/// A generic, honest representation of an integration's state. Screens render
/// distinct UI for each case — never a silent blank.
enum LoadState<Value>: Equatable where Value: Equatable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case disconnected
    case failed(String)

    var value: Value? {
        if case let .loaded(v) = self { return v }
        return nil
    }
}

/// A small, owner-scoped disk cache for read models that make a cold launch
/// useful before remote services finish refreshing. Cached files contain only
/// app-facing data (never OAuth/Plaid tokens), opt out of backup, and use iOS
/// Data Protection after the device's first unlock.
final class ProtectedSnapshotStore<Value: Codable> {
    struct Snapshot {
        var value: Value
        var savedAt: Date
    }

    private struct Envelope: Codable {
        var ownerID: String
        var savedAt: Date
        var value: Value
    }

    private let fileManager: FileManager
    private let fileURL: URL

    init(filename: String, fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        let baseDirectory = directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.fileURL = baseDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    func load(ownerID: String?) -> Snapshot? {
        guard let ownerID, !ownerID.isEmpty,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.ownerID == ownerID else { return nil }
        return Snapshot(value: envelope.value, savedAt: envelope.savedAt)
    }

    func save(_ value: Value, ownerID: String?) {
        guard let ownerID, !ownerID.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Envelope(ownerID: ownerID, savedAt: .now, value: value)) else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = fileURL
            try? mutableURL.setResourceValues(values)
        } catch {
            // A cache miss is always recoverable from the source service.
        }
    }

    func remove() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.removeItem(at: fileURL)
    }
}

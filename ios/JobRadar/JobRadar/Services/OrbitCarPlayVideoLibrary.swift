import Combine
import Foundation
import UniformTypeIdentifiers

struct OrbitCarPlayVideo: Identifiable, Codable, Equatable {
    enum Source: Codable, Equatable {
        case file(name: String)
        case stream(url: URL)
    }

    let id: UUID
    let title: String
    let source: Source

    var playbackURL: URL {
        switch source {
        case .file(let name):
            Self.storageDirectory.appendingPathComponent(name, isDirectory: false)
        case .stream(let url):
            url
        }
    }

    var isImportedFile: Bool {
        if case .file = source { return true }
        return false
    }

    static let storageDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("OrbitCarPlayVideos", isDirectory: true)
}

@MainActor
final class OrbitCarPlayVideoLibrary: ObservableObject {
    static let shared = OrbitCarPlayVideoLibrary()
    static let didChangeNotification = Notification.Name("OrbitCarPlayVideoLibraryDidChange")

    @Published private(set) var videos: [OrbitCarPlayVideo] = []
    @Published private(set) var lastError: String?

    private let fileManager = FileManager.default
    private let manifestURL = OrbitCarPlayVideo.storageDirectory
        .appendingPathComponent("library.json", isDirectory: false)
    private var loadFailed = false

    private init() {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            let saved = try JSONDecoder().decode([OrbitCarPlayVideo].self, from: data)
            guard saved.allSatisfy(Self.isValidSavedVideo) else {
                throw LibraryError.damagedLibrary
            }
            videos = saved
        } catch {
            loadFailed = true
            lastError = LibraryError.damagedLibrary.localizedDescription
        }
    }

    func addFile(_ url: URL) throws {
        try checkLibrary()
        guard url.isFileURL else { throw LibraryError.unsupportedFile }

        let extensionName = url.pathExtension.lowercased()
        guard
            ["mp4", "m4v", "mov"].contains(extensionName),
            UTType(filenameExtension: extensionName)?.conforms(to: .movie) == true
        else { throw LibraryError.unsupportedFile }

        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }

        try fileManager.createDirectory(
            at: OrbitCarPlayVideo.storageDirectory,
            withIntermediateDirectories: true
        )

        var id = UUID()
        var name = "\(id.uuidString).\(extensionName)"
        var destination = OrbitCarPlayVideo.storageDirectory.appendingPathComponent(name)
        while fileManager.fileExists(atPath: destination.path) {
            id = UUID()
            name = "\(id.uuidString).\(extensionName)"
            destination = OrbitCarPlayVideo.storageDirectory.appendingPathComponent(name)
        }

        try fileManager.copyItem(at: url, to: destination)
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let video = OrbitCarPlayVideo(
            id: id,
            title: title.isEmpty ? "Imported Video" : title,
            source: .file(name: name)
        )
        do {
            try save(videos + [video])
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        videos.append(video)
        didChange()
    }

    func addStream(_ string: String) throws {
        try checkLibrary()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let parts = URLComponents(string: trimmed),
            let scheme = parts.scheme?.lowercased(),
            let host = parts.host, !host.isEmpty,
            scheme == "https" || (scheme == "http" && Self.isLocalHost(host)),
            parts.user == nil, parts.password == nil,
            let url = parts.url
        else { throw LibraryError.invalidStreamURL }

        guard !videos.contains(where: { $0.playbackURL == url }) else {
            throw LibraryError.duplicateStream
        }
        let decodedName = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? ""
        let filename = decodedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = filename.isEmpty || filename == "/" ? host : filename
        let video = OrbitCarPlayVideo(id: UUID(), title: title, source: .stream(url: url))
        try save(videos + [video])
        videos.append(video)
        didChange()
    }

    func remove(_ video: OrbitCarPlayVideo) {
        guard let existing = videos.first(where: { $0.id == video.id }) else { return }
        let updated = videos.filter { $0.id != video.id }
        do {
            try save(updated)
            videos = updated
            didChange()
            if existing.isImportedFile {
                try fileManager.removeItem(at: existing.playbackURL)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func checkLibrary() throws {
        if loadFailed { throw LibraryError.damagedLibrary }
    }

    private func save(_ updated: [OrbitCarPlayVideo]) throws {
        try fileManager.createDirectory(
            at: OrbitCarPlayVideo.storageDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: manifestURL, options: .atomic)
    }

    private func didChange() {
        lastError = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func isValidSavedVideo(_ video: OrbitCarPlayVideo) -> Bool {
        switch video.source {
        case .file(let name):
            let filename = URL(fileURLWithPath: name)
            return name == filename.lastPathComponent &&
                UUID(uuidString: filename.deletingPathExtension().lastPathComponent) == video.id &&
                ["mp4", "m4v", "mov"].contains(filename.pathExtension.lowercased())
        case .stream(let url):
            let scheme = url.scheme?.lowercased()
            return (scheme == "https" || (scheme == "http" && isLocalHost(url.host ?? ""))) &&
                url.host?.isEmpty == false && url.user == nil && url.password == nil
        }
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "localhost" || normalized.hasSuffix(".local") || !normalized.contains(".") { return true }
        if normalized.contains(":") { return true } // IPv6 literal
        let octets = normalized.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { Int($0).map { (0...255).contains($0) } == true }
    }

    private enum LibraryError: LocalizedError {
        case unsupportedFile
        case invalidStreamURL
        case duplicateStream
        case damagedLibrary

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                "Choose an MP4, M4V, or MOV video from Files."
            case .invalidStreamURL:
                "Use an HTTPS video link, or a local HTTP link on your network."
            case .duplicateStream:
                "This video link is already saved."
            case .damagedLibrary:
                "The saved video list could not be read. Its files have been left untouched."
            }
        }
    }
}

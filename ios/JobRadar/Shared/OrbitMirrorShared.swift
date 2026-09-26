import Foundation

/// Cross-process storage shared by Orbit and its ReplayKit broadcast extension.
/// The extension writes a rolling HLS stream here; the main app serves and plays it.
enum OrbitMirrorShared {
    static let appGroupIdentifier = "group.com.hetpatel.jobradar"
    static let broadcastExtensionIdentifier = "com.hetpatel.jobradar.screen-broadcast"
    static let playlistFilename = "orbit-live.m3u8"
    static let initializationFilename = "orbit-init.mp4"

    private static let activeKey = "orbit.mirror.broadcastActive"
    private static let pausedKey = "orbit.mirror.broadcastPaused"
    private static let lastFrameKey = "orbit.mirror.lastFrameAt"
    private static let carDisplayWidthKey = "orbit.mirror.carDisplayWidth"
    private static let carDisplayHeightKey = "orbit.mirror.carDisplayHeight"
    private static let streamWidthKey = "orbit.mirror.streamWidth"
    private static let streamHeightKey = "orbit.mirror.streamHeight"

    /// Pixel size of the encoded stream. It has the car display's aspect
    /// ratio, so CarPlay shows it edge to edge without cropping or extra bars.
    struct Canvas: Equatable {
        let width: Int
        let height: Int
    }

    /// Used until a CarPlay display has connected. Most head units are 16:9 or wider.
    static let fallbackCanvas = Canvas(width: 1280, height: 720)

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var streamDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Library/Caches/OrbitMirror", isDirectory: true)
    }

    static var playlistURL: URL? {
        streamDirectory?.appendingPathComponent(playlistFilename)
    }

    static var isBroadcastActive: Bool {
        guard defaults?.bool(forKey: activeKey) == true else { return false }
        guard !isBroadcastPaused else { return true }
        guard let lastFrameDate else { return true }
        return Date().timeIntervalSince(lastFrameDate) < 5
    }

    static var isBroadcastPaused: Bool {
        defaults?.bool(forKey: pausedKey) == true
    }

    static var lastFrameDate: Date? {
        defaults?.object(forKey: lastFrameKey) as? Date
    }

    static var hasPlayableStream: Bool {
        guard isBroadcastActive, let playlistURL else { return false }
        return FileManager.default.fileExists(atPath: playlistURL.path)
    }

    static func prepareStreamDirectory(clean: Bool) throws -> URL {
        guard let directory = streamDirectory else {
            throw NSError(
                domain: "OrbitMirror",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The Orbit App Group container is unavailable."]
            )
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        if clean {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            for file in files where
                file.lastPathComponent == playlistFilename ||
                file.lastPathComponent == initializationFilename ||
                file.lastPathComponent.hasPrefix("orbit-segment-") {
                try? FileManager.default.removeItem(at: file)
            }
        }

        return directory
    }

    static func updateBroadcastState(active: Bool, paused: Bool = false) {
        defaults?.set(active, forKey: activeKey)
        defaults?.set(paused, forKey: pausedKey)
        if active {
            defaults?.set(Date(), forKey: lastFrameKey)
        }
    }

    static func noteFrame() {
        defaults?.set(Date(), forKey: lastFrameKey)
    }

    /// Saved by the app when CarPlay connects. It persists, so a broadcast
    /// started before the car connects still uses the usual car's shape.
    static func recordCarDisplay(width: Int, height: Int) {
        guard min(width, height) >= 240 else { return }
        defaults?.set(width, forKey: carDisplayWidthKey)
        defaults?.set(height, forKey: carDisplayHeightKey)
    }

    /// The canvas the broadcast extension should encode for the last car display.
    static var requestedCanvas: Canvas {
        let width = defaults?.integer(forKey: carDisplayWidthKey) ?? 0
        let height = defaults?.integer(forKey: carDisplayHeightKey) ?? 0
        return canvas(forDisplayWidth: width, height: height)
    }

    static func canvas(forDisplayWidth width: Int, height: Int) -> Canvas {
        guard min(width, height) >= 240 else { return fallbackCanvas }
        let aspectRatio = Double(width) / Double(height)
        guard (0.25...4).contains(aspectRatio) else { return fallbackCanvas }

        // Encode at the display's own resolution, capped so the extension's
        // frame buffers stay well inside its 50 MB memory limit.
        let maximumLongEdge = 1920.0
        let maximumPixels = 1920.0 * 720.0
        let displayWidth = Double(width)
        let displayHeight = Double(height)
        let scale = min(
            1,
            maximumLongEdge / max(displayWidth, displayHeight),
            (maximumPixels / (displayWidth * displayHeight)).squareRoot()
        )
        // H.264 needs even dimensions.
        func even(_ value: Double) -> Int { max(2, Int(value / 2) * 2) }
        return Canvas(width: even(displayWidth * scale), height: even(displayHeight * scale))
    }

    static func recordStreamCanvas(_ canvas: Canvas) {
        defaults?.set(canvas.width, forKey: streamWidthKey)
        defaults?.set(canvas.height, forKey: streamHeightKey)
    }

    /// True once the extension is encoding at the current car display's shape.
    static var streamMatchesCarDisplay: Bool {
        let width = defaults?.integer(forKey: streamWidthKey) ?? 0
        let height = defaults?.integer(forKey: streamHeightKey) ?? 0
        return Canvas(width: width, height: height) == requestedCanvas
    }
}

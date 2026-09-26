import AVFoundation
import CarPlay
import CoreMedia
import MediaPlayer
import Network
import UIKit

@MainActor
final class OrbitMirrorPlaybackController {
    static let shared = OrbitMirrorPlaybackController()

    private let server = OrbitMirrorHTTPServer()
    private var player: AVPlayer?
    private var installedRemoteCommands = false

    private init() {}

    func startPlayback() async throws {
        let baseURL = try await server.playlistURL()
        try await waitForPlayableStream()

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "session", value: UUID().uuidString)]
        guard let playlistURL = components?.url else {
            throw OrbitMirrorError.serverUnavailable
        }

        try play(url: playlistURL, title: "iPhone Screen", artist: "Orbit Screen Mirror", isLive: true)
    }

    func playVideo(_ video: OrbitCarPlayVideo) throws {
        if video.isImportedFile && !FileManager.default.fileExists(atPath: video.playbackURL.path) {
            throw OrbitMirrorError.videoMissing
        }
        try play(url: video.playbackURL, title: video.title, artist: "Orbit Video", isLive: false)
    }

    private func play(url: URL, title: String, artist: String, isLive: Bool) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try audioSession.setActive(true)

        let item = AVPlayerItem(url: url)
        if isLive {
            item.preferredForwardBufferDuration = 1
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        }

        stopPlayback()
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        // CarPlay owns the video surface. Fit, never fill: the mirror is already
        // encoded at the car display's shape, and filling would crop videos
        // whose shape differs from the display.
        player.externalPlaybackVideoGravity = .resizeAspect
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player

        installRemoteCommandsIfNeeded()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyPlaybackRate: 1
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
        player.play()
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func waitForPlayableStream() async throws {
        for attempt in 0..<30 {
            // Prefer a stream encoded for this car's display. The broadcast
            // restarts at the new shape within a couple of seconds of a new
            // car connecting; after 4 s, play whatever is ready.
            if OrbitMirrorShared.hasPlayableStream,
               OrbitMirrorShared.streamMatchesCarDisplay || attempt >= 20 {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw OrbitMirrorError.broadcastNotStarted
    }

    private func installRemoteCommandsIfNeeded() {
        guard !installedRemoteCommands else { return }
        installedRemoteCommands = true
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player?.play()
                MPNowPlayingInfoCenter.default().playbackState = .playing
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.player?.pause()
                MPNowPlayingInfoCenter.default().playbackState = .paused
            }
            return .success
        }
        commands.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stopPlayback() }
            return .success
        }
    }
}

@MainActor
final class OrbitCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate,
    CPInterfaceControllerDelegate, CPSessionConfigurationDelegate {
    private var interfaceController: CPInterfaceController?
    private var sessionConfiguration: CPSessionConfiguration?
    private var videoLibraryObserver: NSObjectProtocol?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.delegate = self
        sessionConfiguration = CPSessionConfiguration(delegate: self)
        // The broadcast extension encodes the mirror at this display's shape.
        let carScreen = templateApplicationScene.carWindow.screen
        OrbitMirrorShared.recordCarDisplay(
            width: Int((carScreen.bounds.width * carScreen.scale).rounded()),
            height: Int((carScreen.bounds.height * carScreen.scale).rounded())
        )
        interfaceController.setRootTemplate(makeRootTemplate(), animated: false, completion: nil)
        videoLibraryObserver = NotificationCenter.default.addObserver(
            forName: OrbitCarPlayVideoLibrary.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let interfaceController = self.interfaceController else { return }
                interfaceController.setRootTemplate(self.makeRootTemplate(), animated: false, completion: nil)
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        OrbitMirrorPlaybackController.shared.stopPlayback()
        if let videoLibraryObserver {
            NotificationCenter.default.removeObserver(videoLibraryObserver)
        }
        videoLibraryObserver = nil
        self.interfaceController?.delegate = nil
        self.interfaceController = nil
        sessionConfiguration = nil
    }

    private func makeRootTemplate() -> CPListTemplate {
        let mirror = CPListItem(
            text: "Mirror iPhone Screen",
            detailText: mirrorDetail,
            image: UIImage(systemName: "rectangle.on.rectangle")
        )
        mirror.accessoryType = .disclosureIndicator

        if #available(iOS 26.4, *) {
            mirror.playbackConfiguration = CPPlaybackConfiguration(
                preferredPresentation: .video,
                playbackAction: .play,
                elapsedTime: .zero,
                duration: .zero
            )
        }

        mirror.handler = { [weak self] _, completion in
            Task { @MainActor in
                await self?.startMirror()
                completion()
            }
        }

        let instructions = CPListItem(
            text: "Start on your iPhone first",
            detailText: "Orbit Settings → CarPlay Screen Mirror → broadcast button"
        )
        instructions.isEnabled = false

        let safety = CPListItem(
            text: "Passenger use while parked",
            detailText: "CarPlay controls when video is available."
        )
        safety.isEnabled = false

        let videos = OrbitCarPlayVideoLibrary.shared.videos
        let library = CPListItem(
            text: "Your Videos",
            detailText: videos.isEmpty ? "Add a video in Orbit Settings" : "\(videos.count) ready to play",
            image: UIImage(systemName: "play.rectangle")
        )
        library.isEnabled = !videos.isEmpty
        library.handler = { [weak self] _, completion in
            self?.showVideos()
            completion()
        }

        return CPListTemplate(
            title: "Orbit Video",
            sections: [CPListSection(items: [library, mirror, instructions, safety])]
        )
    }

    private func showVideos() {
        let template = CPListTemplate(title: "Your Videos", sections: [CPListSection(items: [])])
        updateVideoPage(template, page: 0)
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func updateVideoPage(_ template: CPListTemplate, page: Int) {
        let videos = OrbitCarPlayVideoLibrary.shared.videos
        let pageSize = max(1, Int(CPListTemplate.maximumItemCount) - 2)
        let start = page * pageSize
        let end = min(start + pageSize, videos.count)
        var items: [CPListItem] = []

        if page > 0 {
            let previous = CPListItem(text: "Previous Videos", detailText: nil)
            previous.handler = { [weak self, weak template] _, completion in
                if let template { self?.updateVideoPage(template, page: page - 1) }
                completion()
            }
            items.append(previous)
        }
        if start < end {
            for video in videos[start..<end] {
                let item = CPListItem(
                    text: video.title,
                    detailText: "Play on the car display",
                    image: UIImage(systemName: "play.rectangle")
                )
                if #available(iOS 26.4, *) {
                    item.playbackConfiguration = CPPlaybackConfiguration(
                        preferredPresentation: .video,
                        playbackAction: .play,
                        elapsedTime: .zero,
                        duration: .zero
                    )
                }
                item.handler = { [weak self] _, completion in
                    self?.startVideo(video)
                    completion()
                }
                items.append(item)
            }
        }
        if end < videos.count {
            let next = CPListItem(text: "More Videos", detailText: nil)
            next.handler = { [weak self, weak template] _, completion in
                if let template { self?.updateVideoPage(template, page: page + 1) }
                completion()
            }
            items.append(next)
        }
        template.updateSections([CPListSection(items: items)])
    }

    private var mirrorDetail: String {
        guard #available(iOS 26.4, *) else {
            return "Requires a newer iOS version with CarPlay video."
        }
        if sessionConfiguration?.supportsVideoPlayback != true {
            return "This CarPlay session does not advertise video support."
        }
        if OrbitMirrorShared.hasPlayableStream {
            return "Screen broadcast detected. Tap to show it on the car display."
        }
        return "Start Orbit Screen Broadcast on your iPhone, then tap here."
    }

    private func startMirror() async {
        guard #available(iOS 26.4, *) else {
            presentAlert(
                title: "Newer iOS required",
                message: "CarPlay video presentation requires iOS 26.4 or later."
            )
            return
        }
        guard sessionConfiguration?.supportsVideoPlayback == true else {
            presentAlert(
                title: "Video isn't supported",
                message: "This vehicle or current CarPlay session did not enable video playback."
            )
            return
        }

        do {
            try await OrbitMirrorPlaybackController.shared.startPlayback()
        } catch {
            presentAlert(title: "Screen mirror isn't ready", message: error.localizedDescription)
        }
    }

    private func startVideo(_ video: OrbitCarPlayVideo) {
        guard #available(iOS 26.4, *) else {
            presentAlert(
                title: "Newer iOS required",
                message: "CarPlay video presentation requires iOS 26.4 or later."
            )
            return
        }
        guard sessionConfiguration?.supportsVideoPlayback == true else {
            presentAlert(
                title: "Video isn't supported",
                message: "This vehicle or current CarPlay session did not enable video playback."
            )
            return
        }
        do {
            try OrbitMirrorPlaybackController.shared.playVideo(video)
        } catch {
            presentAlert(title: "Video couldn't start", message: error.localizedDescription)
        }
    }

    private func presentAlert(title: String, message: String) {
        guard let interfaceController else { return }
        let action = CPAlertAction(title: "OK", style: .default) { _ in }
        let alert = CPAlertTemplate(titleVariants: ["\(title)\n\(message)", title], actions: [action])
        interfaceController.presentTemplate(alert, animated: true, completion: { _, _ in })
    }
}

private enum OrbitMirrorError: LocalizedError {
    case broadcastNotStarted
    case serverUnavailable
    case videoMissing

    var errorDescription: String? {
        switch self {
        case .broadcastNotStarted:
            "Open Orbit Settings on your iPhone and start Orbit Screen Broadcast first."
        case .serverUnavailable:
            "Orbit could not start its private live-video server."
        case .videoMissing:
            "This imported video is missing. Remove it in Orbit Settings and import it again."
        }
    }
}

private final class OrbitMirrorHTTPServer {
    private let queue = DispatchQueue(label: "com.hetpatel.jobradar.mirror-http")
    private var listener: NWListener?
    private var readyURL: URL?
    private var pending: [(Result<URL, Error>) -> Void] = []

    func playlistURL() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            start { result in continuation.resume(with: result) }
        }
    }

    private func start(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if let readyURL {
                completion(.success(readyURL))
                return
            }
            pending.append(completion)
            guard listener == nil else { return }

            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener
                listener.service = NWListener.Service(
                    name: "Orbit Screen Mirror",
                    type: "_orbitmirror._tcp"
                )
                listener.newConnectionHandler = { [weak self] connection in
                    self?.serve(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handle(state)
                }
                listener.start(queue: queue)
            } catch {
                finishPending(with: .failure(error))
            }
        }
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port else {
                finishPending(with: .failure(OrbitMirrorError.serverUnavailable))
                return
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = ProcessInfo.processInfo.hostName
            components.port = Int(port.rawValue)
            components.path = "/\(OrbitMirrorShared.playlistFilename)"
            guard let url = components.url else {
                finishPending(with: .failure(OrbitMirrorError.serverUnavailable))
                return
            }
            readyURL = url
            finishPending(with: .success(url))
        case let .failed(error):
            listener?.cancel()
            listener = nil
            finishPending(with: .failure(error))
        default:
            break
        }
    }

    private func finishPending(with result: Result<URL, Error>) {
        let callbacks = pending
        pending.removeAll()
        callbacks.forEach { $0(result) }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, _, error in
            guard let self, error == nil, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let request = String(decoding: data, as: UTF8.self)
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: String) -> Data {
        let lines = request.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        guard requestParts.count >= 2 else { return errorResponse(status: "400 Bad Request") }

        let rawTarget = String(requestParts[1])
        let path = URLComponents(string: rawTarget)?.path ?? rawTarget
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let isAllowed = filename == OrbitMirrorShared.playlistFilename ||
            filename == OrbitMirrorShared.initializationFilename ||
            (filename.hasPrefix("orbit-segment-") && filename.hasSuffix(".m4s"))
        guard isAllowed, let directory = OrbitMirrorShared.streamDirectory else {
            return errorResponse(status: "404 Not Found")
        }

        let fileURL = directory.appendingPathComponent(filename)
        guard let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return errorResponse(status: "404 Not Found")
        }

        let rangeHeader = lines.first { $0.lowercased().hasPrefix("range:") }
        let selected = byteRange(from: rangeHeader, count: fileData.count)
        let body: Data
        let status: String
        var extraHeaders: [String] = []
        if let selected {
            body = fileData.subdata(in: selected)
            status = "206 Partial Content"
            extraHeaders.append(
                "Content-Range: bytes \(selected.lowerBound)-\(selected.upperBound - 1)/\(fileData.count)"
            )
        } else {
            body = fileData
            status = "200 OK"
        }

        let contentType: String
        switch fileURL.pathExtension.lowercased() {
        case "m3u8": contentType = "application/vnd.apple.mpegurl"
        case "m4s": contentType = "video/iso.segment"
        default: contentType = "video/mp4"
        }

        var headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Accept-Ranges: bytes",
            "Cache-Control: no-store, no-cache, must-revalidate",
            "Connection: close"
        ]
        headers.append(contentsOf: extraHeaders)
        headers.append("")
        headers.append("")

        var response = Data(headers.joined(separator: "\r\n").utf8)
        response.append(body)
        return response
    }

    private func byteRange(from header: String?, count: Int) -> Range<Int>? {
        guard
            count > 0,
            let header,
            let value = header.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces),
            value.lowercased().hasPrefix("bytes=")
        else { return nil }

        let bounds = value.dropFirst("bytes=".count).split(separator: "-", maxSplits: 1)
        guard let startText = bounds.first, let start = Int(startText), start < count else { return nil }
        let requestedEnd = bounds.count > 1 ? Int(bounds[1]) : nil
        let end = min((requestedEnd ?? (count - 1)) + 1, count)
        guard start < end else { return nil }
        return start..<end
    }

    private func errorResponse(status: String) -> Data {
        Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}

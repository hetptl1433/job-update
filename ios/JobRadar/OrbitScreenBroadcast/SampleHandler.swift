import AVFoundation
import CoreImage
import Foundation
import ReplayKit
import UniformTypeIdentifiers

final class SampleHandler: RPBroadcastSampleHandler {
    private var streamWriter: OrbitHLSStreamWriter?
    private var lastCanvasCheck = Date.distantPast

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        do {
            _ = try OrbitMirrorShared.prepareStreamDirectory(clean: true)
            OrbitMirrorShared.updateBroadcastState(active: true)
        } catch {
            finishBroadcastWithError(error)
        }
    }

    override func broadcastPaused() {
        OrbitMirrorShared.updateBroadcastState(active: true, paused: true)
    }

    override func broadcastResumed() {
        OrbitMirrorShared.updateBroadcastState(active: true)
    }

    override func broadcastFinished() {
        OrbitMirrorShared.updateBroadcastState(active: false)
        streamWriter?.finish()
        streamWriter = nil
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        do {
            switch sampleBufferType {
            case .video:
                try restartStreamIfCarDisplayChanged()
                if streamWriter == nil {
                    let canvas = OrbitMirrorShared.requestedCanvas
                    streamWriter = try OrbitHLSStreamWriter(firstVideoSample: sampleBuffer, canvas: canvas)
                    OrbitMirrorShared.recordStreamCanvas(canvas)
                }
                try streamWriter?.appendVideo(sampleBuffer)
                OrbitMirrorShared.noteFrame()
            case .audioApp:
                try streamWriter?.appendAudio(sampleBuffer)
            case .audioMic:
                // The picker intentionally hides microphone capture. Mirroring
                // app audio avoids recording conversations in the vehicle.
                break
            @unknown default:
                break
            }
        } catch {
            OrbitMirrorShared.updateBroadcastState(active: false)
            streamWriter?.cancel()
            streamWriter = nil
            finishBroadcastWithError(error)
        }
    }

    /// A car that connects after the broadcast started can have a different
    /// display shape, so start a fresh stream at that shape. Checked once a
    /// second rather than reading shared defaults on every frame.
    private func restartStreamIfCarDisplayChanged() throws {
        guard let streamWriter else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCanvasCheck) >= 1 else { return }
        lastCanvasCheck = now
        guard OrbitMirrorShared.requestedCanvas != streamWriter.canvas else { return }

        streamWriter.cancel()
        self.streamWriter = nil
        _ = try OrbitMirrorShared.prepareStreamDirectory(clean: true)
    }
}

private final class OrbitHLSStreamWriter: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    let canvas: OrbitMirrorShared.Canvas

    private struct Segment {
        let sequence: Int
        let duration: Double
        let filename: String
    }

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let videoAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput
    private let directory: URL
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let outputColorSpace = CGColorSpaceCreateDeviceRGB()
    private let outputBounds: CGRect
    private let letterbox: CIImage
    private let stateLock = NSLock()
    private var segments: [Segment] = []
    private var nextSequence = 0
    private var hasWrittenInitialization = false
    private var hasFinished = false
    private var isCancelled = false
    private let maximumSegments = 10

    init(firstVideoSample: CMSampleBuffer, canvas: OrbitMirrorShared.Canvas) throws {
        guard CMSampleBufferGetImageBuffer(firstVideoSample) != nil else {
            throw NSError(
                domain: "OrbitMirror",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "ReplayKit did not provide a video image buffer."]
            )
        }

        self.canvas = canvas
        outputBounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        letterbox = CIImage(color: .black).cropped(to: outputBounds)
        directory = try OrbitMirrorShared.prepareStreamDirectory(clean: false)
        writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        writer.initialSegmentStartTime = CMSampleBufferGetPresentationTimeStamp(firstVideoSample)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: canvas.width,
            AVVideoHeightKey: canvas.height,
            AVVideoCompressionPropertiesKey: [
                // About 5 Mbps at 1280×720, scaled with the canvas area.
                AVVideoAverageBitRateKey: min(8_000_000, max(2_000_000, canvas.width * canvas.height * 11 / 2)),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalDurationKey: 1,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: canvas.width,
                kCVPixelBufferHeightKey as String: canvas.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        super.init()
        writer.delegate = self

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw NSError(
                domain: "OrbitMirror",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The live HLS encoder could not add its media inputs."]
            )
        }
        writer.add(videoInput)
        writer.add(audioInput)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "OrbitMirror",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The live HLS encoder could not start."]
            )
        }
        writer.startSession(atSourceTime: writer.initialSegmentStartTime)
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) throws {
        guard writer.status == .writing else {
            throw writer.error ?? NSError(
                domain: "OrbitMirror",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "The live HLS encoder stopped unexpectedly."]
            )
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(
                domain: "OrbitMirror",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "ReplayKit did not provide a video image buffer."]
            )
        }
        guard let pool = videoAdaptor.pixelBufferPool else {
            throw NSError(
                domain: "OrbitMirror",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "The live video buffer pool is unavailable."]
            )
        }

        var destinationBuffer: CVPixelBuffer?
        let poolStatus = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pool,
            &destinationBuffer
        )
        guard poolStatus == kCVReturnSuccess, let destinationBuffer else {
            throw NSError(
                domain: "OrbitMirror",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "The live video encoder could not allocate a frame."]
            )
        }

        let orientedFrame = CIImage(cvPixelBuffer: sourceBuffer)
            .oriented(Self.videoOrientation(for: sampleBuffer))
        let sourceBounds = orientedFrame.extent
        guard sourceBounds.width > 0, sourceBounds.height > 0 else {
            throw NSError(
                domain: "OrbitMirror",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "ReplayKit provided an empty screen frame."]
            )
        }

        // Fit the whole iPhone screen inside the car-shaped canvas, with black
        // bars on the sides. Filling it would crop a portrait screen to a thin band.
        let scale = min(
            outputBounds.width / sourceBounds.width,
            outputBounds.height / sourceBounds.height
        )
        let frame = orientedFrame
            .transformed(by: CGAffineTransform(
                translationX: -sourceBounds.minX,
                y: -sourceBounds.minY
            ))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: ((outputBounds.width - sourceBounds.width * scale) / 2).rounded(),
                y: ((outputBounds.height - sourceBounds.height * scale) / 2).rounded()
            ))
            // Pooled buffers keep old pixels, so paint the bars every frame.
            .composited(over: letterbox)
        imageContext.render(
            frame,
            to: destinationBuffer,
            bounds: outputBounds,
            colorSpace: outputColorSpace
        )

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard videoAdaptor.append(destinationBuffer, withPresentationTime: timestamp) else {
            throw writer.error ?? NSError(
                domain: "OrbitMirror",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "A captured screen frame could not be encoded."]
            )
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) throws {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp >= writer.initialSegmentStartTime else { return }
        try append(sampleBuffer, to: audioInput)
    }

    func finish() {
        stateLock.lock()
        guard !hasFinished else {
            stateLock.unlock()
            return
        }
        hasFinished = true
        stateLock.unlock()

        videoInput.markAsFinished()
        audioInput.markAsFinished()
        writer.finishWriting { [weak self] in
            self?.writePlaylist(isFinished: true)
        }
    }

    func cancel() {
        stateLock.lock()
        isCancelled = true
        stateLock.unlock()
        writer.cancelWriting()
    }

    func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        // A replacement stream may already own the directory.
        stateLock.lock()
        let cancelled = isCancelled
        stateLock.unlock()
        guard !cancelled else { return }

        do {
            switch segmentType {
            case .initialization:
                try segmentData.write(
                    to: directory.appendingPathComponent(OrbitMirrorShared.initializationFilename),
                    options: .atomic
                )
                stateLock.lock()
                hasWrittenInitialization = true
                stateLock.unlock()
            case .separable:
                let duration = Self.duration(from: segmentReport)
                stateLock.lock()
                let sequence = nextSequence
                nextSequence += 1
                let filename = "orbit-segment-\(sequence).m4s"
                stateLock.unlock()

                try segmentData.write(
                    to: directory.appendingPathComponent(filename),
                    options: .atomic
                )

                stateLock.lock()
                segments.append(Segment(sequence: sequence, duration: duration, filename: filename))
                let expired = segments.count > maximumSegments
                    ? Array(segments.prefix(segments.count - maximumSegments))
                    : []
                if !expired.isEmpty {
                    segments.removeFirst(expired.count)
                }
                stateLock.unlock()

                writePlaylist(isFinished: false)
                for oldSegment in expired {
                    try? FileManager.default.removeItem(
                        at: directory.appendingPathComponent(oldSegment.filename)
                    )
                }
            @unknown default:
                break
            }
        } catch {
            // A following playlist refresh can recover from a single failed
            // segment write. ReplayKit will stop the extension for fatal errors.
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput) throws {
        guard writer.status == .writing else {
            throw writer.error ?? NSError(
                domain: "OrbitMirror",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "The live HLS encoder stopped unexpectedly."]
            )
        }
        if input.isReadyForMoreMediaData, !input.append(sampleBuffer) {
            throw writer.error ?? NSError(
                domain: "OrbitMirror",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "A captured screen frame could not be encoded."]
            )
        }
    }

    private func writePlaylist(isFinished: Bool) {
        stateLock.lock()
        let snapshot = segments
        let initializationReady = hasWrittenInitialization
        let cancelled = isCancelled
        stateLock.unlock()

        guard !cancelled, initializationReady, !snapshot.isEmpty else { return }
        let targetDuration = max(1, Int(ceil(snapshot.map(\.duration).max() ?? 1)))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(targetDuration)",
            "#EXT-X-MEDIA-SEQUENCE:\(snapshot[0].sequence)",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-MAP:URI=\"\(OrbitMirrorShared.initializationFilename)\""
        ]
        for segment in snapshot {
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
            lines.append(segment.filename)
        }
        if isFinished {
            lines.append("#EXT-X-ENDLIST")
        }
        lines.append("")

        try? Data(lines.joined(separator: "\n").utf8).write(
            to: directory.appendingPathComponent(OrbitMirrorShared.playlistFilename),
            options: .atomic
        )
    }

    private static func duration(from report: AVAssetSegmentReport?) -> Double {
        let durations = report?.trackReports.compactMap { track -> Double? in
            let seconds = track.duration.seconds
            return seconds.isFinite && seconds > 0 ? seconds : nil
        } ?? []
        return max(durations.max() ?? 1, 0.1)
    }

    private static func videoOrientation(for sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard
            let attachment = CMGetAttachment(
                sampleBuffer,
                key: RPVideoSampleOrientationKey as CFString,
                attachmentModeOut: nil
            ) as? NSNumber,
            let orientation = CGImagePropertyOrientation(rawValue: attachment.uint32Value)
        else {
            return .up
        }
        return orientation
    }
}

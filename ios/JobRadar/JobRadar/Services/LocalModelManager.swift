import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import UIKit
import os

/// An open-weights model Orbit downloads once and then runs entirely on the
/// iPhone or iPad with MLX. Each entry is pinned to an exact Hugging Face
/// commit so its weights, tokenizer and chat template never change underneath
/// the app.
struct LocalModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let repository: String
    let revision: String
    let downloadBytes: Int64
    /// Rough peak memory while answering: weights plus the prompt's KV cache.
    let workingSetBytes: Int64
    /// Smallest physical RAM the model is offered on.
    let minimumPhysicalMemory: UInt64
    /// Smallest physical RAM on which this is the recommended model.
    let recommendedPhysicalMemory: UInt64
    /// Prompt tokens Orbit fills before answering. A larger prompt holds more
    /// Orbit data but takes longer before the first word appears.
    let promptTokenBudget: Int
    let maxResponseTokens: Int
    /// The original Qwen3 models can think before answering; the 2507
    /// instruct update always answers directly.
    let supportsThinking: Bool
    /// Estimated speed on an iPhone 15 (A16), scaled for other devices by
    /// `DevicePerformance` until Orbit has measured the model on the device.
    let referenceSpeed: LocalModelSpeed

    /// Thinking stops after this many tokens or `thinkingTimeLimit`,
    /// whichever comes first, and the model answers from what it has.
    static let thinkingTokenLimit = 1_024
    static let thinkingTimeLimit: TimeInterval = 30

    /// A model is recommended only if a typical answer takes at most this long.
    static let comfortableAnswerSeconds: Double = 25

    var downloadSizeText: String {
        ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file)
    }

    var memoryText: String {
        ByteCountFormatter.string(fromByteCount: workingSetBytes, countStyle: .memory)
    }

    /// Measured on this device when Orbit has used the model, otherwise
    /// estimated from the chip.
    func speed(
        on performance: DevicePerformance = DeviceProfile.performance,
        measured: [String: LocalModelSpeed] = LocalModelSpeedStore.load()
    ) -> LocalModelSpeed {
        measured[id] ?? referenceSpeed.scaled(by: performance)
    }

    /// Seconds for a typical answer: reading a full prompt, then writing a
    /// short reply.
    func typicalAnswerSeconds(speed: LocalModelSpeed) -> Double {
        speed.secondsToRead(promptTokens: promptTokenBudget)
            + LocalModelSpeed.typicalReplyTokens / max(speed.replyTokensPerSecond, 1)
    }

    /// The longest thinking can add before the answer starts.
    func maxThinkingSeconds(speed: LocalModelSpeed) -> Double {
        min(
            Self.thinkingTimeLimit,
            Double(Self.thinkingTokenLimit) / max(speed.replyTokensPerSecond, 1)
        )
    }

    static let qwen3_8B = LocalModelOption(
        id: "qwen3-8b-4bit",
        name: "Qwen3 8B",
        detail: "Most capable, for iPads with plenty of memory",
        repository: "mlx-community/Qwen3-8B-4bit",
        revision: "545dc4251c05440727734bcd94334791f6ab0192",
        downloadBytes: 4_622_000_000,
        workingSetBytes: 5_600_000_000,
        minimumPhysicalMemory: 7_000_000_000,
        recommendedPhysicalMemory: 12_000_000_000,
        promptTokenBudget: 3_200,
        maxResponseTokens: 800,
        supportsThinking: true,
        referenceSpeed: LocalModelSpeed(promptTokensPerSecond: 100, replyTokensPerSecond: 6.5)
    )

    /// The July 2025 instruct update: stronger than the original Qwen3 4B and
    /// never spends time reasoning before it answers. Offered on 6 GB iPhones
    /// whose raised per-app limit holds it, but recommended only with 8 GB.
    static let qwen3_4B = LocalModelOption(
        id: "qwen3-4b-instruct-2507-4bit",
        name: "Qwen3 4B",
        detail: "Sharper answers, but slower and needs more memory",
        repository: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
        revision: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b",
        downloadBytes: 2_278_000_000,
        workingSetBytes: 3_300_000_000,
        minimumPhysicalMemory: 5_000_000_000,
        recommendedPhysicalMemory: 7_000_000_000,
        promptTokenBudget: 3_600,
        maxResponseTokens: 800,
        supportsThinking: false,
        referenceSpeed: LocalModelSpeed(promptTokensPerSecond: 210, replyTokensPerSecond: 13)
    )

    static let qwen3_1_7B = LocalModelOption(
        id: "qwen3-1.7b-4bit",
        name: "Qwen3 1.7B",
        detail: "Best balance of answer quality and speed on iPhone",
        repository: "mlx-community/Qwen3-1.7B-4bit",
        revision: "3b1b1768f8f8cf8351c712464f906e86c2b8269e",
        downloadBytes: 982_000_000,
        workingSetBytes: 1_600_000_000,
        minimumPhysicalMemory: 5_000_000_000,
        recommendedPhysicalMemory: 5_000_000_000,
        promptTokenBudget: 2_400,
        maxResponseTokens: 600,
        supportsThinking: true,
        referenceSpeed: LocalModelSpeed(promptTokensPerSecond: 470, replyTokensPerSecond: 28)
    )

    static let qwen3_0_6B = LocalModelOption(
        id: "qwen3-0.6b-4bit",
        name: "Qwen3 0.6B",
        detail: "Smallest and fastest, with simpler answers",
        repository: "mlx-community/Qwen3-0.6B-4bit",
        revision: "73e3e38d981303bc594367cd910ea6eb48349da8",
        downloadBytes: 350_000_000,
        workingSetBytes: 800_000_000,
        minimumPhysicalMemory: 2_500_000_000,
        recommendedPhysicalMemory: 0,
        promptTokenBudget: 2_400,
        maxResponseTokens: 600,
        supportsThinking: true,
        referenceSpeed: LocalModelSpeed(promptTokensPerSecond: 1_300, replyTokensPerSecond: 55)
    )

    /// Largest first.
    static let catalog = [qwen3_8B, qwen3_4B, qwen3_1_7B, qwen3_0_6B]

    /// Memory Orbit itself needs alongside the model.
    static let appMemoryReserve: UInt64 = 500_000_000

    /// Models this device can run. Beyond physical RAM, a model must fit the
    /// per-app memory limit iOS reports, which differs between devices with
    /// the same RAM (an 8 GB iPad allows more than an 8 GB iPhone).
    static func available(
        physicalMemory: UInt64 = DeviceProfile.physicalMemory,
        appMemoryLimit: UInt64? = DeviceProfile.appMemoryLimit
    ) -> [LocalModelOption] {
        catalog.filter { option in
            guard physicalMemory >= option.minimumPhysicalMemory else { return false }
            guard let appMemoryLimit else { return true }
            return appMemoryLimit >= UInt64(option.workingSetBytes) + appMemoryReserve
        }
    }

    /// The largest model this device runs comfortably: it leaves memory to
    /// spare, and this chip gives a typical answer within
    /// `comfortableAnswerSeconds`.
    static func recommended(
        physicalMemory: UInt64 = DeviceProfile.physicalMemory,
        appMemoryLimit: UInt64? = DeviceProfile.appMemoryLimit,
        performance: DevicePerformance = DeviceProfile.performance,
        measured: [String: LocalModelSpeed] = LocalModelSpeedStore.load()
    ) -> LocalModelOption? {
        let options = available(physicalMemory: physicalMemory, appMemoryLimit: appMemoryLimit)
        return options.first { option in
            physicalMemory >= option.recommendedPhysicalMemory
                && option.typicalAnswerSeconds(speed: option.speed(on: performance, measured: measured))
                    <= comfortableAnswerSeconds
        } ?? options.last
    }

    /// The owner's saved choice. Without one, the recommended model, unless
    /// only another model is already downloaded.
    static func selected(
        defaults: UserDefaults = .standard,
        physicalMemory: UInt64 = DeviceProfile.physicalMemory,
        appMemoryLimit: UInt64? = DeviceProfile.appMemoryLimit,
        performance: DevicePerformance = DeviceProfile.performance,
        measured: [String: LocalModelSpeed] = LocalModelSpeedStore.load(),
        isDownloaded: (LocalModelOption) -> Bool = LocalModelStorage.isDownloaded
    ) -> LocalModelOption? {
        let options = available(physicalMemory: physicalMemory, appMemoryLimit: appMemoryLimit)
        if let id = defaults.string(forKey: AppConfig.localModelPreferenceKey),
           let saved = options.first(where: { $0.id == id }) {
            return saved
        }
        let recommended = recommended(
            physicalMemory: physicalMemory,
            appMemoryLimit: appMemoryLimit,
            performance: performance,
            measured: measured
        )
        // A recommendation that changes as Orbit learns this device's speed
        // must not strand the owner on a model that isn't downloaded.
        if let recommended, isDownloaded(recommended) { return recommended }
        return options.first(where: isDownloaded) ?? recommended
    }
}

/// How fast a model reads Orbit's prompt and writes its reply.
struct LocalModelSpeed: Hashable, Codable, Sendable {
    var promptTokensPerSecond: Double
    var replyTokensPerSecond: Double
    /// Whether Orbit measured this on the device rather than estimating it.
    var isMeasured = false

    /// Tokens in a typical short Orbit Chat answer.
    static let typicalReplyTokens: Double = 150

    enum Rating: Comparable {
        case slow, moderate, fast, veryFast

        var title: String {
            switch self {
            case .slow: "Slow"
            case .moderate: "Moderate"
            case .fast: "Fast"
            case .veryFast: "Very fast"
            }
        }
    }

    /// A measurement from a finished reply, if it was long enough to trust.
    init?(measuring info: GenerateCompletionInfo) {
        guard info.promptTokenCount >= 400, info.generationTokenCount >= 24,
              info.promptTime > 0, info.generateTime > 0 else { return nil }
        self.init(
            promptTokensPerSecond: info.promptTokensPerSecond,
            replyTokensPerSecond: info.tokensPerSecond,
            isMeasured: true
        )
    }

    init(promptTokensPerSecond: Double, replyTokensPerSecond: Double, isMeasured: Bool = false) {
        self.promptTokensPerSecond = promptTokensPerSecond
        self.replyTokensPerSecond = replyTokensPerSecond
        self.isMeasured = isMeasured
    }

    func secondsToRead(promptTokens: Int) -> Double {
        Double(promptTokens) / max(promptTokensPerSecond, 1)
    }

    func scaled(by performance: DevicePerformance) -> LocalModelSpeed {
        LocalModelSpeed(
            promptTokensPerSecond: promptTokensPerSecond * performance.promptSpeed,
            replyTokensPerSecond: replyTokensPerSecond * performance.replySpeed
        )
    }

    static func rating(answerSeconds: Double) -> Rating {
        switch answerSeconds {
        case ..<8: .veryFast
        case ..<15: .fast
        case ..<LocalModelOption.comfortableAnswerSeconds: .moderate
        default: .slow
        }
    }
}

/// Speeds measured while answering, per model, so the estimates give way to
/// what this device actually does.
enum LocalModelSpeedStore {
    private static let key = "orbit.localModel.measuredSpeeds.v1"

    static func load(defaults: UserDefaults = .standard) -> [String: LocalModelSpeed] {
        guard let data = defaults.data(forKey: key),
              let speeds = try? JSONDecoder().decode([String: LocalModelSpeed].self, from: data)
        else { return [:] }
        return speeds
    }

    /// Blends a measurement into the saved one, so a single answer on a warm
    /// device doesn't swing the recommendation.
    @discardableResult
    static func record(
        _ sample: LocalModelSpeed,
        for optionID: String,
        defaults: UserDefaults = .standard
    ) -> [String: LocalModelSpeed] {
        var speeds = load(defaults: defaults)
        let previous = speeds[optionID]
        func blend(_ old: Double?, _ new: Double) -> Double {
            old.map { $0 * 0.6 + new * 0.4 } ?? new
        }
        speeds[optionID] = LocalModelSpeed(
            promptTokensPerSecond: blend(previous?.promptTokensPerSecond, sample.promptTokensPerSecond),
            replyTokensPerSecond: blend(previous?.replyTokensPerSecond, sample.replyTokensPerSecond),
            isMeasured: true
        )
        if let data = try? JSONEncoder().encode(speeds) {
            defaults.set(data, forKey: key)
        }
        return speeds
    }
}

/// Downloaded model files live in Application Support, which iOS never purges,
/// and are excluded from iCloud and device backups because they can always be
/// downloaded again.
enum LocalModelStorage {
    static let directory: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orbit/LocalModels", isDirectory: true)
    }()

    static func isDownloaded(_ option: LocalModelOption) -> Bool {
        UserDefaults.standard.string(forKey: markerKey(for: option)) == option.revision
            && FileManager.default.fileExists(atPath: snapshotDirectory(for: option).path)
    }

    static var downloadedOptions: [LocalModelOption] {
        LocalModelOption.catalog.filter(isDownloaded)
    }

    static func snapshotDirectory(for option: LocalModelOption) -> URL {
        cache.snapshotsDirectory(repo: repo(for: option), kind: .model)
            .appendingPathComponent(option.revision, isDirectory: true)
    }

    static func markDownloaded(_ option: LocalModelOption) {
        UserDefaults.standard.set(option.revision, forKey: markerKey(for: option))
    }

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }

    static func remove(_ option: LocalModelOption) throws {
        UserDefaults.standard.removeObject(forKey: markerKey(for: option))
        let fileManager = FileManager.default
        for url in [
            cache.repoDirectory(repo: repo(for: option), kind: .model),
            cache.metadataDirectory(repo: repo(for: option), kind: .model)
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static var availableCapacity: Int64? {
        try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    static let client = HubClient(host: HubClient.defaultHost, userAgent: "Orbit-iOS", cache: cache)

    private static var cache: HubCache {
        HubCache(cacheDirectory: directory)
    }

    private static func repo(for option: LocalModelOption) -> HuggingFace.Repo.ID {
        let parts = option.repository.split(separator: "/", maxSplits: 1).map(String.init)
        return HuggingFace.Repo.ID(namespace: parts.first ?? "", name: parts.last ?? option.repository)
    }

    private static func markerKey(for option: LocalModelOption) -> String {
        "orbit.localModel.downloadedRevision.\(option.id)"
    }
}

enum LocalModelError: LocalizedError {
    case unavailable(String)
    case notDownloaded
    case insufficientMemory
    case appInactive
    case interrupted

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            reason
        case .notDownloaded:
            "Download the on-device model first."
        case .insufficientMemory:
            "There isn't enough free memory to load the on-device model right now. Close a few apps and try again, or choose a smaller model in Settings."
        case .appInactive:
            "Orbit pauses the on-device model while it isn't on screen. Ask again."
        case .interrupted:
            "The on-device model was unloaded before it could answer. Ask again."
        }
    }
}

/// Downloads, loads and runs Orbit Chat's on-device model.
///
/// MLX needs Metal GPU features the iOS Simulator doesn't provide, so the
/// model only runs on a physical iPhone or iPad. iOS also rejects GPU work
/// from apps in the background, and MLX treats a rejected GPU command as
/// fatal, so generation stops as soon as Orbit leaves the foreground and the
/// model is unloaded to give its memory back.
@MainActor
final class LocalModelManager: ObservableObject {
    enum Availability: Equatable {
        case unsupported(String)
        case notDownloaded
        case downloading(fractionCompleted: Double)
        case downloaded
    }

    /// The one download in progress, which need not be the selected model.
    struct Download: Equatable {
        let optionID: String
        var fractionCompleted: Double
    }

    @Published private(set) var option: LocalModelOption?
    @Published private(set) var availability: Availability = .notDownloaded
    @Published private(set) var isLoading = false
    @Published private(set) var activeDownload: Download?
    @Published private(set) var downloadError: String?
    /// The model `downloadError` is about.
    @Published private(set) var downloadErrorOptionID: String?
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var measuredSpeeds = LocalModelSpeedStore.load()

    private let logger = Logger(subsystem: "com.hetpatel.jobradar", category: "LocalModel")
    private var container: ModelContainer?
    private var loadedOptionID: String?
    private var loadTask: Task<ModelContainer, Error>?
    /// Incremented by `unload()` so a load that finishes afterwards is discarded.
    private var loadEpoch = 0
    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?
    /// A model downloaded while another could answer becomes the selected one
    /// when its download finishes.
    private var selectWhenDownloaded: String?
    private var generationTask: Task<Void, Never>?
    private var generationID: UUID?
    private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        option = LocalModelOption.selected()
        refreshAvailability()
        observeLifecycle()
    }

    var isReady: Bool { availability == .downloaded }

    /// This device's speed for `option`, measured or estimated.
    func speed(of option: LocalModelOption) -> LocalModelSpeed {
        option.speed(measured: measuredSpeeds)
    }

    /// Like `availability`, for any model rather than the selected one.
    func state(of target: LocalModelOption) -> Availability {
        if let reason = Self.unsupportedReason(for: target) { return .unsupported(reason) }
        if let activeDownload, activeDownload.optionID == target.id {
            return .downloading(fractionCompleted: activeDownload.fractionCompleted)
        }
        return downloadedIDs.contains(target.id) ? .downloaded : .notDownloaded
    }

    // MARK: Model choice and storage

    func select(_ newOption: LocalModelOption) {
        selectWhenDownloaded = nil
        guard newOption.id != option?.id else { return }
        cancelGeneration()
        unload()
        option = newOption
        UserDefaults.standard.set(newOption.id, forKey: AppConfig.localModelPreferenceKey)
        clearDownloadError()
        refreshAvailability()
    }

    func refreshAvailability() {
        let downloaded = Set(LocalModelStorage.downloadedOptions.map(\.id))
        if downloaded != downloadedIDs { downloadedIDs = downloaded }
        if let reason = Self.unsupportedReason(for: option) {
            availability = .unsupported(reason)
        } else if let activeDownload, activeDownload.optionID == option?.id {
            availability = .downloading(fractionCompleted: activeDownload.fractionCompleted)
        } else if let option, downloaded.contains(option.id) {
            availability = .downloaded
        } else {
            availability = .notDownloaded
        }
    }

    /// Downloads the selected model.
    func download() {
        guard let option else { return }
        download(option)
    }

    /// Downloads `target`, one model at a time. While another model can
    /// answer, it keeps answering until the download finishes.
    func download(_ target: LocalModelOption) {
        guard activeDownload == nil, !LocalModelStorage.isDownloaded(target),
              Self.unsupportedReason(for: target) == nil else { return }
        let required = target.downloadBytes + 300_000_000
        if let free = LocalModelStorage.availableCapacity, free < required {
            let size = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            downloadError = "Free up about \(size) on this \(DeviceProfile.name), then try again."
            downloadErrorOptionID = target.id
            return
        }

        if isReady, target.id != option?.id {
            selectWhenDownloaded = target.id
        } else {
            select(target)
        }
        clearDownloadError()
        activeDownload = Download(optionID: target.id, fractionCompleted: 0)
        refreshAvailability()
        // A locked screen suspends Orbit and stops the download.
        UIApplication.shared.isIdleTimerDisabled = true
        let id = UUID()
        downloadID = id
        logger.info("Downloading \(target.repository, privacy: .public) at \(target.revision, privacy: .public)")
        downloadTask = Task { [weak self] in
            let result: Result<Void, Error>
            do {
                try LocalModelStorage.prepareDirectory()
                _ = try await HubModelDownloader(client: LocalModelStorage.client).download(
                    id: target.repository,
                    revision: target.revision,
                    matching: Self.modelFilePatterns,
                    useLatest: false
                ) { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        self?.updateDownload(id, fractionCompleted: fraction)
                    }
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.finishDownload(id, option: target, result: result)
        }
    }

    func cancelDownload() {
        guard let downloadTask else { return }
        downloadTask.cancel()
        self.downloadTask = nil
        downloadID = nil
        activeDownload = nil
        selectWhenDownloaded = nil
        UIApplication.shared.isIdleTimerDisabled = false
        refreshAvailability()
    }

    /// The downloaded model chat switches to when `target` is deleted while
    /// selected: the recommended model if it's here, otherwise the largest.
    func replacement(forDeleting target: LocalModelOption) -> LocalModelOption? {
        guard target.id == option?.id else { return nil }
        let candidates = LocalModelOption.available().filter {
            $0.id != target.id && downloadedIDs.contains($0.id)
        }
        let recommendedID = LocalModelOption.recommended(measured: measuredSpeeds)?.id
        return candidates.first { $0.id == recommendedID } ?? candidates.first
    }

    /// Frees one model's storage. Deleting the selected model switches chat
    /// to another downloaded model, or leaves it needing a download.
    func delete(_ target: LocalModelOption) {
        let replacement = replacement(forDeleting: target)
        if activeDownload?.optionID == target.id { cancelDownload() }
        if target.id == option?.id {
            cancelGeneration()
            unload()
        }
        do {
            try LocalModelStorage.remove(target)
            clearDownloadError()
        } catch {
            downloadError = "Orbit couldn't delete the model files: \(error.localizedDescription)"
            downloadErrorOptionID = target.id
        }
        refreshAvailability()
        if let replacement, !downloadedIDs.contains(target.id) { select(replacement) }
    }

    private func clearDownloadError() {
        downloadError = nil
        downloadErrorOptionID = nil
    }

    // MARK: Loading

    /// Loads the model ahead of the first question so the reply starts sooner.
    func preload() {
        guard isReady, container == nil, loadTask == nil,
              UIApplication.shared.applicationState == .active else { return }
        Task { _ = try? await loadedContainer() }
    }

    func unload() {
        loadEpoch += 1
        loadTask = nil
        isLoading = false
        guard container != nil else { return }
        container = nil
        loadedOptionID = nil
        MLX.Memory.clearCache()
        logger.info("Unloaded the on-device model")
    }

    // MARK: Answering

    /// Streams the reply as progressively longer snapshots. `makeRequest`
    /// builds the prompt for a given character budget of Orbit data; the
    /// prompt is measured with the model's tokenizer and the data is trimmed
    /// until it fits. `thinking` applies only to models that support it.
    func streamReply(
        thinking: Bool,
        makeRequest: @escaping @Sendable (_ dataCharacterBudget: Int) -> LocalAssistantPrompt.Request
    ) -> AsyncThrowingStream<AssistantReplySnapshot, Error> {
        cancelGeneration()
        let (stream, continuation) = AsyncThrowingStream<AssistantReplySnapshot, Error>.makeStream()
        let id = UUID()
        let task = Task { [weak self] in
            do {
                guard let self else { throw CancellationError() }
                try await self.generate(thinking: thinking, makeRequest: makeRequest, continuation: continuation)
                continuation.finish()
            } catch {
                continuation.finish(throwing: Self.isCancellation(error) ? nil : error)
            }
            if self?.generationID == id {
                self?.generationTask = nil
                self?.generationID = nil
            }
        }
        generationTask = task
        generationID = id
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
    }

    private func generate(
        thinking: Bool,
        makeRequest: @Sendable (Int) -> LocalAssistantPrompt.Request,
        continuation: AsyncThrowingStream<AssistantReplySnapshot, Error>.Continuation
    ) async throws {
        guard let option else {
            throw LocalModelError.unavailable(Self.unsupportedReason(for: nil) ?? "No on-device model is available.")
        }
        try ensureForeground()
        let container = try await loadedContainer()
        try Task.checkCancellation()
        let plan = LocalGenerationPlan(option: option, thinking: thinking && option.supportsThinking)
        let input = try await promptInput(for: option, plan: plan, container: container, makeRequest: makeRequest)
        try Task.checkCancellation()
        try ensureForeground()

        let info = try await container.perform(nonSendable: input) { context, input in
            try await Self.write(plan, input: input, context: context) { continuation.yield($0) }
        }
        if let info {
            logger.info("Prompt \(info.promptTokenCount) tokens at \(info.promptTokensPerSecond, format: .fixed(precision: 0)) tok/s; reply \(info.generationTokenCount) tokens at \(info.tokensPerSecond, format: .fixed(precision: 1)) tok/s")
            if let sample = LocalModelSpeed(measuring: info) {
                measuredSpeeds = LocalModelSpeedStore.record(sample, for: option.id)
            }
        }
        try Task.checkCancellation()
    }

    /// Writes the reply, sending a snapshot after every token. Thinking that
    /// runs past its limit is closed by Orbit, and the model answers from
    /// what it has thought so far, continuing from the same cache instead of
    /// reading the prompt again.
    private nonisolated static func write(
        _ plan: LocalGenerationPlan,
        input: LMInput,
        context: ModelContext,
        emit: @Sendable (AssistantReplySnapshot) -> Void
    ) async throws -> GenerateCompletionInfo? {
        let cache = context.model.newCache(parameters: plan.parameters)
        let started = Date()
        var raw = ""
        var info: GenerateCompletionInfo?
        var thinkingTokens = 0
        var endThinking = false

        let iterator = try TokenIterator(
            input: input,
            model: context.model,
            cache: cache,
            parameters: plan.parameters
        )
        let (events, task) = generateTask(
            promptTokenCount: input.text.tokens.size,
            modelConfiguration: context.configuration,
            tokenizer: context.tokenizer,
            iterator: iterator
        )
        reading: for await event in events {
            switch event {
            case .chunk(let text):
                raw += text
                let snapshot = LocalAssistantPrompt.snapshot(from: raw, thinking: plan.thinking)
                emit(snapshot)
                guard snapshot.isThinking else { continue }
                thinkingTokens += 1
                if thinkingTokens >= LocalModelOption.thinkingTokenLimit
                    || Date().timeIntervalSince(started) >= LocalModelOption.thinkingTimeLimit {
                    endThinking = true
                    break reading
                }
            case .info(let completion):
                info = completion
            case .toolCall:
                break
            }
        }
        // Wait until generation has stopped using the cache.
        task.cancel()
        await task.value
        try Task.checkCancellation()
        guard endThinking else { return info }

        raw += LocalAssistantPrompt.thinkingEnd
        emit(LocalAssistantPrompt.snapshot(from: raw, thinking: true))
        let closing = context.tokenizer.encode(text: plan.closingThought, addSpecialTokens: false)
        let answerIterator = try TokenIterator(
            input: LMInput(tokens: MLXArray(closing)),
            model: context.model,
            cache: cache,
            parameters: plan.answerParameters
        )
        let (answer, answerTask) = generateTask(
            promptTokenCount: closing.count,
            modelConfiguration: context.configuration,
            tokenizer: context.tokenizer,
            iterator: answerIterator
        )
        for await event in answer {
            if case .chunk(let text) = event {
                raw += text
                emit(LocalAssistantPrompt.snapshot(from: raw, thinking: true))
            }
        }
        answerTask.cancel()
        await answerTask.value
        return nil
    }

    /// Measures the templated prompt with the model's own tokenizer and trims
    /// Orbit data until it fits the model's prompt budget.
    private func promptInput(
        for option: LocalModelOption,
        plan: LocalGenerationPlan,
        container: ModelContainer,
        makeRequest: @Sendable (Int) -> LocalAssistantPrompt.Request
    ) async throws -> sending LMInput {
        // Everything but Orbit data first, to learn how much room is left.
        let baseline = try await container.prepare(
            input: Self.input(for: makeRequest(0), thinking: plan.thinking)
        )
        let spareTokens = option.promptTokenBudget - baseline.text.tokens.size
        guard spareTokens > 0 else { return baseline }

        // Orbit's dense data lines average a little over three characters per
        // token. Measure the real prompt and shrink until it fits.
        var dataBudget = Int(Double(spareTokens) * 3.2)
        for _ in 0..<3 {
            let input = try await container.prepare(
                input: Self.input(for: makeRequest(dataBudget), thinking: plan.thinking)
            )
            let overflow = input.text.tokens.size - option.promptTokenBudget
            if overflow <= 0 { return input }
            dataBudget -= overflow * 4 + 100
            guard dataBudget > 0 else { break }
        }
        return baseline
    }

    private func loadedContainer() async throws -> ModelContainer {
        guard let option else { throw LocalModelError.notDownloaded }
        if let container, loadedOptionID == option.id { return container }
        if let loadTask { return try await loadTask.value }
        guard LocalModelStorage.isDownloaded(option) else { throw LocalModelError.notDownloaded }
        let availableMemory = Int64(os_proc_available_memory())
        if availableMemory > 0, availableMemory < option.workingSetBytes {
            throw LocalModelError.insufficientMemory
        }

        let epoch = loadEpoch
        let configuration = option.modelConfiguration(
            directory: LocalModelStorage.snapshotDirectory(for: option)
        )
        let started = Date()
        let task = Task.detached(priority: .userInitiated) {
            // MLX keeps freed GPU buffers for reuse; a small cache keeps the
            // app's footprint well inside iOS's per-app memory limit.
            MLX.Memory.cacheLimit = 32 * 1024 * 1024
            return try await LLMModelFactory.shared.loadContainer(
                from: HubModelDownloader(client: LocalModelStorage.client),
                using: TransformersTokenizerLoader(),
                configuration: configuration
            )
        }
        loadTask = task
        isLoading = true
        defer {
            if epoch == loadEpoch {
                loadTask = nil
                isLoading = false
            }
        }

        let loaded = try await task.value
        guard epoch == loadEpoch, self.option?.id == option.id else {
            throw LocalModelError.interrupted
        }
        container = loaded
        loadedOptionID = option.id
        logger.info("Loaded \(option.name, privacy: .public) in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
        return loaded
    }

    private func ensureForeground() throws {
        guard UIApplication.shared.applicationState == .active else {
            throw LocalModelError.appInactive
        }
    }

    // MARK: Helpers

    private static let modelFilePatterns = ["*.safetensors", "*.json", "*.jinja"]

    /// Qwen3's chat template skips the thinking phase unless it's asked for.
    private static func input(
        for request: LocalAssistantPrompt.Request,
        thinking: Bool
    ) -> UserInput {
        let chat = [Chat.Message.system(request.instructions)]
            + request.history.map { turn -> Chat.Message in
                turn.role == .user ? .user(turn.text) : .assistant(turn.text)
            }
            + [Chat.Message.user(request.message)]
        return UserInput(chat: chat, additionalContext: ["enable_thinking": thinking])
    }

    private static func unsupportedReason(for option: LocalModelOption?) -> String? {
        #if targetEnvironment(simulator)
        return "The on-device model runs on a physical iPhone or iPad. The Simulator doesn't provide the Metal GPU features MLX needs."
        #else
        return option == nil ? "This \(DeviceProfile.name) doesn't have enough memory to run an on-device model." : nil
        #endif
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func updateDownload(_ id: UUID, fractionCompleted: Double) {
        guard id == downloadID, let current = activeDownload,
              fractionCompleted >= current.fractionCompleted + 0.01 || fractionCompleted >= 1 else { return }
        activeDownload?.fractionCompleted = min(fractionCompleted, 1)
        refreshAvailability()
    }

    private func finishDownload(_ id: UUID, option: LocalModelOption, result: Result<Void, Error>) {
        if case .success = result {
            LocalModelStorage.markDownloaded(option)
            logger.info("Downloaded \(option.repository, privacy: .public)")
        }
        guard id == downloadID else {
            refreshAvailability()
            return
        }
        downloadTask = nil
        downloadID = nil
        activeDownload = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if case .failure(let error) = result, !Self.isCancellation(error) {
            logger.error("Download failed: \(error.localizedDescription, privacy: .public)")
            downloadError = Self.downloadMessage(for: error)
            downloadErrorOptionID = option.id
        }
        refreshAvailability()
        // Switch to the new model, unless that would cut off a reply.
        if case .success = result, selectWhenDownloaded == option.id {
            selectWhenDownloaded = nil
            if generationTask == nil { select(option) }
        }
    }

    private static func downloadMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "The download stopped because the connection dropped. Reconnect and tap Download to continue."
            case .timedOut:
                return "The download timed out. Check your connection and try again."
            default:
                break
            }
        }
        let nsError = error as NSError
        if (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)) {
            return "This \(DeviceProfile.name) ran out of storage during the download. Free up space and try again."
        }
        return "The model couldn't be downloaded: \(error.localizedDescription)"
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelGeneration() }
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancelGeneration()
                    self?.unload()
                }
            },
            center.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.relieveMemoryPressure() }
            }
        ]
    }

    /// Returns cached GPU buffers, and the model itself when it isn't in use.
    private func relieveMemoryPressure() {
        guard container != nil else { return }
        if generationTask == nil, loadTask == nil {
            unload()
        } else {
            MLX.Memory.clearCache()
        }
    }
}

private extension LocalModelOption {
    /// Every catalog model is Qwen3: stop at its end-of-turn token.
    func modelConfiguration(directory: URL) -> ModelConfiguration {
        ModelConfiguration(directory: directory, extraEOSTokens: ["<|im_end|>"])
    }
}

/// How one reply is generated: with or without thinking first.
struct LocalGenerationPlan: Sendable {
    let thinking: Bool
    /// The whole generation. With thinking it leaves room for the thinking
    /// limit plus a full answer.
    let parameters: GenerateParameters
    /// The answer written after Orbit closes thinking that ran too long.
    let answerParameters: GenerateParameters

    /// What Qwen suggests appending when thinking has to stop early.
    let closingThought =
        "\n\nConsidering the limited time, I have to give the answer based on my thinking directly now.\n</think>\n\n"

    init(option: LocalModelOption, thinking: Bool) {
        self.thinking = thinking
        // Qwen3's recommended sampling for each mode.
        if thinking {
            parameters = GenerateParameters(
                maxTokens: LocalModelOption.thinkingTokenLimit + option.maxResponseTokens,
                temperature: 0.6, topP: 0.95, topK: 20
            )
            answerParameters = GenerateParameters(
                maxTokens: option.maxResponseTokens,
                temperature: 0.6, topP: 0.95, topK: 20
            )
        } else {
            parameters = GenerateParameters(
                maxTokens: option.maxResponseTokens,
                temperature: 0.7, topP: 0.8, topK: 20
            )
            answerParameters = parameters
        }
    }
}

// MARK: - Hugging Face adapters

/// Downloads a pinned model snapshot with the Hugging Face Hub client.
private struct HubModelDownloader: MLXLMCommon.Downloader {
    let client: HubClient

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repo = HuggingFace.Repo.ID(rawValue: id) else {
            throw LocalModelError.unavailable("\(id) isn't a valid Hugging Face model.")
        }
        return try await client.downloadSnapshot(
            of: repo,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in progressHandler(progress) }
        )
    }
}

private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TransformersTokenizer(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

/// Adapts a swift-transformers tokenizer to the protocol MLX models use.
private struct TransformersTokenizer: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

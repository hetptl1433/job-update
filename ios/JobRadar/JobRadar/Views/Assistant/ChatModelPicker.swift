import Combine
import SwiftUI

// MARK: - Screens

/// Where Orbit Chat runs, which model answers, and how long it thinks.
struct ChatModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ChatModelPickerContent()
                    .chatPickerPageLayout()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }
}

/// The same choices as a page in Settings.
struct ChatModelSettingsView: View {
    var body: some View {
        ScrollView {
            ChatModelPickerContent()
                .chatPickerPageLayout()
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Orbit Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ChatModelPickerContent: View {
    @EnvironmentObject private var app: AppState
    @State private var showConnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            ChatEngineSwitcher(
                engine: $app.assistantEngine,
                openAIConnected: app.connections.aiConnected
            )
            switch app.assistantEngine {
            case .onDevice:
                OnDeviceModelSection(model: app.localModel)
            case .openAI:
                OpenAIModelSection(isConnected: app.connections.aiConnected) {
                    showConnect = true
                }
            }
        }
        .sheet(isPresented: $showConnect) {
            ConnectChatGPTView().environmentObject(app)
        }
    }
}

// MARK: - Engine

private struct ChatEngineSwitcher: View {
    @Binding var engine: AssistantEngine
    let openAIConnected: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            option(
                .onDevice,
                title: "On device",
                subtitle: "Private · works offline",
                symbol: DeviceProfile.isPad ? "ipad" : "iphone"
            )
            option(
                .openAI,
                title: "OpenAI",
                subtitle: openAIConnected ? "Most capable" : "Needs your API key",
                symbol: "cloud"
            )
        }
    }

    private func option(
        _ value: AssistantEngine,
        title: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        let isSelected = engine == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { engine = value }
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? AppTheme.coral : AppTheme.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(
                            isSelected ? AppTheme.accent.opacity(0.14) : AppTheme.elevatedSurface,
                            in: Circle()
                        )
                    Spacer(minLength: 0)
                    SelectionMark(isSelected: isSelected)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pickerCard(isSelected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - On device

private struct OnDeviceModelSection: View {
    @ObservedObject var model: LocalModelManager
    @AppStorage(ChatPreferences.onDeviceThinkingKey) private var thinking: ChatThinkingMode = .instant

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            DevicePowerCard(model: model)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Models").sectionLabel()
                LocalModelList(model: model)
            }
            if let option = model.option, isSupported {
                ThinkingModeSection(
                    modes: ChatThinkingMode.onDeviceModes,
                    selection: $thinking,
                    unavailableNote: option.supportsThinking ? nil : Self.noThinkingNote(for: option)
                ) { mode in
                    detail(for: mode, option: option)
                }
            }
            PickerFootnote(
                "On-device models run on this \(DeviceProfile.name)'s own chip. Your questions and Orbit data never leave it, and chat keeps working offline. Live voice still uses OpenAI."
            )
        }
    }

    private var isSupported: Bool {
        if case .unsupported = model.availability { return false }
        return true
    }

    private func detail(for mode: ChatThinkingMode, option: LocalModelOption) -> String {
        guard mode == .thinking else { return "Answers right away." }
        let seconds = Int(option.maxThinkingSeconds(speed: model.speed(of: option)).rounded())
        return "Works through the question before answering, which helps with plans, comparisons and questions with several steps. Adds up to about \(seconds) seconds on this \(DeviceProfile.name)."
    }

    private static func noThinkingNote(for option: LocalModelOption) -> String {
        let thinkers = LocalModelOption.available().filter(\.supportsThinking).map(\.name)
        guard !thinkers.isEmpty else { return "\(option.name) always answers directly." }
        let names = ListFormatter.localizedString(byJoining: thinkers)
        return "\(option.name) always answers directly. \(names) can think first."
    }
}

/// This device's chip and the memory iOS gives Orbit for a model.
struct DevicePowerCard: View {
    @ObservedObject var model: LocalModelManager
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: DeviceProfile.isPad ? "ipad" : "iphone")
                    .font(.title3)
                    .foregroundStyle(AppTheme.coral)
                    .frame(width: 42, height: 42)
                    .background(
                        AppTheme.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This \(DeviceProfile.name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text(Self.hardwareSummary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            if case .unsupported(let reason) = model.availability {
                notice(reason, symbol: "exclamationmark.triangle")
            } else if let limit = DeviceProfile.appMemoryLimit {
                MemoryBudgetBar(option: model.option, limit: limit)
            }
            if isLowPower {
                notice("Low Power Mode is on, so on-device answers are slower.", symbol: "battery.25")
            }
            if thermalState == .serious || thermalState == .critical {
                notice(
                    "This \(DeviceProfile.name) is warm, so it's slowing down on-device answers.",
                    symbol: "thermometer.high"
                )
            }
        }
        .pickerCard()
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: RunLoop.main)
        ) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
    }

    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(AppTheme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// For example "A15/A16-class chip · 6 GB memory".
    private static var hardwareSummary: String {
        // iOS reports a little less memory than the device has installed.
        let gigabytes = Int((Double(DeviceProfile.physicalMemory) / 1_073_741_824).rounded(.up))
        let memory = "\(gigabytes) GB memory"
        guard let chip = DeviceProfile.performance.chipClass else { return memory }
        return "\(chip)-class chip · \(memory)"
    }
}

private struct MemoryBudgetBar: View {
    let option: LocalModelOption?
    let limit: UInt64

    var body: some View {
        let needed = option.map { UInt64($0.workingSetBytes) + LocalModelOption.appMemoryReserve } ?? 0
        let fraction = min(Double(needed) / Double(max(limit, 1)), 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Memory for Orbit")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .memory))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.elevatedSurface)
                    Capsule()
                        .fill(fraction < 0.8 ? AppTheme.success : AppTheme.warning)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            if let option {
                Text("\(option.name) uses about \(option.memoryText) of it while answering.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every on-device model this device can run, with its download and speed.
struct LocalModelList: View {
    @ObservedObject var model: LocalModelManager

    var body: some View {
        let available = LocalModelOption.available()
        let recommendedID = LocalModelOption.recommended(measured: model.measuredSpeeds)?.id
        let tooLarge = LocalModelOption.catalog.filter { !available.contains($0) }
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ForEach(available) { option in
                LocalModelRow(option: option, model: model, isRecommended: option.id == recommendedID)
            }
            if !tooLarge.isEmpty {
                Label(Self.tooLargeNote(tooLarge), systemImage: "memorychip")
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppTheme.Spacing.xs)
            }
        }
    }

    private static func tooLargeNote(_ options: [LocalModelOption]) -> String {
        let names = ListFormatter.localizedString(byJoining: options.map(\.name))
        let verb = options.count == 1 ? "needs" : "need"
        return "\(names) \(verb) more memory than this \(DeviceProfile.name) gives Orbit."
    }
}

private struct LocalModelRow: View {
    let option: LocalModelOption
    @ObservedObject var model: LocalModelManager
    let isRecommended: Bool
    @State private var confirmDelete = false

    private var state: LocalModelManager.Availability { model.state(of: option) }
    private var isSelected: Bool { model.option?.id == option.id }
    private var isInUse: Bool { isSelected && state == .downloaded }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if state == .downloaded {
                Button { model.select(option) } label: { summary }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isInUse ? .isSelected : [])
            } else {
                summary
            }
            actions
                .padding(.leading, SelectionMark.width + AppTheme.Spacing.md)
        }
        .pickerCard(isSelected: isInUse)
        .confirmationDialog(
            "Delete \(option.name)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete and Free \(option.downloadSizeText)", role: .destructive) {
                model.delete(option)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        guard isSelected else { return "You can download it again anytime." }
        if let replacement = model.replacement(forDeleting: option) {
            return "Chat switches to \(replacement.name), which is already downloaded."
        }
        return "On-device chat needs a download before it can answer again."
    }

    private var summary: some View {
        let speed = model.speed(of: option)
        let rating = LocalModelSpeed.rating(answerSeconds: option.typicalAnswerSeconds(speed: speed))
        return HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            SelectionMark(isSelected: isInUse)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(option.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    if isRecommended { RecommendedBadge() }
                }
                Text(option.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TagFlow {
                    FactTag(symbol: "speedometer", text: rating.title, tint: rating.tint)
                    FactTag(symbol: "arrow.down.circle", text: option.downloadSizeText)
                    if option.supportsThinking {
                        FactTag(symbol: "brain", text: "Can think")
                    }
                }
                Text(Self.speedSummary(speed, option: option))
                    .font(.caption)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .unsupported:
                EmptyView()
            case .notDownloaded:
                Button { model.download(option) } label: {
                    Label("Download · \(option.downloadSizeText)", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(ChatPickerButtonStyle(prominent: isRecommended))
                .disabled(model.activeDownload != nil)
                if model.activeDownload != nil {
                    Text("Available when the current download finishes.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            case .downloading(let fraction):
                HStack {
                    Text(verbatim: "Downloading · \(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Button("Cancel", action: model.cancelDownload)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .tint(AppTheme.coral)
                }
                ProgressView(value: fraction)
                    .tint(AppTheme.coral)
                Text(downloadingNote)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .downloaded:
                HStack(spacing: AppTheme.Spacing.sm) {
                    if isSelected {
                        Label("In use · works offline", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.success)
                    } else {
                        Label("Downloaded · tap to use", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Menu {
                        Button("Delete Download", systemImage: "trash", role: .destructive) {
                            confirmDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 36, height: 28)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More options for \(option.name)")
                }
            }
            if model.downloadErrorOptionID == option.id, let error = model.downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var downloadingNote: String {
        model.isReady && !isSelected
            ? "Keep Orbit open. Chat switches to \(option.name) when it's ready."
            : "Keep Orbit open until the download finishes."
    }

    /// For example "First words in about 5 s, then about 21 words a second ·
    /// estimated for this iPhone".
    private static func speedSummary(_ speed: LocalModelSpeed, option: LocalModelOption) -> String {
        let wait = max(Int(speed.secondsToRead(promptTokens: option.promptTokenBudget).rounded()), 1)
        // English runs about three quarters of a word per token.
        let words = max(Int((speed.replyTokensPerSecond * 0.75).rounded()), 1)
        let source = speed.isMeasured ? "measured" : "estimated"
        return "First words in about \(wait) s, then about \(words) words a second · \(source) for this \(DeviceProfile.name)"
    }
}

private extension LocalModelSpeed.Rating {
    var tint: Color {
        switch self {
        case .veryFast, .fast: AppTheme.success
        case .moderate: AppTheme.warning
        case .slow: AppTheme.destructive
        }
    }
}

// MARK: - OpenAI

private struct OpenAIModelSection: View {
    let isConnected: Bool
    let onConnect: () -> Void
    @AppStorage(AppConfig.openAIChatModelPreferenceKey) private var chatModelID = ""
    @AppStorage(ChatPreferences.openAIThinkingKey) private var thinking: ChatThinkingMode = .balanced

    var body: some View {
        let selectedID = effectiveChatModelID(chatModelID)
        let selected = AppConfig.chatModelChoice(for: selectedID)
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            if !isConnected {
                ConnectOpenAICard(action: onConnect)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Models").sectionLabel()
                ForEach(AppConfig.chatModelChoices(including: selectedID)) { choice in
                    CloudModelRow(choice: choice, isSelected: choice.id == selectedID) {
                        chatModelID = choice.id
                    }
                }
            }
            ThinkingModeSection(
                modes: ChatThinkingMode.allCases,
                selection: $thinking,
                unavailableNote: OpenAIClient.reasoningEfforts(forModel: selectedID).isEmpty
                    ? "\(selected.name) answers directly, without reasoning. Choose a GPT-5.6 or GPT-6 model to set how long it thinks."
                    : nil,
                detail: \.openAIDetail
            )
            PickerFootnote(
                "Your question and the Orbit data needed to answer it are sent to OpenAI with your API key. Charges depend on your OpenAI project."
            )
        }
    }
}

private struct CloudModelRow: View {
    let choice: AIModelChoice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let reasons = !OpenAIClient.reasoningEfforts(forModel: choice.id).isEmpty
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                SelectionMark(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(choice.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        if choice.isRecommended { RecommendedBadge() }
                    }
                    Text(choice.detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    TagFlow {
                        if let cost = choice.cost.title {
                            FactTag(symbol: "dollarsign.circle", text: cost)
                        }
                        FactTag(
                            symbol: reasons ? "brain" : "bolt",
                            text: reasons ? "Reasons" : "No reasoning"
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .pickerCard(isSelected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ConnectOpenAICard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Connect OpenAI", systemImage: "key.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text("Add your OpenAI API key to chat with these models. It's kept in this \(DeviceProfile.name)'s Keychain.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect OpenAI", action: action)
                .buttonStyle(ChatPickerButtonStyle(prominent: true))
        }
        .pickerCard()
    }
}

// MARK: - Thinking

private struct ThinkingModeSection: View {
    let modes: [ChatThinkingMode]
    @Binding var selection: ChatThinkingMode
    /// Shown instead of the modes when the selected model can't think.
    let unavailableNote: String?
    let detail: (ChatThinkingMode) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Thinking").sectionLabel()
            if let unavailableNote {
                Label(unavailableNote, systemImage: "bolt")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .pickerCard()
            } else {
                ThinkingModeControl(modes: modes, selection: $selection)
                Text(detail(ThinkingModeControl.active(selection, in: modes)))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ThinkingModeControl: View {
    let modes: [ChatThinkingMode]
    @Binding var selection: ChatThinkingMode
    @Namespace private var highlight

    /// A saved mode the current engine doesn't offer shows as its first mode.
    static func active(_ selection: ChatThinkingMode, in modes: [ChatThinkingMode]) -> ChatThinkingMode {
        modes.contains(selection) ? selection : modes[0]
    }

    var body: some View {
        let active = Self.active(selection, in: modes)
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(modes) { mode in
                let isActive = mode == active
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = mode }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.systemImage)
                            .font(.subheadline.weight(.semibold))
                        Text(mode.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isActive ? AppTheme.primaryText : AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                .fill(AppTheme.elevatedSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                                        .strokeBorder(AppTheme.accent.opacity(0.6), lineWidth: 1)
                                )
                                .matchedGeometryEffect(id: "active", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(AppTheme.Spacing.xs)
        .background(
            AppTheme.primarySurface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.separator, lineWidth: 1)
        )
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Composer controls

/// The composer's model button: which model answers, and where.
struct ChatModelChip: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var localModel: LocalModelManager
    @AppStorage(AppConfig.openAIChatModelPreferenceKey) private var chatModelID = ""
    let action: () -> Void

    var body: some View {
        let name = modelName
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: app.assistantEngine.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(app.assistantEngine == .onDevice ? AppTheme.success : AppTheme.info)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .foregroundStyle(AppTheme.primaryText)
            .chipSurface(isActive: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model, \(name)")
        .accessibilityHint("Choose the model and how long it thinks")
    }

    private var modelName: String {
        switch app.assistantEngine {
        case .onDevice: localModel.option?.name ?? "On device"
        case .openAI: AppConfig.chatModelChoice(for: effectiveChatModelID(chatModelID)).name
        }
    }
}

/// The composer's thinking control: a switch for on-device models and a
/// menu of modes for OpenAI models. Hidden for models that can't think.
struct ChatThinkingChip: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var localModel: LocalModelManager
    @AppStorage(AppConfig.openAIChatModelPreferenceKey) private var chatModelID = ""
    @AppStorage(ChatPreferences.openAIThinkingKey) private var openAIThinking: ChatThinkingMode = .balanced
    @AppStorage(ChatPreferences.onDeviceThinkingKey) private var onDeviceThinking: ChatThinkingMode = .instant
    let showOptions: () -> Void

    var body: some View {
        switch app.assistantEngine {
        case .onDevice:
            if localModel.option?.supportsThinking == true {
                let isOn = onDeviceThinking == .thinking
                Button {
                    onDeviceThinking = isOn ? .instant : .thinking
                } label: {
                    chipLabel(symbol: "brain", title: "Think", isActive: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Think before answering")
                .accessibilityValue(isOn ? "On" : "Off")
                .sensoryFeedback(.selection, trigger: isOn)
            }
        case .openAI:
            if !OpenAIClient.reasoningEfforts(forModel: effectiveChatModelID(chatModelID)).isEmpty {
                Menu {
                    Picker("Thinking", selection: $openAIThinking) {
                        ForEach(ChatThinkingMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    Divider()
                    Button("About Thinking Modes", systemImage: "info.circle", action: showOptions)
                } label: {
                    chipLabel(
                        symbol: openAIThinking.systemImage,
                        title: openAIThinking.title,
                        isActive: openAIThinking == .thinking || openAIThinking == .deep
                    )
                }
                .accessibilityLabel("Thinking, \(openAIThinking.title)")
            }
        }
    }

    private func chipLabel(symbol: String, title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? AppTheme.coral : AppTheme.secondaryText)
        .chipSurface(isActive: isActive)
    }
}

/// Settings' one-line summary of the chat model.
struct ChatModelSummary: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var localModel: LocalModelManager
    @AppStorage(AppConfig.openAIChatModelPreferenceKey) private var chatModelID = ""

    var body: some View {
        switch app.assistantEngine {
        case .onDevice:
            Text(localModel.option.map { "\($0.name) · on device" } ?? "On device")
        case .openAI:
            Text(AppConfig.chatModelChoice(for: effectiveChatModelID(chatModelID)).name)
        }
    }
}

/// Views read the chat model through `@AppStorage` so they update when it
/// changes. Empty means chat still follows the email scanning model.
private func effectiveChatModelID(_ stored: String) -> String {
    stored.isEmpty ? AppConfig.selectedOpenAIModel() : stored
}

// MARK: - Building blocks

private struct SelectionMark: View {
    static let width: CGFloat = 22
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.tertiaryText)
            .frame(width: Self.width)
            .accessibilityHidden(true)
    }
}

private struct RecommendedBadge: View {
    var body: some View {
        Text("Recommended")
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.coral)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.accent.opacity(0.14), in: Capsule())
    }
}

private struct FactTag: View {
    let symbol: String
    let text: String
    var tint: Color = AppTheme.secondaryText

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(AppTheme.secondarySurface, in: Capsule())
    }
}

private struct PickerFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ChatPickerButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? AppTheme.onBrand : AppTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(prominent ? AppTheme.primaryButton : AppTheme.secondarySurface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    prominent ? Color.white.opacity(0.16) : AppTheme.border,
                    lineWidth: 1
                )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Lays tags out in rows, wrapping when a row is full.
private struct TagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            width = max(width, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension View {
    func pickerCard(isSelected: Bool = false) -> some View {
        self
            .padding(AppTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.primarySurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.accent : AppTheme.separator,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
    }

    func chipSurface(isActive: Bool) -> some View {
        self
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(isActive ? AppTheme.accent.opacity(0.14) : AppTheme.secondarySurface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isActive ? AppTheme.accent.opacity(0.5) : AppTheme.border,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
    }

    func chatPickerPageLayout() -> some View {
        self
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
    }
}

#Preview("Model picker") {
    let app = PreviewSupport.appState()
    return ChatModelPickerSheet()
        .environmentObject(app)
}

import SwiftUI

/// A neutral informational state (empty / disconnected / permission / error).
/// Every integration uses one of these rather than rendering a silent blank.
struct InfoStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, AppTheme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxl)
        .padding(.horizontal, AppTheme.Spacing.lg)
    }
}

/// Inline loading indicator.
struct LoadingStateView: View {
    var message: String = "Loading…"
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xxl)
    }
}

/// A section title with an optional trailing action (e.g. "View Inbox →").
struct SectionHeader: View {
    var title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

/// A small importance indicator. Uses a filled/hollow dot rather than loud color.
struct ImportanceDot: View {
    var importance: AttentionImportance
    var body: some View {
        Circle()
            .fill(importance == .high ? AppTheme.coral : AppTheme.tertiaryText)
            .frame(width: 6, height: 6)
            .opacity(importance == .low ? 0.5 : 1)
    }
}

/// Restrained pill/tag used for statuses and labels.
struct Tag: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = AppTheme.secondaryText

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(tint.opacity(0.23), lineWidth: 1)
        )
    }
}

// MARK: - Refined Orbit design language

/// App identity in the navigation bar; native safe areas provide the device chrome.
struct OrbitWordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            OrbitMark(size: 27)
            Text("orbit")
                .font(.title2.weight(.bold))
                .tracking(-1)
                .foregroundStyle(AppTheme.primaryText)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orbit")
    }
}

struct OrbitMark: View {
    var size: CGFloat = 30
    var tint: Color = AppTheme.coral

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(tint, lineWidth: max(1.4, size * 0.05))
                .frame(width: size * 0.86, height: size * 0.36)
                .rotationEffect(.degrees(-35))
            Circle().fill(tint).frame(width: size * 0.2, height: size * 0.2)
            Circle().fill(tint).frame(width: size * 0.13, height: size * 0.13)
                .offset(x: size * 0.32, y: -size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct OrbitPageHeading: View {
    var title: String
    var subtitle: String
    var actionTitle: String? = nil
    var symbol: String = "plus"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .tracking(-1)
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                OrbitIconButton(title: actionTitle, symbol: symbol, action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OrbitIconButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 44, height: 44)
                .background(AppTheme.secondarySurface, in: Circle())
                .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct OrbitAvatar: View {
    var name: String
    var size: CGFloat = 36

    private var initials: String {
        let value = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "O" : value.uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(hex: 0x342E30), AppTheme.secondarySurface], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(AppTheme.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

private struct OrbitNavigationChrome: ViewModifier {
    @EnvironmentObject private var app: AppState
    @Environment(\.orbitOpenSettings) private var openSettings
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { OrbitWordmark() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let openSettings { openSettings() } else { showSettings = true }
                    } label: {
                        OrbitAvatar(name: app.user?.fullName ?? "Orbit")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile and settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

extension View {
    func orbitNavigationChrome() -> some View { modifier(OrbitNavigationChrome()) }
}

struct OrbitAssistantCard: View {
    var title: String = "A little help from Orbit"
    var prompt: String
    var onChat: () -> Void
    var onVoice: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button(action: onChat) {
                HStack(spacing: AppTheme.Spacing.md) {
                    OrbitMark(size: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.primaryText)
                        Text(prompt).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onVoice) {
                Image(systemName: "waveform")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.coral)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start live voice")
        }
        .orbitFocusSurface(padding: AppTheme.Spacing.lg)
    }
}

struct OrbitSummaryTile: View {
    var title: String
    var symbol: String
    var value: String
    var detail: String
    var tint: Color = AppTheme.coral
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Capsule().fill(tint.opacity(0.6)).frame(width: 24, height: 3)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Date {
    /// Compact relative label, e.g. "12 min ago", "in 2 hr".
    var relativeShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}

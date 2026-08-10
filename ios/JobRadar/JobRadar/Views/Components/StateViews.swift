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
            Text(title).sectionLabel()
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
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
        .background(tint.opacity(0.08), in: Capsule())
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
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

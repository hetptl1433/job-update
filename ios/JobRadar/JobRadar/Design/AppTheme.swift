import SwiftUI

// MARK: - Color utilities

extension Color {
    /// Build a color from a 24-bit hex value (e.g. 0x0A0A0B).
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Build a color that resolves differently in light vs. dark mode.
    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { trait in
            let value = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Design tokens

/// Centralized design tokens for the whole app. Views must reference these
/// rather than hard-coding colors so the visual language stays consistent.
///
/// Orbit intentionally uses the same black canvas in every system appearance.
/// Red is reserved for brand moments and primary interaction; semantic colors
/// remain distinct so important status information is never ambiguous.
enum AppTheme {
    // Surfaces & text
    static let background = Color(hex: 0x070708)
    static let primarySurface = Color(hex: 0x111114)
    static let secondarySurface = Color(hex: 0x1A1A1F)
    static let elevatedSurface = Color(hex: 0x222228)
    static let primaryText = Color(hex: 0xF8F8FA)
    static let secondaryText = Color(hex: 0xB2B2BC)
    static let tertiaryText = Color(hex: 0x7E7E89)
    static let border = Color(hex: 0x303037)
    static let separator = Color(hex: 0x242429)

    /// Purposeful signal red used for primary actions, selection, and focus.
    static let accent = Color(hex: 0xF3263E)
    /// Foreground color to place on top of `accent`.
    static let onAccent = Color(hex: 0xFFFFFF)

    static let brand = accent
    static let brandSecondary = Color(hex: 0xB81029)
    /// Deeper brand endpoint keeps white button labels legible.
    static let primaryButton = Color(hex: 0xD4142C)
    static let coral = Color(hex: 0xFF6675)
    static let onBrand = onAccent
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFF354B), Color(hex: 0xD4142C)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Semantic (restrained, used only where meaning requires it)
    static let destructive = Color(hex: 0xFF5264)
    static let success = Color(hex: 0x55D98B)
    static let warning = Color(hex: 0xFFC15C)
    static let info = Color(hex: 0x6DAEFF)
    static let purple = Color(hex: 0xC69BFF)

    // Spacing scale
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let page: CGFloat = 22
    }

    // Refined corner radii: soft enough to feel polished, never bubbly.
    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 22
    }

    enum Shadow {
        static let cardColor = Color.black.opacity(0.12)
        static let cardRadius: CGFloat = 6
        static let cardY: CGFloat = 3
        static let buttonColor = brand.opacity(0.28)
    }
}

// MARK: - Reusable styling

extension View {
    /// Quiet grouped surface shared by the refined screens and their details.
    func cardSurface(padding: CGFloat = AppTheme.Spacing.lg,
                     radius: CGFloat = AppTheme.Radius.lg) -> some View {
        self
            .padding(padding)
            .background(AppTheme.primarySurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AppTheme.separator, lineWidth: 1)
            )
            .shadow(
                color: AppTheme.Shadow.cardColor,
                radius: AppTheme.Shadow.cardRadius,
                x: 0,
                y: AppTheme.Shadow.cardY
            )
    }

    func orbitFocusSurface(padding: CGFloat = AppTheme.Spacing.xl) -> some View {
        self
            .padding(padding)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x1B1417), AppTheme.primarySurface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(AppTheme.coral.opacity(0.18), lineWidth: 1)
            }
    }

    /// For a row inside `cardSurface(padding: 0)`: gives its touch-and-hold
    /// preview the card's fill and corners. In place it looks unchanged, since
    /// the card behind it is the same color and shape.
    func cardRowPreviewSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
        return self
            .background(AppTheme.primarySurface, in: shape)
            .contentShape(.contextMenuPreview, shape)
    }

    /// Fades a screen section in and lifts it into place the first time it
    /// appears, `order` steps after the first so sections arrive in sequence.
    /// Reduce Motion shows sections immediately.
    func orbitAppear(_ order: Int) -> some View {
        modifier(OrbitAppearModifier(order: order))
    }

    /// Small uppercase section label used above grouped content.
    func sectionLabel() -> some View {
        self
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(AppTheme.tertiaryText)
            .textCase(.uppercase)
    }
}

private struct OrbitAppearModifier: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .onAppear {
                guard !isVisible else { return }
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86).delay(Double(min(order, 8)) * 0.04)) {
                    isVisible = true
                }
            }
    }
}

/// Brand-colored primary button used for main actions.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.onBrand)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(AppTheme.primaryButton, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(
                color: configuration.isPressed ? .clear : AppTheme.Shadow.buttonColor,
                radius: configuration.isPressed ? 2 : 5,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Gives a tappable card a soft press: it settles slightly and dims, then
/// springs back. Reduce Motion keeps only the dimming.
struct OrbitPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

/// Secondary bordered button.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                configuration.isPressed ? AppTheme.elevatedSurface : AppTheme.secondarySurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

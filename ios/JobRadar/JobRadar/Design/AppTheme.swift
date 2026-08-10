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
/// rather than hard-coding colors, so the visual language stays consistent and
/// light/dark are handled in one place.
///
/// Neutral surfaces and monochrome emphasis create the app's industrial,
/// premium visual language. Color is reserved for semantic meaning.
enum AppTheme {
    // Surfaces & text
    static let background = Color(light: 0xFFFFFF, dark: 0x0A0A0B)
    static let primarySurface = Color(light: 0xFFFFFF, dark: 0x151517)
    static let secondarySurface = Color(light: 0xF4F4F6, dark: 0x1C1C1F)
    static let primaryText = Color(light: 0x0A0A0B, dark: 0xF4F4F6)
    static let secondaryText = Color(light: 0x6C6C72, dark: 0x99999F)
    static let tertiaryText = Color(light: 0x9A9AA0, dark: 0x67676D)
    static let border = Color(light: 0xE5E5E9, dark: 0x2B2B2F)
    static let separator = Color(light: 0xEDEDF0, dark: 0x232326)

    /// Accent is black in light mode, white in dark mode. Used for primary
    /// buttons and emphasis — never green.
    static let accent = Color(light: 0x0A0A0B, dark: 0xF4F4F6)
    /// Foreground color to place on top of `accent`.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0A0A0B)

    static let brand = accent
    static let brandSecondary = Color(light: 0x3A3A3D, dark: 0xC8C8CC)
    static let coral = Color(light: 0xE6545F, dark: 0xFF7B7F)
    static let onBrand = onAccent
    static let brandGradient = LinearGradient(
        colors: [brand, brand],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Semantic (restrained, used only where meaning requires it)
    static let destructive = Color(light: 0xC5303A, dark: 0xFF6B6B)
    static let success = Color(light: 0x2E7D46, dark: 0x54C27A)
    static let warning = Color(light: 0xB26A00, dark: 0xE0A64B)
    static let info = Color(light: 0x2F6FB3, dark: 0x6FB0F0)
    static let purple = Color(light: 0x6D4AB6, dark: 0xB49BF0)

    // Spacing scale
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // Restrained corner radii — no giant bubble cards
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }
}

// MARK: - Reusable styling

extension View {
    /// A restrained surface card: thin border, subtle fill, modest radius.
    func cardSurface(padding: CGFloat = AppTheme.Spacing.lg,
                     radius: CGFloat = AppTheme.Radius.md) -> some View {
        self
            .padding(padding)
            .background(AppTheme.primarySurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
    }

    /// Small uppercase section label used above grouped content.
    func sectionLabel() -> some View {
        self
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(AppTheme.secondaryText)
            .textCase(.uppercase)
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
            .background(AppTheme.brandGradient, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
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
            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

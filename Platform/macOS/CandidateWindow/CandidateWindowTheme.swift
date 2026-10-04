import AppKit

struct CandidateAccessibilityEnvironment: Equatable, Sendable {
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let reduceMotion: Bool

    static var current: CandidateAccessibilityEnvironment {
        let workspace = NSWorkspace.shared
        return CandidateAccessibilityEnvironment(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion
        )
    }
}

struct CandidateWindowTheme: Equatable, Sendable {
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let candidateHeight: CGFloat
    let candidateSpacing: CGFloat
    let candidateHorizontalPadding: CGFloat
    let minimumCandidateWidth: CGFloat
    let maximumCandidateWidth: CGFloat
    let minimumPanelWidth: CGFloat
    let maximumPanelWidth: CGFloat
    let maximumVerticalPanelWidth: CGFloat
    let pageIndicatorWidth: CGFloat
    let primaryFontSize: CGFloat
    let commentFontSize: CGFloat
    let shortcutFontSize: CGFloat
    let animationDuration: TimeInterval

    /// Width reserved for the index digit and the gap that follows it.
    static let shortcutWidth: CGFloat = 10
    static let shortcutGap: CGFloat = 5
    static let commentGap: CGFloat = 6
    static let highlightCornerRadius: CGFloat = 5

    static func system(
        environment: CandidateAccessibilityEnvironment
    ) -> CandidateWindowTheme {
        CandidateWindowTheme(
            reduceTransparency: environment.reduceTransparency,
            increaseContrast: environment.increaseContrast,
            cornerRadius: environment.increaseContrast ? 6 : 8,
            horizontalPadding: 4,
            verticalPadding: 4,
            candidateHeight: 30,
            candidateSpacing: 2,
            candidateHorizontalPadding: 8,
            minimumCandidateWidth: 52,
            maximumCandidateWidth: 220,
            minimumPanelWidth: 160,
            maximumPanelWidth: 760,
            maximumVerticalPanelWidth: 420,
            pageIndicatorWidth: 64,
            primaryFontSize: 16,
            commentFontSize: 12,
            shortcutFontSize: 12,
            animationDuration: environment.reduceMotion ? 0 : 0.08
        )
    }

    var contentChromeWidth: CGFloat {
        candidateHorizontalPadding * 2 + Self.shortcutWidth + Self.shortcutGap
    }

    /// The system material only tints the panel; this near-opaque surface keeps
    /// glyph contrast stable over bright or busy content behind the window.
    var panelBackgroundColor: NSColor {
        reduceTransparency ? FengYuPalette.surface : FengYuPalette.surfaceTranslucent
    }

    var panelBorderColor: NSColor {
        increaseContrast ? .separatorColor : FengYuPalette.border
    }

    var panelBorderWidth: CGFloat {
        increaseContrast ? 1.5 : 1
    }

    var highlightColor: NSColor {
        increaseContrast ? FengYuPalette.highlightFillStrong : FengYuPalette.highlightFill
    }
}

/// Brand palette shared by the candidate window and the input mode indicator.
/// Values mirror docs/DESIGN_SYSTEM.md.
enum FengYuPalette {
    nonisolated(unsafe) static let surface = dynamic(light: 0xFAFAF8, dark: 0x252629)
    nonisolated(unsafe) static let surfaceTranslucent = dynamic(light: 0xFAFAF8, dark: 0x252629, alpha: 0.9)
    nonisolated(unsafe) static let border = dynamic(light: 0xDEDED9, dark: 0x3A3C40)
    nonisolated(unsafe) static let textPrimary = dynamic(light: 0x1F2023, dark: 0xECEDEF)
    nonisolated(unsafe) static let textSecondary = dynamic(light: 0x6E7076, dark: 0x9A9DA3)
    nonisolated(unsafe) static let textTertiary = dynamic(light: 0x85878D, dark: 0x7E8187)
    nonisolated(unsafe) static let accent = dynamic(light: 0x2F6B8A, dark: 0x86B6CF)
    nonisolated(unsafe) static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x13232C)
    nonisolated(unsafe) static let highlightFill = dynamic(light: 0xE4EDF1, dark: 0x33434D)
    nonisolated(unsafe) static let highlightFillStrong = dynamic(light: 0xCCDDE6, dark: 0x3F5664)
    nonisolated(unsafe) static let highlightText = dynamic(light: 0x163F55, dark: 0xE3EEF4)

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return color(isDark ? dark : light, alpha: alpha)
        }
    }

    private static func color(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

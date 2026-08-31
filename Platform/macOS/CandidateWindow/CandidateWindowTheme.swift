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
    let reduceMotion: Bool
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
    let pageIndicatorWidth: CGFloat
    let primaryFontSize: CGFloat
    let commentFontSize: CGFloat
    let shortcutFontSize: CGFloat
    let animationDuration: TimeInterval

    static func system(
        environment: CandidateAccessibilityEnvironment
    ) -> CandidateWindowTheme {
        CandidateWindowTheme(
            reduceTransparency: environment.reduceTransparency,
            increaseContrast: environment.increaseContrast,
            reduceMotion: environment.reduceMotion,
            cornerRadius: environment.increaseContrast ? 13 : 15,
            horizontalPadding: 7,
            verticalPadding: 6,
            candidateHeight: 36,
            candidateSpacing: 5,
            candidateHorizontalPadding: 10,
            minimumCandidateWidth: 68,
            maximumCandidateWidth: 220,
            minimumPanelWidth: 220,
            maximumPanelWidth: 760,
            pageIndicatorWidth: 58,
            primaryFontSize: 16,
            commentFontSize: 12,
            shortcutFontSize: 11,
            animationDuration: environment.reduceMotion ? 0 : 0.1
        )
    }

    var panelBackgroundColor: NSColor {
        if reduceTransparency {
            return increaseContrast ? .windowBackgroundColor : .underPageBackgroundColor
        }
        return increaseContrast
            ? NSColor.windowBackgroundColor.withAlphaComponent(0.18)
            : .clear
    }

    var panelBorderColor: NSColor {
        if !reduceTransparency, !increaseContrast {
            return .clear
        }
        return NSColor.separatorColor.withAlphaComponent(increaseContrast ? 0.92 : 0.42)
    }

    var highlightColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(increaseContrast ? 0.26 : 0.16)
    }

    var highlightBorderColor: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(increaseContrast ? 0.9 : 0.42)
    }

    var paginationBackgroundColor: NSColor {
        NSColor.quaternaryLabelColor.withAlphaComponent(increaseContrast ? 0.4 : 0.2)
    }
}

import SwiftUI

extension EnvironmentValues {
    @Entry var menuItemHighlighted: Bool = false
}

enum MenuHighlightStyle {
    static let openAIAccent = Color.white.opacity(0.88)
    static let selectionText = Color.white.opacity(0.98)
    static let normalPrimaryText = Color.white.opacity(0.94)
    static let normalSecondaryText = Color.white.opacity(0.7)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.78) : self.normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.9) : Color.white.opacity(0.78)
    }

    static func progressTrack(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.2) : Color.white.opacity(0.12)
    }

    static func progressTint(_ highlighted: Bool, fallback: Color) -> Color {
        _ = fallback
        let pearl = Color.white
        return highlighted ? pearl.opacity(0.9) : pearl.opacity(0.78)
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.085) : .clear
    }

    static func cardBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color.black.opacity(0.52) : Color.black.opacity(0.46)
    }

    static func cardBorder(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.14) : Color.white.opacity(0.09)
    }

    static func cardShadow(_ highlighted: Bool) -> Color {
        highlighted ? Color.black.opacity(0.46) : Color.black.opacity(0.32)
    }

    static func pillBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.11) : Color.white.opacity(0.07)
    }

    static func subtleDivider(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.13) : Color.white.opacity(0.06)
    }

    static func glassHighlight(_ highlighted: Bool) -> Color {
        highlighted ? Color.white.opacity(0.24) : Color.white.opacity(0.16)
    }

    static func glassLowlight(_ highlighted: Bool) -> Color {
        highlighted ? Color.black.opacity(0.46) : Color.black.opacity(0.34)
    }
}

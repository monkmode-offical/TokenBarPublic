import SwiftUI

/// Static progress fill with no implicit animations, used inside the menu card.
struct UsageProgressBar: View {
    private static let paceMarkerWidth: CGFloat = 1.2

    let percent: Double
    let tint: Color
    let accessibilityLabel: String
    let pacePercent: Double?
    let paceOnTop: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(
        percent: Double,
        tint: Color,
        accessibilityLabel: String,
        pacePercent: Double? = nil,
        paceOnTop: Bool = true)
    {
        self.percent = percent
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.pacePercent = pacePercent
        self.paceOnTop = paceOnTop
    }

    private var clamped: Double {
        min(100, max(0, self.percent))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            let fillWidth = width * self.clamped / 100
            let markerX = width * Self.clampedPercent(self.pacePercent) / 100
            let markerOffset = max(0, min(width - Self.paceMarkerWidth, markerX - (Self.paceMarkerWidth / 2)))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(self.isHighlighted ? 0.2 : 0.14))
                            .frame(height: 0.8)
                    }
                self.actualBar(width: fillWidth)
                if self.pacePercent != nil {
                    self.paceMarker
                        .offset(x: markerOffset)
                }
            }
            .clipped()
        }
        .frame(height: 3)
        .accessibilityLabel(self.accessibilityLabel)
        .accessibilityValue("\(Int(self.clamped)) percent")
    }

    private func actualBar(width: CGFloat) -> some View {
        let tint = MenuHighlightStyle.progressTint(self.isHighlighted, fallback: self.tint)
        return Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(self.isHighlighted ? 0.88 : 0.8),
                        tint.opacity(self.isHighlighted ? 0.72 : 0.64),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing))
            .frame(width: width)
            .animation(.spring(response: 0.24, dampingFraction: 0.92), value: width)
            .contentShape(Rectangle())
            .allowsHitTesting(false)
    }

    private var paceMarker: some View {
        Capsule()
            .fill(self.paceMarkerColor)
            .frame(width: Self.paceMarkerWidth)
            .contentShape(Rectangle())
            .allowsHitTesting(false)
    }

    private var paceMarkerColor: Color {
        if self.isHighlighted {
            return .white.opacity(0.95)
        }
        return self.paceOnTop ? Color.white.opacity(0.76) : Color.white.opacity(0.6)
    }

    private static func clampedPercent(_ value: Double?) -> Double {
        guard let value else { return 0 }
        return min(100, max(0, value))
    }
}

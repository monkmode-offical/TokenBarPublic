import AppKit
import SwiftUI
import TokenBarCore

/// SwiftUI card used inside the NSMenu to mirror Apple's rich menu panels.
struct UsageMenuCardView: View {
    fileprivate static let maxVisibleMetrics = 2

    struct Model {
        enum PercentStyle: String, Sendable {
            case left
            case used

            var labelSuffix: String {
                switch self {
                case .left: "remaining"
                case .used: "used"
                }
            }

            var accessibilityLabel: String {
                switch self {
                case .left: "Usage remaining"
                case .used: "Usage used"
                }
            }
        }

        struct Metric: Identifiable {
            let id: String
            let title: String
            let windowLabel: String?
            let windowMinutes: Int?
            let percent: Double
            let percentStyle: PercentStyle
            let resetText: String?
            let detailText: String?
            let detailLeftText: String?
            let detailRightText: String?
            let pacePercent: Double?
            let paceOnTop: Bool

            var percentLabel: String {
                String(format: "%@ %.0f%%", self.percentStyle == .left ? "Remaining" : "Used", self.percent)
            }
        }

        enum SubtitleStyle {
            case info
            case loading
            case error
        }

        struct TokenUsageSection: Sendable {
            let title: String
            let sessionLine: String
            let monthLine: String
            let planSpendLine: String?
            let todayEconomicsLine: String?
            let weekEconomicsLine: String?
            let monthEconomicsLine: String?
            let averageLine: String?
            let coverageLine: String?
            let effectiveRateLine: String?
            let modelSpendLine: String?
            let allTimeLine: String?
            let spendComparison: SpendComparison?
            let hintLine: String?
            let errorLine: String?
            let errorCopyText: String?
        }

        struct SpendComparison: Sendable {
            let title: String
            let paidUSD: Double
            let valueUSD: Double
        }

        struct ProviderCostSection: Sendable {
            let title: String
            let percentUsed: Double
            let spendLine: String
        }

        enum InsightStyle: Sendable {
            case info
            case success
            case warning
            case danger
        }

        struct Insight: Identifiable, Sendable {
            let id: String
            let text: String
            let style: InsightStyle
        }

        let provider: UsageProvider
        let providerName: String
        let email: String
        let subtitleText: String
        let subtitleStyle: SubtitleStyle
        let sourceContextText: String?
        let planText: String?
        let metrics: [Metric]
        let usageNotes: [String]
        let insights: [Insight]
        let creditsText: String?
        let creditsRemaining: Double?
        let creditsHintText: String?
        let creditsHintCopyText: String?
        let providerCost: ProviderCostSection?
        let tokenUsage: TokenUsageSection?
        let placeholder: String?
        let progressColor: Color
    }

    let model: Model
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    static func popupMetricTitle(provider: UsageProvider, metric: Model.Metric) -> String {
        if provider == .openrouter, metric.id == "primary" {
            return "API key limit"
        }
        return metric.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageMenuCardHeaderView(model: self.model)

            if self.hasDetails {
                MenuCardDivider()
            }

            if self.model.metrics.isEmpty {
                if !self.model.usageNotes.isEmpty || !self.model.insights.isEmpty {
                    if !self.model.usageNotes.isEmpty {
                        UsageNotesContent(notes: self.model.usageNotes)
                    }
                    if !self.model.insights.isEmpty {
                        UsageInsightsContent(insights: self.model.insights)
                    }
                } else if let placeholder = self.model.placeholder {
                    Text(placeholder)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .font(.subheadline)
                }
            } else {
                let hasUsage = !self.model.metrics.isEmpty || !self.model.usageNotes.isEmpty || !self.model.insights
                    .isEmpty
                let hasCredits = self.model.creditsText != nil
                let hasProviderCost = self.model.providerCost != nil
                let hasCost = self.model.tokenUsage != nil || hasProviderCost
                let visibleMetrics = Self.visibleMetrics(self.model.metrics)

                VStack(alignment: .leading, spacing: 10) {
                    if hasUsage {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(visibleMetrics, id: \.id) { metric in
                                MetricRow(
                                    metric: metric,
                                    title: Self.popupMetricTitle(provider: self.model.provider, metric: metric),
                                    progressColor: self.model.progressColor)
                            }
                            if !self.model.usageNotes.isEmpty {
                                UsageNotesContent(notes: self.model.usageNotes)
                            }
                            if !self.model.insights.isEmpty {
                                UsageInsightsContent(insights: self.model.insights)
                            }
                        }
                    }
                    if hasUsage, hasCredits || hasCost {
                        MenuCardDivider()
                    }
                    if let credits = self.model.creditsText {
                        CreditsBarContent(
                            creditsText: credits,
                            creditsRemaining: self.model.creditsRemaining,
                            hintText: self.model.creditsHintText,
                            hintCopyText: self.model.creditsHintCopyText,
                            progressColor: self.model.progressColor)
                    }
                    if hasCredits, hasCost {
                        MenuCardDivider()
                    }
                    if let providerCost = self.model.providerCost {
                        ProviderCostContent(
                            section: providerCost,
                            progressColor: self.model.progressColor)
                    }
                    if hasProviderCost, self.model.tokenUsage != nil {
                        MenuCardDivider()
                    }
                    if let tokenUsage = self.model.tokenUsage {
                        TokenUsageContent(tokenUsage: tokenUsage)
                    }
                }
                .padding(.bottom, self.model.creditsText == nil ? 7 : 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .frame(width: self.width, alignment: .leading)
    }

    private static func visibleMetrics(_ metrics: [Model.Metric]) -> [Model.Metric] {
        let focus = metrics.filter { $0.id == "primary" || $0.id == "secondary" }
        if !focus.isEmpty {
            return Array(focus.prefix(self.maxVisibleMetrics))
        }
        return Array(metrics.prefix(self.maxVisibleMetrics))
    }

    private var hasDetails: Bool {
        !self.model.metrics.isEmpty || !self.model.usageNotes.isEmpty || !self.model.insights.isEmpty ||
            self.model.placeholder != nil ||
            self.model.tokenUsage != nil ||
            self.model.providerCost != nil
    }
}

private struct UsageMenuCardHeaderView: View {
    let model: UsageMenuCardView.Model
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.model.providerName)
                    .font(.system(size: 18.5, weight: .semibold, design: .default))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Spacer()
            }
            let subtitleAlignment: VerticalAlignment = self.model.subtitleStyle == .error ? .top : .firstTextBaseline
            HStack(alignment: subtitleAlignment) {
                Text(self.model.subtitleText)
                    .font(.system(size: 10.8, weight: .medium, design: .default))
                    .foregroundStyle(self.subtitleColor)
                    .lineLimit(self.model.subtitleStyle == .error ? 4 : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.bottom, self.model.subtitleStyle == .error ? 4 : 0)
                Spacer()
                if self.model.subtitleStyle == .error, !self.model.subtitleText.isEmpty {
                    CopyIconButton(copyText: self.model.subtitleText, isHighlighted: self.isHighlighted)
                }
                if let plan = self.model.planText {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.35)
                        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(MenuHighlightStyle.pillBackground(self.isHighlighted))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(MenuHighlightStyle.cardBorder(self.isHighlighted), lineWidth: 0.5)
                                }
                        }
                        .lineLimit(1)
                }
            }
            if let sourceContext = self.model.sourceContextText,
               !sourceContext.isEmpty
            {
                Text(sourceContext)
                    .font(.system(size: 9.8, weight: .medium, design: .default))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            if !self.focusMetrics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(self.focusMetrics, id: \.id) { metric in
                        self.focusMetricChip(metric)
                    }
                }
                .padding(.top, 3)
            }
        }
    }

    private var subtitleColor: Color {
        switch self.model.subtitleStyle {
        case .info: MenuHighlightStyle.secondary(self.isHighlighted)
        case .loading: MenuHighlightStyle.secondary(self.isHighlighted)
        case .error: MenuHighlightStyle.error(self.isHighlighted)
        }
    }

    private var focusMetrics: [UsageMenuCardView.Model.Metric] {
        self.model.metrics.filter { $0.id == "primary" || $0.id == "secondary" }
    }

    private func focusMetricChip(_ metric: UsageMenuCardView.Model.Metric) -> some View {
        let tint = UsageMetricFocusPalette.color(for: metric)
        let suffix = metric.percentStyle == .left ? "left" : "used"
        return VStack(alignment: .leading, spacing: 1) {
            Text(metric.title.uppercased())
                .font(.system(size: 8.5, weight: .semibold, design: .default))
                .tracking(0.35)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
            Text("\(Int(metric.percent.rounded()))% \(suffix)")
                .font(.system(size: 15.0, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MenuHighlightStyle.pillBackground(self.isHighlighted))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MenuHighlightStyle.cardBorder(self.isHighlighted), lineWidth: 0.62)
                }
        }
    }
}

private struct CopyIconButtonStyle: ButtonStyle {
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(configuration.isPressed ? 0.18 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

private struct CopyIconButton: View {
    let copyText: String
    let isHighlighted: Bool

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            self.copyToPasteboard()
            withAnimation(.easeOut(duration: 0.12)) {
                self.didCopy = true
            }
            self.resetTask?.cancel()
            self.resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeOut(duration: 0.2)) {
                    self.didCopy = false
                }
            }
        } label: {
            Image(systemName: self.didCopy ? "checkmark" : "doc.on.doc")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(CopyIconButtonStyle(isHighlighted: self.isHighlighted))
        .accessibilityLabel(self.didCopy ? "Copied" : "Copy error")
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(self.copyText, forType: .string)
    }
}

private struct ProviderCostContent: View {
    let section: UsageMenuCardView.Model.ProviderCostSection
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.section.title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.42)
            UsageProgressBar(
                percent: self.section.percentUsed,
                tint: self.progressColor,
                accessibilityLabel: "Provider billed usage")
            HStack(alignment: .firstTextBaseline) {
                Text(self.section.spendLine)
                    .font(.system(size: 13.2, weight: .semibold, design: .default))
                    .monospacedDigit()
                Spacer()
                Text(String(format: "%.0f%% used", min(100, max(0, self.section.percentUsed))))
                    .font(.system(size: 10.2, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
        }
    }
}

private struct TokenUsageContent: View {
    let tokenUsage: UsageMenuCardView.Model.TokenUsageSection
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.tokenUsage.title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.42)
            if let monthly = Self.spendBreakdown(from: self.tokenUsage.monthLine) {
                Text("30d spend")
                    .font(.system(size: 9.8, weight: .semibold, design: .default))
                    .tracking(0.33)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                Text(monthly.priceText)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else {
                Text(self.tokenUsage.monthLine)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .monospacedDigit()
            }
            if let today = Self.spendBreakdown(from: self.tokenUsage.sessionLine) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today")
                        .font(.system(size: 10.4, weight: .semibold, design: .default))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    Spacer()
                    Text(today.priceText)
                        .font(.system(size: 14.2, weight: .semibold, design: .default))
                        .monospacedDigit()
                }
            } else {
                Text(self.tokenUsage.sessionLine)
                    .font(.system(size: 12.2, weight: .semibold, design: .default))
                    .monospacedDigit()
            }
            if let planSpendLine = self.tokenUsage.planSpendLine, !planSpendLine.isEmpty {
                Text(planSpendLine)
                    .font(.system(size: 10.2, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
            if let spendComparison = self.tokenUsage.spendComparison {
                BreakEvenLineGraph(comparison: spendComparison)
            } else {
                self.noBaselineUsageSummary
            }
            if let error = self.tokenUsage.errorLine, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        ClickToCopyOverlay(copyText: self.tokenUsage.errorCopyText ?? error)
                    }
            }
        }
    }

    private var noBaselineUsageSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Showing compute-only stats (plan price not detected).")
                .font(.system(size: 10.0, weight: .medium, design: .default))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(2)
            ForEach(Array(self.compactNoBaselineLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10.0, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var compactNoBaselineLines: [String] {
        [
            self.tokenUsage.averageLine,
            self.tokenUsage.coverageLine,
            self.tokenUsage.effectiveRateLine,
        ]
            .compactMap { raw in
                guard let raw else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .prefix(2)
            .map(\.self)
    }

    private struct SpendBreakdown {
        let priceText: String
        let tokenText: String?
    }

    private static func spendBreakdown(from rawLine: String) -> SpendBreakdown? {
        let parts = rawLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let payload = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }
        let payloadParts = payload.split(separator: "·", maxSplits: 1, omittingEmptySubsequences: false)
        let priceText = payloadParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !priceText.isEmpty else { return nil }
        let tokenTextRaw = payloadParts.count > 1 ? payloadParts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let tokenText = tokenTextRaw?.isEmpty == true ? nil : tokenTextRaw
        return SpendBreakdown(priceText: priceText, tokenText: tokenText)
    }
}

private struct BreakEvenLineGraph: View {
    let comparison: UsageMenuCardView.Model.SpendComparison
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(self.comparison.title)
                .font(.system(size: 9.8, weight: .semibold, design: .default))
                .tracking(0.31)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            HStack(alignment: .firstTextBaseline) {
                Text(self.statusText)
                    .font(.system(size: 10.2, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(self.statusColor)
                Spacer()
            }
            BreakEvenBars(
                paidUSD: self.comparison.paidUSD,
                valueUSD: self.comparison.valueUSD,
                paidColor: self.lossColor,
                valueColor: self.gainColor)
        }
    }

    private var deltaUSD: Double {
        self.comparison.valueUSD - self.comparison.paidUSD
    }

    private var statusText: String {
        if self.deltaUSD >= 0 {
            return "Winning \(UsageFormatter.usdString(self.deltaUSD))"
        }
        return "Losing \(UsageFormatter.usdString(abs(self.deltaUSD)))"
    }

    private var statusColor: Color {
        MenuHighlightStyle.secondary(self.isHighlighted)
    }

    private var lossColor: Color {
        Color(red: 0.84, green: 0.47, blue: 0.48)
    }

    private var gainColor: Color {
        Color(red: 0.53, green: 0.76, blue: 0.58)
    }
}

private struct BreakEvenBars: View {
    let paidUSD: Double
    let valueUSD: Double
    let paidColor: Color
    let valueColor: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let paid = max(0, self.paidUSD)
            let value = max(0, self.valueUSD)
            let total = max(0.0001, paid + value)
            let balance = max(-1, min(1, (value - paid) / total))
            let redShare = max(0, min(1, 0.5 - (balance * 0.5)))
            let redWidth = width * redShare
            let greenWidth = max(0, width - redWidth)
            let centerOffset = max(0, min(width - 1, (width * 0.5) - 0.5))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(self.paidColor.opacity(0.82))
                    .frame(width: redWidth)
                Rectangle()
                    .fill(self.valueColor.opacity(0.82))
                    .frame(width: greenWidth)
                    .offset(x: redWidth)
                Rectangle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 1)
                    .offset(x: centerOffset)
            }
            .clipShape(Capsule(style: .continuous))
            .animation(.easeInOut(duration: 0.22), value: redShare)
        }
        .frame(height: 4)
    }
}

private struct MetricRow: View {
    let metric: UsageMenuCardView.Model.Metric
    let title: String
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(self.title)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.44)
                        .foregroundStyle(
                            self.isFocusMetric
                                ? self.effectiveTint.opacity(self.isHighlighted ? 0.92 : 0.8)
                                : MenuHighlightStyle.secondary(self.isHighlighted))
                    if let windowLabel = self.metric.windowLabel {
                        Text(windowLabel)
                            .font(.system(size: 9.5, weight: .semibold, design: .default))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    }
                }
                Spacer()
                if let resetText = self.metric.resetText {
                    Text(resetText)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.28)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }
            UsageProgressBar(
                percent: self.metric.percent,
                tint: self.effectiveTint,
                accessibilityLabel: self.metric.percentStyle.accessibilityLabel,
                pacePercent: self.metric.pacePercent,
                paceOnTop: self.metric.paceOnTop)
                .frame(height: 3)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.metric.detailLeftText ?? self.metric.percentLabel)
                    .font(.system(
                        size: self.isFocusMetric ? 13.2 : 10.8,
                        weight: self.isFocusMetric ? .bold : .semibold,
                        design: .default))
                    .monospacedDigit()
                    .foregroundStyle(
                        self.isFocusMetric
                            ? self.effectiveTint
                            : MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Spacer()
                if let detailRight = self.metric.detailRightText {
                    Text(detailRight)
                        .font(.system(size: 10.2, weight: .medium, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let detail = self.metric.detailText, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10.3, weight: .regular, design: .default))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isFocusMetric: Bool {
        self.metric.id == "primary" || self.metric.id == "secondary"
    }

    private var effectiveTint: Color {
        self.isFocusMetric ? UsageMetricFocusPalette.color(for: self.metric) : self.progressColor
    }
}

private enum UsageMetricFocusPalette {
    static func color(for metric: UsageMenuCardView.Model.Metric) -> Color {
        let usedPercent = metric.percentStyle == .left ? (100 - metric.percent) : metric.percent
        if usedPercent >= 90 {
            return Color(red: 0.9, green: 0.56, blue: 0.54)
        }
        if usedPercent >= 75 {
            return Color(red: 0.93, green: 0.76, blue: 0.56)
        }
        return Color.white.opacity(0.89)
    }
}

private struct UsageNotesContent: View {
    let notes: [String]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(self.notes.prefix(1).enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageInsightsContent: View {
    let insights: [UsageMenuCardView.Model.Insight]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let visibleInsights = Array(self.insights.prefix(1))
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visibleInsights) { insight in
                HStack(alignment: .center, spacing: 7) {
                    Circle()
                        .fill(self.color(for: insight.style))
                        .frame(width: 6, height: 6)
                    Text(insight.text)
                        .font(.system(size: 12.5, weight: .medium, design: .default))
                        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(MenuHighlightStyle.pillBackground(self.isHighlighted))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(MenuHighlightStyle.cardBorder(self.isHighlighted), lineWidth: 0.5)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for style: UsageMenuCardView.Model.InsightStyle) -> Color {
        if self.isHighlighted {
            return MenuHighlightStyle.primary(true)
        }
        switch style {
        case .info:
            return MenuHighlightStyle.secondary(false)
        case .success:
            return MenuHighlightStyle.openAIAccent
        case .warning:
            return Color.white.opacity(0.62)
        case .danger:
            return Color.white.opacity(0.78)
        }
    }
}

struct UsageMenuCardHeaderSectionView: View {
    let model: UsageMenuCardView.Model
    let showDivider: Bool
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageMenuCardHeaderView(model: self.model)

            if self.showDivider {
                MenuCardDivider()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, self.model.subtitleStyle == .error ? 11 : 9)
        .frame(width: self.width, alignment: .leading)
    }
}

struct UsageMenuCardUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let bottomPadding: CGFloat
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let focusMetrics = self.model.metrics.filter { $0.id == "primary" || $0.id == "secondary" }
        let visibleMetrics = if !focusMetrics.isEmpty {
            Array(focusMetrics.prefix(UsageMenuCardView.maxVisibleMetrics))
        } else {
            Array(self.model.metrics.prefix(UsageMenuCardView.maxVisibleMetrics))
        }
        VStack(alignment: .leading, spacing: 12) {
            if self.model.metrics.isEmpty {
                if !self.model.usageNotes.isEmpty || !self.model.insights.isEmpty {
                    if !self.model.usageNotes.isEmpty {
                        UsageNotesContent(notes: self.model.usageNotes)
                    }
                    if !self.model.insights.isEmpty {
                        UsageInsightsContent(insights: self.model.insights)
                    }
                } else if let placeholder = self.model.placeholder {
                    Text(placeholder)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .font(.subheadline)
                }
            } else {
                ForEach(visibleMetrics, id: \.id) { metric in
                    MetricRow(
                        metric: metric,
                        title: UsageMenuCardView.popupMetricTitle(provider: self.model.provider, metric: metric),
                        progressColor: self.model.progressColor)
                }
                if !self.model.usageNotes.isEmpty {
                    UsageNotesContent(notes: self.model.usageNotes)
                }
                if !self.model.insights.isEmpty {
                    UsageInsightsContent(insights: self.model.insights)
                }
            }
            if self.showBottomDivider {
                MenuCardDivider()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, self.bottomPadding)
        .frame(width: self.width, alignment: .leading)
    }
}

struct UsageMenuCardCreditsSectionView: View {
    let model: UsageMenuCardView.Model
    let showBottomDivider: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        if let credits = self.model.creditsText {
            VStack(alignment: .leading, spacing: 6) {
                CreditsBarContent(
                    creditsText: credits,
                    creditsRemaining: self.model.creditsRemaining,
                    hintText: self.model.creditsHintText,
                    hintCopyText: self.model.creditsHintCopyText,
                    progressColor: self.model.progressColor)
                if self.showBottomDivider {
                    MenuCardDivider()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, self.topPadding)
            .padding(.bottom, self.bottomPadding)
            .frame(width: self.width, alignment: .leading)
        }
    }
}

private struct CreditsBarContent: View {
    private static let fullScaleTokens: Double = 1000

    let creditsText: String
    let creditsRemaining: Double?
    let hintText: String?
    let hintCopyText: String?
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private var percentLeft: Double? {
        guard let creditsRemaining else { return nil }
        let percent = (creditsRemaining / Self.fullScaleTokens) * 100
        return min(100, max(0, percent))
    }

    private var scaleText: String {
        let scale = UsageFormatter.tokenCountString(Int(Self.fullScaleTokens))
        return "\(scale) tokens"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Credits")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.42)
            if let percentLeft {
                UsageProgressBar(
                    percent: percentLeft,
                    tint: self.progressColor,
                    accessibilityLabel: "Credits remaining")
                HStack(alignment: .firstTextBaseline) {
                    Text(self.creditsText)
                        .font(.caption)
                    Spacer()
                    Text(self.scaleText)
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            } else {
                Text(self.creditsText)
                    .font(.caption)
                    .lineLimit(2)
            }
            if let hintText, !hintText.isEmpty {
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay {
                        ClickToCopyOverlay(copyText: self.hintCopyText ?? hintText)
                    }
            }
        }
    }
}

struct UsageMenuCardCostSectionView: View {
    let model: UsageMenuCardView.Model
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        let hasTokenCost = self.model.tokenUsage != nil
        return Group {
            if hasTokenCost {
                VStack(alignment: .leading, spacing: 8) {
                    if let tokenUsage = self.model.tokenUsage {
                        TokenUsageContent(tokenUsage: tokenUsage)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, self.topPadding)
                .padding(.bottom, self.bottomPadding)
                .frame(width: self.width, alignment: .leading)
            }
        }
    }
}

struct UsageMenuCardExtraUsageSectionView: View {
    let model: UsageMenuCardView.Model
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let width: CGFloat

    var body: some View {
        Group {
            if let providerCost = self.model.providerCost {
                ProviderCostContent(
                    section: providerCost,
                    progressColor: self.model.progressColor)
                    .padding(.horizontal, 16)
                    .padding(.top, self.topPadding)
                    .padding(.bottom, self.bottomPadding)
                    .frame(width: self.width, alignment: .leading)
            }
        }
    }
}

private struct MenuCardDivider: View {
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Rectangle()
            .fill(MenuHighlightStyle.subtleDivider(self.isHighlighted))
            .frame(height: 0.45)
    }
}

// MARK: - Model factory

extension UsageMenuCardView.Model {
    struct Input {
        let provider: UsageProvider
        let metadata: ProviderMetadata
        let snapshot: UsageSnapshot?
        let sourceContextText: String?
        let credits: CreditsSnapshot?
        let creditsError: String?
        let dashboard: OpenAIDashboardSnapshot?
        let dashboardError: String?
        let tokenSnapshot: CostUsageTokenSnapshot?
        let tokenError: String?
        let account: AccountInfo
        let isRefreshing: Bool
        let lastError: String?
        let usageBarsShowUsed: Bool
        let resetTimeDisplayStyle: ResetTimeDisplayStyle
        let usageBudgetModeEnabled: Bool
        let usageBudgetTargetDays: Int
        let tokenCostUsageEnabled: Bool
        let showOptionalCreditsAndExtraUsage: Bool
        let hidePersonalInfo: Bool
        let now: Date
        let localInsights: [Insight]

        init(
            provider: UsageProvider,
            metadata: ProviderMetadata,
            snapshot: UsageSnapshot?,
            sourceContextText: String? = nil,
            credits: CreditsSnapshot?,
            creditsError: String?,
            dashboard: OpenAIDashboardSnapshot?,
            dashboardError: String?,
            tokenSnapshot: CostUsageTokenSnapshot?,
            tokenError: String?,
            account: AccountInfo,
            isRefreshing: Bool,
            lastError: String?,
            usageBarsShowUsed: Bool,
            resetTimeDisplayStyle: ResetTimeDisplayStyle,
            usageBudgetModeEnabled: Bool = false,
            usageBudgetTargetDays: Int = 7,
            tokenCostUsageEnabled: Bool,
            showOptionalCreditsAndExtraUsage: Bool,
            hidePersonalInfo: Bool,
            now: Date,
            localInsights: [Insight] = [])
        {
            self.provider = provider
            self.metadata = metadata
            self.snapshot = snapshot
            self.sourceContextText = sourceContextText
            self.credits = credits
            self.creditsError = creditsError
            self.dashboard = dashboard
            self.dashboardError = dashboardError
            self.tokenSnapshot = tokenSnapshot
            self.tokenError = tokenError
            self.account = account
            self.isRefreshing = isRefreshing
            self.lastError = lastError
            self.usageBarsShowUsed = usageBarsShowUsed
            self.resetTimeDisplayStyle = resetTimeDisplayStyle
            self.usageBudgetModeEnabled = usageBudgetModeEnabled
            self.usageBudgetTargetDays = usageBudgetTargetDays
            self.tokenCostUsageEnabled = tokenCostUsageEnabled
            self.showOptionalCreditsAndExtraUsage = showOptionalCreditsAndExtraUsage
            self.hidePersonalInfo = hidePersonalInfo
            self.now = now
            self.localInsights = localInsights
        }
    }

    static func make(_ input: Input) -> UsageMenuCardView.Model {
        let planText = Self.plan(
            for: input.provider,
            snapshot: input.snapshot,
            account: input.account,
            metadata: input.metadata)
        let metrics = Self.metrics(input: input)
        let usageNotes = Self.usageNotes(provider: input.provider, snapshot: input.snapshot)
        let insights = Self.insights(input: input)
        let creditsText: String? = if input.provider == .openrouter {
            nil
        } else if input.provider == .codex, !input.showOptionalCreditsAndExtraUsage {
            nil
        } else {
            Self.creditsLine(metadata: input.metadata, credits: input.credits, error: input.creditsError)
        }
        let providerCost: ProviderCostSection? = if input.provider == .claude, !input.showOptionalCreditsAndExtraUsage {
            nil
        } else {
            Self.providerCostSection(provider: input.provider, cost: input.snapshot?.providerCost)
        }
        let tokenUsage: TokenUsageSection? = if input.tokenCostUsageEnabled {
            Self.tokenUsageSection(
                provider: input.provider,
                planText: planText,
                snapshot: input.tokenSnapshot,
                error: input.tokenError,
                now: input.now)
        } else {
            nil
        }
        let subtitle = Self.subtitle(
            snapshot: input.snapshot,
            isRefreshing: input.isRefreshing,
            lastError: input.lastError)
        let redacted = Self.redactedText(input: input, subtitle: subtitle)
        let placeholder = input.snapshot == nil && !input.isRefreshing && input.lastError == nil ? "No usage yet" : nil
        let hideCreditsHint = creditsText?.localizedCaseInsensitiveContains("unavailable") ?? false

        return UsageMenuCardView.Model(
            provider: input.provider,
            providerName: input.metadata.displayName,
            email: redacted.email,
            subtitleText: redacted.subtitleText,
            subtitleStyle: subtitle.style,
            sourceContextText: input.sourceContextText,
            planText: planText,
            metrics: metrics,
            usageNotes: usageNotes,
            insights: insights,
            creditsText: creditsText,
            creditsRemaining: input.credits?.remaining,
            creditsHintText: hideCreditsHint ? nil : redacted.creditsHintText,
            creditsHintCopyText: redacted.creditsHintCopyText,
            providerCost: providerCost,
            tokenUsage: tokenUsage,
            placeholder: placeholder,
            progressColor: Self.progressColor(for: input.provider))
    }

    private static func usageNotes(provider: UsageProvider, snapshot: UsageSnapshot?) -> [String] {
        guard provider == .openrouter,
              let openRouter = snapshot?.openRouterUsage
        else {
            return []
        }

        switch openRouter.keyQuotaStatus {
        case .available:
            return []
        case .noLimitConfigured:
            return ["No limit set for the API key"]
        case .unavailable:
            return ["API key limit unavailable right now"]
        }
    }

    private static func insights(input: Input) -> [Insight] {
        guard let snapshot = input.snapshot else { return [] }
        var insights: [Insight] = []

        if let burnRate = Self.burnRateInsight(snapshot: snapshot, now: input.now) {
            insights.append(burnRate)
        }
        if let resetCountdown = Self.resetCountdownInsight(snapshot: snapshot, now: input.now) {
            insights.append(resetCountdown)
        }
        if input.usageBudgetModeEnabled,
           let budget = Self.budgetInsight(
               snapshot: snapshot,
               targetDays: input.usageBudgetTargetDays,
               now: input.now)
        {
            insights.append(budget)
        }

        if insights.count < 2, !input.localInsights.isEmpty {
            let remainingSlots = max(0, 2 - insights.count)
            insights.append(contentsOf: input.localInsights.prefix(remainingSlots))
        }

        return Array(insights.prefix(2))
    }

    private static func burnRateInsight(snapshot: UsageSnapshot, now: Date) -> Insight? {
        guard let window = insightWindow(snapshot: snapshot),
              let resetAt = window.resetsAt
        else {
            return nil
        }
        let defaultWindowMinutes = window.windowMinutes ?? 10080
        guard let pace = UsagePace.weekly(window: window, now: now, defaultWindowMinutes: defaultWindowMinutes) else {
            return nil
        }

        if pace.willLastToReset {
            return Insight(
                id: "burn-rate",
                text: "Pace is safe: projected to last until reset.",
                style: .success)
        }

        guard let eta = pace.etaSeconds else { return nil }
        let timeUntilReset = max(1, resetAt.timeIntervalSince(now))
        let ratio = eta / timeUntilReset
        let style: InsightStyle = if ratio <= 0.33 {
            .danger
        } else if ratio <= 0.8 {
            .warning
        } else {
            .success
        }

        return Insight(
            id: "burn-rate",
            text: "At this pace, cap in \(Self.shortDurationText(eta, now: now)).",
            style: style)
    }

    private static func resetCountdownInsight(snapshot: UsageSnapshot, now: Date) -> Insight? {
        guard let nextReset = nextResetDate(snapshot: snapshot, now: now) else { return nil }
        let countdown = UsageFormatter.resetCountdownDescription(from: nextReset, now: now)
        let countdownText = countdown.hasPrefix("in ") ? String(countdown.dropFirst(3)) : countdown
        let untilReset = nextReset.timeIntervalSince(now)
        if untilReset <= 3 * 3600 {
            return Insight(
                id: "reset-countdown",
                text: "Reset \(countdownText). Best time for a long session: right after reset.",
                style: .success)
        }
        return Insight(
            id: "reset-countdown",
            text: "Reset \(countdownText).",
            style: .info)
    }

    private static func budgetInsight(snapshot: UsageSnapshot, targetDays: Int, now: Date) -> Insight? {
        guard let window = insightWindow(snapshot: snapshot),
              let resetAt = window.resetsAt
        else {
            return nil
        }
        let durationMinutes = max(1, window.windowMinutes ?? 10080)
        let duration = TimeInterval(durationMinutes * 60)
        let windowStart = resetAt.addingTimeInterval(-duration)
        let elapsed = max(0, min(duration, now.timeIntervalSince(windowStart)))
        let elapsedDays = elapsed / 86400
        let clampedTargetDays = max(1, targetDays)
        let expectedUsed = min(100, (elapsedDays / Double(clampedTargetDays)) * 100)
        let deviation = window.usedPercent - expectedUsed
        let roundedDeviation = Int(abs(deviation).rounded())
        let sign = deviation >= 0 ? "+" : "-"
        let dailyAllowance = 100 / Double(clampedTargetDays)
        let dailyText = String(format: "%.1f", dailyAllowance)

        let style: InsightStyle = if abs(deviation) <= 3 {
            .success
        } else if abs(deviation) <= 8 {
            .warning
        } else {
            .danger
        }

        return Insight(
            id: "budget-mode",
            text: "Budget \(sign)\(roundedDeviation)% vs \(clampedTargetDays)-day plan (daily \(dailyText)%).",
            style: style)
    }

    private static func insightWindow(snapshot: UsageSnapshot) -> RateWindow? {
        let candidates: [RateWindow?] = [snapshot.secondary, snapshot.primary, snapshot.tertiary]
        return candidates
            .compactMap(\.self)
            .first { $0.resetsAt != nil }
    }

    private static func nextResetDate(snapshot: UsageSnapshot, now: Date) -> Date? {
        [snapshot.primary?.resetsAt, snapshot.secondary?.resetsAt, snapshot.tertiary?.resetsAt]
            .compactMap(\.self)
            .filter { $0 > now.addingTimeInterval(-1) }
            .min()
    }

    private static func shortDurationText(_ seconds: TimeInterval, now: Date) -> String {
        if seconds >= 86400 {
            let days = seconds / 86400
            return String(format: "%.1f days", days)
        }
        let countdown = UsageFormatter.resetCountdownDescription(from: now.addingTimeInterval(seconds), now: now)
        return countdown.hasPrefix("in ") ? String(countdown.dropFirst(3)) : countdown
    }

    private static func email(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        account: AccountInfo,
        metadata: ProviderMetadata) -> String
    {
        if let email = snapshot?.accountEmail(for: provider), !email.isEmpty { return email }
        if metadata.usesAccountFallback,
           let email = account.email, !email.isEmpty
        {
            return email
        }
        return ""
    }

    private static func plan(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        account: AccountInfo,
        metadata: ProviderMetadata) -> String?
    {
        if provider == .gemini {
            // Gemini tier labels are frequently ambiguous in practice, so avoid
            // rendering a potentially misleading plan chip.
            return nil
        }
        if let plan = snapshot?.loginMethod(for: provider), !plan.isEmpty {
            return self.planDisplay(plan)
        }
        if metadata.usesAccountFallback,
           let plan = account.plan, !plan.isEmpty
        {
            return Self.planDisplay(plan)
        }
        return nil
    }

    private static func planDisplay(_ text: String) -> String {
        let cleaned = UsageFormatter.cleanPlanName(text)
        return cleaned.isEmpty ? text : cleaned
    }

    private static func subtitle(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        lastError: String?) -> (text: String, style: SubtitleStyle)
    {
        if let lastError, !lastError.isEmpty {
            return (lastError.trimmingCharacters(in: .whitespacesAndNewlines), .error)
        }

        if isRefreshing, snapshot == nil {
            return ("Refreshing...", .loading)
        }

        if let updated = snapshot?.updatedAt {
            return (UsageFormatter.updatedString(from: updated), .info)
        }

        return ("Not fetched yet", .info)
    }

    private struct RedactedText {
        let email: String
        let subtitleText: String
        let creditsHintText: String?
        let creditsHintCopyText: String?
    }

    private static func redactedText(
        input: Input,
        subtitle: (text: String, style: SubtitleStyle)) -> RedactedText
    {
        let email = PersonalInfoRedactor.redactEmail(
            Self.email(
                for: input.provider,
                snapshot: input.snapshot,
                account: input.account,
                metadata: input.metadata),
            isEnabled: input.hidePersonalInfo)
        let subtitleText = PersonalInfoRedactor.redactEmails(in: subtitle.text, isEnabled: input.hidePersonalInfo)
            ?? subtitle.text
        let creditsHintText = PersonalInfoRedactor.redactEmails(
            in: Self.dashboardHint(provider: input.provider, error: input.dashboardError),
            isEnabled: input.hidePersonalInfo)
        let creditsHintCopyText = Self.creditsHintCopyText(
            dashboardError: input.dashboardError,
            hidePersonalInfo: input.hidePersonalInfo)
        return RedactedText(
            email: email,
            subtitleText: subtitleText,
            creditsHintText: creditsHintText,
            creditsHintCopyText: creditsHintCopyText)
    }

    private static func creditsHintCopyText(dashboardError: String?, hidePersonalInfo: Bool) -> String? {
        guard let dashboardError, !dashboardError.isEmpty else { return nil }
        return hidePersonalInfo ? "" : dashboardError
    }

    private static func metrics(input: Input) -> [Metric] {
        guard let snapshot = input.snapshot else { return [] }
        var metrics: [Metric] = []
        let percentStyle: PercentStyle = input.usageBarsShowUsed ? .used : .left
        let suppressResetText = input.provider == .gemini
        let zaiUsage = input.provider == .zai ? snapshot.zaiUsage : nil
        let zaiTokenDetail = Self.zaiLimitDetailText(limit: zaiUsage?.tokenLimit)
        let zaiTimeDetail = Self.zaiLimitDetailText(limit: zaiUsage?.timeLimit)
        let openRouterQuotaDetail = Self.openRouterQuotaDetail(provider: input.provider, snapshot: snapshot)
        let dashboardPrimary = input.provider == .codex ? input.dashboard?.primaryLimit : nil
        let dashboardSecondary = input.provider == .codex ? input.dashboard?.secondaryLimit : nil
        if let primary = Self.mergedWindow(preferred: snapshot.primary, fallback: dashboardPrimary) {
            var primaryDetailText: String? = input.provider == .zai ? zaiTokenDetail : nil
            var primaryResetText = Self.resetText(for: primary, style: input.resetTimeDisplayStyle, now: input.now)
            if input.provider == .openrouter,
               let openRouterQuotaDetail
            {
                primaryResetText = openRouterQuotaDetail
            }
            if input.provider == .warp,
               let detail = primary.resetDescription,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                primaryDetailText = detail
            }
            if input.provider == .warp, primary.resetsAt == nil {
                primaryResetText = nil
            }
            if suppressResetText {
                primaryResetText = nil
            }
            metrics.append(Metric(
                id: "primary",
                title: input.metadata.sessionLabel,
                windowLabel: Self.windowLabel(for: primary),
                windowMinutes: primary.windowMinutes,
                percent: Self.clamped(
                    input.usageBarsShowUsed ? primary.usedPercent : primary.remainingPercent),
                percentStyle: percentStyle,
                resetText: primaryResetText,
                detailText: primaryDetailText,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }
        if let weekly = Self.mergedWindow(preferred: snapshot.secondary, fallback: dashboardSecondary) {
            let paceDetail = Self.weeklyPaceDetail(
                provider: input.provider,
                window: weekly,
                now: input.now,
                showUsed: input.usageBarsShowUsed)
            var weeklyResetText = Self.resetText(for: weekly, style: input.resetTimeDisplayStyle, now: input.now)
            var weeklyDetailText: String? = input.provider == .zai ? zaiTimeDetail : nil
            if input.provider == .warp,
               let detail = weekly.resetDescription,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                weeklyResetText = nil
                weeklyDetailText = detail
            }
            if suppressResetText {
                weeklyResetText = nil
            }
            metrics.append(Metric(
                id: "secondary",
                title: input.metadata.weeklyLabel,
                windowLabel: Self.windowLabel(for: weekly),
                windowMinutes: weekly.windowMinutes,
                percent: Self.clamped(input.usageBarsShowUsed ? weekly.usedPercent : weekly.remainingPercent),
                percentStyle: percentStyle,
                resetText: weeklyResetText,
                detailText: weeklyDetailText,
                detailLeftText: paceDetail?.leftLabel,
                detailRightText: paceDetail?.rightLabel,
                pacePercent: paceDetail?.pacePercent,
                paceOnTop: paceDetail?.paceOnTop ?? true))
        }
        if input.metadata.supportsOpus, let opus = snapshot.tertiary {
            metrics.append(Metric(
                id: "tertiary",
                title: input.metadata.opusLabel ?? "Sonnet",
                windowLabel: Self.windowLabel(for: opus),
                windowMinutes: opus.windowMinutes,
                percent: Self.clamped(input.usageBarsShowUsed ? opus.usedPercent : opus.remainingPercent),
                percentStyle: percentStyle,
                resetText: Self.resetText(for: opus, style: input.resetTimeDisplayStyle, now: input.now),
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }

        if input.provider == .codex, let remaining = input.dashboard?.codeReviewRemainingPercent {
            let percent = input.usageBarsShowUsed ? (100 - remaining) : remaining
            metrics.append(Metric(
                id: "code-review",
                title: "Code review",
                windowLabel: nil,
                windowMinutes: nil,
                percent: Self.clamped(percent),
                percentStyle: percentStyle,
                resetText: nil,
                detailText: nil,
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true))
        }
        return metrics
    }

    private static func zaiLimitDetailText(limit: ZaiLimitEntry?) -> String? {
        guard let limit else { return nil }

        if let currentValue = limit.currentValue,
           let usage = limit.usage,
           let remaining = limit.remaining
        {
            let currentStr = UsageFormatter.tokenCountString(currentValue)
            let usageStr = UsageFormatter.tokenCountString(usage)
            let remainingStr = UsageFormatter.tokenCountString(remaining)
            return "\(currentStr) / \(usageStr) (\(remainingStr) remaining)"
        }

        return nil
    }

    private static func openRouterQuotaDetail(provider: UsageProvider, snapshot: UsageSnapshot) -> String? {
        guard provider == .openrouter,
              let usage = snapshot.openRouterUsage,
              usage.hasValidKeyQuota,
              let keyRemaining = usage.keyRemaining,
              let keyLimit = usage.keyLimit
        else {
            return nil
        }

        let remaining = UsageFormatter.usdString(keyRemaining)
        let limit = UsageFormatter.usdString(keyLimit)
        return "\(remaining)/\(limit) left"
    }

    private struct PaceDetail {
        let leftLabel: String
        let rightLabel: String?
        let pacePercent: Double?
        let paceOnTop: Bool
    }

    private static func weeklyPaceDetail(
        provider: UsageProvider,
        window: RateWindow,
        now: Date,
        showUsed: Bool) -> PaceDetail?
    {
        guard let detail = UsagePaceText.weeklyDetail(provider: provider, window: window, now: now) else { return nil }
        let expectedUsed = detail.expectedUsedPercent
        let actualUsed = window.usedPercent
        let expectedPercent = showUsed ? expectedUsed : (100 - expectedUsed)
        let actualPercent = showUsed ? actualUsed : (100 - actualUsed)
        if expectedPercent.isFinite == false || actualPercent.isFinite == false { return nil }
        let paceOnTop = actualUsed <= expectedUsed
        let pacePercent: Double? = if detail.stage == .onTrack { nil } else { expectedPercent }
        return PaceDetail(
            leftLabel: detail.leftLabel,
            rightLabel: detail.rightLabel,
            pacePercent: pacePercent,
            paceOnTop: paceOnTop)
    }

    private static func creditsLine(
        metadata: ProviderMetadata,
        credits: CreditsSnapshot?,
        error: String?) -> String?
    {
        guard metadata.supportsCredits else { return nil }
        if let credits {
            return UsageFormatter.creditsString(from: credits.remaining)
        }
        if let error, !error.isEmpty {
            _ = error
            return nil
        }
        return nil
    }

    private static func dashboardHint(provider: UsageProvider, error: String?) -> String? {
        _ = provider
        _ = error
        return nil
    }

    private static func tokenUsageSection(
        provider: UsageProvider,
        planText: String?,
        snapshot: CostUsageTokenSnapshot?,
        error: String?,
        now: Date) -> TokenUsageSection?
    {
        guard provider == .codex || provider == .claude || provider == .vertexai else { return nil }
        let planPricing = Self.planPricingBaseline(provider: provider, planText: planText)
        let planSpendLine = Self.planSpendLine(from: planPricing)
        guard let snapshot else {
            let err = (error?.isEmpty ?? true) ? nil : error
            return TokenUsageSection(
                title: "Model compute cost",
                sessionLine: "Today (compute): —",
                monthLine: "Last 30 days (compute): —",
                planSpendLine: planSpendLine,
                todayEconomicsLine: nil,
                weekEconomicsLine: nil,
                monthEconomicsLine: nil,
                averageLine: "Syncing local compute usage...",
                coverageLine: nil,
                effectiveRateLine: nil,
                modelSpendLine: nil,
                allTimeLine: nil,
                spendComparison: nil,
                hintLine: "Estimated from local usage logs. Separate from subscription and provider billing.",
                errorLine: err,
                errorCopyText: (error?.isEmpty ?? true) ? nil : error)
        }

        let sessionCostValue = snapshot.sessionCostUSD
        let sessionCost = sessionCostValue.map { UsageFormatter.usdString($0) } ?? "—"
        let sessionTokens = snapshot.sessionTokens.map { UsageFormatter.tokenCountString($0) }
        let sessionLine: String = {
            if let sessionTokens {
                return "Today (compute): \(sessionCost) · \(sessionTokens) tokens"
            }
            return "Today (compute): \(sessionCost)"
        }()

        let fallbackCost = snapshot.daily.compactMap(\.costUSD).reduce(0, +)
        let monthCostValue = snapshot.last30DaysCostUSD ?? (fallbackCost > 0 ? fallbackCost : nil)
        let monthCost = monthCostValue.map { UsageFormatter.usdString($0) } ?? "—"
        let fallbackTokens = snapshot.daily.compactMap(\.totalTokens).reduce(0, +)
        let monthTokensValue = snapshot.last30DaysTokens ?? (fallbackTokens > 0 ? fallbackTokens : nil)
        let monthTokens = monthTokensValue.map { UsageFormatter.tokenCountString($0) }
        let monthLine: String = {
            if let monthTokens {
                return "Last 30 days (compute): \(monthCost) · \(monthTokens) tokens"
            }
            return "Last 30 days (compute): \(monthCost)"
        }()
        let activeDays = Self.activeDayCount(from: snapshot.daily)
        let averageLine = Self.averageUsageLine(
            costUSD: monthCostValue,
            tokens: monthTokensValue,
            activeDays: activeDays)
        let coverageLine = activeDays > 0 ? "Active usage days (30d): \(activeDays)/30" : nil
        let effectiveRateLine = Self.effectiveRateLine(costUSD: monthCostValue, tokens: monthTokensValue)
        let modelSpendLine = Self.modelSpendLine(from: snapshot)
        let allTimeLine = Self.allTimeUsageLine(from: snapshot)
        let spendComparison = Self.spendComparison(
            from: planPricing,
            valueUSD: sessionCostValue,
            now: now,
            periodDays: 1,
            title: "Today break-even")
        let weekCostValue = Self.periodCostUSD(from: snapshot.daily, days: 7, now: now)
        let weekComparison = Self.spendComparison(
            from: planPricing,
            valueUSD: weekCostValue,
            now: now,
            periodDays: 7,
            title: "7d break-even")
        let monthComparison = Self.spendComparison(
            from: planPricing,
            valueUSD: monthCostValue,
            now: now,
            periodDays: 30,
            title: "30d break-even")
        let todayEconomicsLine = Self.economicsLine(label: "Today", comparison: spendComparison)
        let weekEconomicsLine = Self.economicsLine(label: "7d", comparison: weekComparison)
        let monthEconomicsLine = Self.economicsLine(label: "30d", comparison: monthComparison)
        let err = (error?.isEmpty ?? true) ? nil : error
        return TokenUsageSection(
            title: "Model compute cost",
            sessionLine: sessionLine,
            monthLine: monthLine,
            planSpendLine: planSpendLine,
            todayEconomicsLine: todayEconomicsLine,
            weekEconomicsLine: weekEconomicsLine,
            monthEconomicsLine: monthEconomicsLine,
            averageLine: averageLine,
            coverageLine: coverageLine,
            effectiveRateLine: effectiveRateLine,
            modelSpendLine: modelSpendLine,
            allTimeLine: allTimeLine,
            spendComparison: spendComparison,
            hintLine: "Estimated from local usage logs. Separate from subscription and provider billing.",
            errorLine: err,
            errorCopyText: (error?.isEmpty ?? true) ? nil : error)
    }

    private static func providerCostSection(
        provider: UsageProvider,
        cost: ProviderCostSnapshot?) -> ProviderCostSection?
    {
        guard let cost else { return nil }
        guard cost.limit > 0 else { return nil }

        let used: String
        let limit: String
        let title: String

        if cost.currencyCode == "Quota" {
            title = "Provider quota"
            used = String(format: "%.0f", cost.used)
            limit = String(format: "%.0f", cost.limit)
        } else {
            title = "Provider billed usage"
            used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
            limit = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
        }

        let percentUsed = Self.clamped((cost.used / cost.limit) * 100)
        let periodLabel = cost.period ?? "This month"

        return ProviderCostSection(
            title: title,
            percentUsed: percentUsed,
            spendLine: "\(periodLabel): \(used) / \(limit)")
    }

    private static func clamped(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func mergedWindow(preferred: RateWindow?, fallback: RateWindow?) -> RateWindow? {
        guard let preferred else { return fallback }
        guard let fallback else { return preferred }
        return RateWindow(
            usedPercent: preferred.usedPercent,
            windowMinutes: preferred.windowMinutes ?? fallback.windowMinutes,
            resetsAt: preferred.resetsAt ?? fallback.resetsAt,
            resetDescription: preferred.resetDescription ?? fallback.resetDescription)
    }

    private static func windowLabel(for window: RateWindow) -> String? {
        guard let minutes = window.windowMinutes, minutes > 0 else { return nil }
        if minutes % 1440 == 0 {
            return "\(minutes / 1440)d"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    private static func modelSpendLine(from snapshot: CostUsageTokenSnapshot) -> String? {
        var totals: [String: Double] = [:]
        for day in snapshot.daily {
            guard let breakdowns = day.modelBreakdowns else { continue }
            for breakdown in breakdowns {
                guard let cost = breakdown.costUSD, cost > 0 else { continue }
                totals[breakdown.modelName, default: 0] += cost
            }
        }
        guard !totals.isEmpty else { return nil }
        let topModels = totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .prefix(3)
            .map { name, cost in "\(name): \(UsageFormatter.usdString(cost))" }
        guard !topModels.isEmpty else { return nil }
        return "Top models (30d): \(topModels.joined(separator: " · "))"
    }

    private static func allTimeUsageLine(from snapshot: CostUsageTokenSnapshot) -> String? {
        let cost = snapshot.allTimeCostUSD.map { UsageFormatter.usdString($0) }
        let tokens = snapshot.allTimeTokens.map { "\(UsageFormatter.tokenCountString($0)) tokens" }
        guard cost != nil || tokens != nil else { return nil }

        let value = [cost, tokens].compactMap(\.self).joined(separator: " · ")
        if let since = snapshot.allTimeSince {
            return "All-time local logs (since \(Self.shortDate(since))): \(value)"
        }
        return "All-time local logs: \(value)"
    }

    private struct PlanPricingBaseline {
        let planLabel: String
        let monthlyUSD: Double
    }

    private static func planPricingBaseline(provider: UsageProvider, planText: String?) -> PlanPricingBaseline? {
        guard let planText, !planText.isEmpty else { return nil }
        if let explicitMonthly = self.monthlyPriceFromPlanText(planText) {
            return PlanPricingBaseline(
                planLabel: planText.trimmingCharacters(in: .whitespacesAndNewlines),
                monthlyUSD: explicitMonthly)
        }

        let normalized = planText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .codex:
            if normalized.contains("pro") {
                return PlanPricingBaseline(planLabel: "Pro", monthlyUSD: 200)
            }
            if normalized.contains("plus") {
                return PlanPricingBaseline(planLabel: "Plus", monthlyUSD: 20)
            }
            if normalized.contains("free") {
                return PlanPricingBaseline(planLabel: "Free", monthlyUSD: 0)
            }
        case .claude:
            if normalized.contains("max") {
                if normalized.contains("20x") || normalized.contains("200") {
                    return PlanPricingBaseline(planLabel: "Max 20x", monthlyUSD: 200)
                }
                return PlanPricingBaseline(planLabel: "Max (est.)", monthlyUSD: 100)
            }
            if normalized.contains("pro") {
                return PlanPricingBaseline(planLabel: "Pro", monthlyUSD: 20)
            }
            if normalized.contains("free") {
                return PlanPricingBaseline(planLabel: "Free", monthlyUSD: 0)
            }
        case .gemini:
            if normalized.contains("ultra") {
                return PlanPricingBaseline(planLabel: "Ultra", monthlyUSD: 250)
            }
            if normalized.contains("advanced") || normalized.contains("pro") || normalized.contains("standard") {
                return PlanPricingBaseline(planLabel: "Pro", monthlyUSD: 20)
            }
            if normalized.contains("workspace") || normalized.contains("free") {
                return PlanPricingBaseline(planLabel: "Free/Workspace", monthlyUSD: 0)
            }
        default:
            break
        }
        return nil
    }

    private static func monthlyPriceFromPlanText(_ planText: String) -> Double? {
        let lower = planText.lowercased()
        let monthlyHints = ["mo", "month", "/m", "monthly"]
        guard monthlyHints.contains(where: { lower.contains($0) }) else { return nil }

        guard let regex = try? NSRegularExpression(pattern: #"\$+\s*([0-9]+(?:\.[0-9]{1,2})?)"#) else {
            return nil
        }
        let range = NSRange(planText.startIndex..<planText.endIndex, in: planText)
        guard let match = regex.firstMatch(in: planText, range: range),
              match.numberOfRanges > 1,
              let amountRange = Range(match.range(at: 1), in: planText)
        else {
            return nil
        }
        return Double(planText[amountRange])
    }

    private static func planSpendLine(from pricing: PlanPricingBaseline?) -> String? {
        guard let pricing else { return nil }
        return "Subscription: \(pricing.planLabel) · \(UsageFormatter.usdString(pricing.monthlyUSD))/mo"
    }

    private static func dailyPlanSpend(monthlyUSD: Double, now: Date) -> Double {
        let daysInMonth = max(1, Calendar.current.range(of: .day, in: .month, for: now)?.count ?? 30)
        return monthlyUSD / Double(daysInMonth)
    }

    private static func periodPlanSpend(monthlyUSD: Double, periodDays: Int, now: Date) -> Double {
        self.dailyPlanSpend(monthlyUSD: monthlyUSD, now: now) * Double(max(1, periodDays))
    }

    private static func spendComparison(
        from pricing: PlanPricingBaseline?,
        valueUSD: Double?,
        now: Date,
        periodDays: Int,
        title: String) -> SpendComparison?
    {
        guard let pricing else { return nil }

        let paid = self.periodPlanSpend(monthlyUSD: pricing.monthlyUSD, periodDays: periodDays, now: now)
        let value = max(0, valueUSD ?? 0)
        if paid <= 0, value <= 0 {
            return nil
        }

        return SpendComparison(
            title: title,
            paidUSD: paid,
            valueUSD: value)
    }

    private static func economicsLine(label: String, comparison: SpendComparison?) -> String? {
        guard let comparison else { return nil }
        let paidText = UsageFormatter.usdString(comparison.paidUSD)
        let valueText = UsageFormatter.usdString(comparison.valueUSD)
        let delta = comparison.valueUSD - comparison.paidUSD
        if delta >= 0 {
            return "\(label): Paid \(paidText) · Compute \(valueText) · Ahead \(UsageFormatter.usdString(delta))"
        }
        return "\(label): Paid \(paidText) · Compute \(valueText) · To OpenAI \(UsageFormatter.usdString(abs(delta)))"
    }

    private static func periodCostUSD(from entries: [CostUsageDailyReport.Entry], days: Int, now: Date) -> Double? {
        guard days > 0 else { return nil }
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: now)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else { return nil }
        let total = entries.reduce(0.0) { partial, entry in
            guard let costUSD = entry.costUSD, costUSD > 0 else { return partial }
            guard let entryDate = self.dateFromDayKey(entry.date) else { return partial }
            let entryDay = calendar.startOfDay(for: entryDate)
            guard entryDay >= startDay, entryDay <= endDay else { return partial }
            return partial + costUSD
        }
        return total > 0 ? total : nil
    }

    private static func dateFromDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date
    }

    private static func activeDayCount(from entries: [CostUsageDailyReport.Entry]) -> Int {
        entries.reduce(into: 0) { count, entry in
            let hasTokens = (entry.totalTokens ?? 0) > 0
            let hasCost = (entry.costUSD ?? 0) > 0
            if hasTokens || hasCost {
                count += 1
            }
        }
    }

    private static func averageUsageLine(costUSD: Double?, tokens: Int?, activeDays: Int) -> String? {
        guard activeDays > 0 else { return nil }
        let avgCost = costUSD.map { UsageFormatter.usdString($0 / Double(activeDays)) }
        let avgTokens = tokens.map { UsageFormatter.tokenCountString(Int((Double($0) / Double(activeDays)).rounded())) }
        let valueParts: [String] = [avgCost, avgTokens.map { "\($0) tokens" }].compactMap(\.self)
        guard !valueParts.isEmpty else { return nil }
        return "Avg active day (30d): \(valueParts.joined(separator: " · "))"
    }

    private static func effectiveRateLine(costUSD: Double?, tokens: Int?) -> String? {
        guard let costUSD, let tokens, tokens > 0 else { return nil }
        let perMillion = (costUSD / Double(tokens)) * 1_000_000
        return "Effective rate (30d): \(UsageFormatter.usdString(perMillion)) / 1M tokens"
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func progressColor(for provider: UsageProvider) -> Color {
        let color = ProviderDescriptorRegistry.descriptor(for: provider).branding.color
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private static func resetText(
        for window: RateWindow,
        style: ResetTimeDisplayStyle,
        now: Date) -> String?
    {
        guard let raw = UsageFormatter.resetLine(for: window, style: style, now: now) else { return nil }
        if raw.hasPrefix("Resets in ") {
            return "Reset \(raw.dropFirst("Resets in ".count))"
        }
        if raw.hasPrefix("Reset in ") {
            return "Reset \(raw.dropFirst("Reset in ".count))"
        }
        if raw.hasPrefix("Resets ") {
            return "Reset \(raw.dropFirst("Resets ".count))"
        }
        return raw
    }
}

// MARK: - Copy-on-click overlay

private struct ClickToCopyOverlay: NSViewRepresentable {
    let copyText: String

    func makeNSView(context: Context) -> ClickToCopyView {
        ClickToCopyView(copyText: self.copyText)
    }

    func updateNSView(_ nsView: ClickToCopyView, context: Context) {
        nsView.copyText = self.copyText
    }
}

private final class ClickToCopyView: NSView {
    var copyText: String

    init(copyText: String) {
        self.copyText = copyText
        super.init(frame: .zero)
        self.wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        _ = event
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(self.copyText, forType: .string)
    }
}

import AppKit
import Charts
import SwiftUI
import TokenBarCore

private struct DashboardSpendPoint: Identifiable {
    let date: Date
    let costUSD: Double
    let tokens: Int

    var id: String {
        String(Int(self.date.timeIntervalSince1970 / 86400))
    }
}

private struct DashboardUsagePoint: Identifiable {
    let date: Date
    let usedPercent: Double

    var id: String {
        String(Int(self.date.timeIntervalSince1970 / 86400))
    }
}

private struct DashboardModelSpend: Identifiable {
    let modelName: String
    let costUSD: Double

    var id: String {
        self.modelName
    }
}

private struct DashboardHistoryEntry: Identifiable {
    let date: Date
    let costUSD: Double

    var id: String {
        String(Int(self.date.timeIntervalSince1970 / 86400))
    }

    var isActive: Bool {
        self.costUSD > 0
    }
}

private struct DashboardSummaryMetric: Identifiable {
    let label: String
    let value: String
    let detail: String
    let tint: Color

    var id: String {
        self.label
    }
}

private struct DashboardProviderRow: Identifiable {
    let provider: UsageProvider
    let snapshot: UsageSnapshot?
    let tokenSnapshot: CostUsageTokenSnapshot?
    let sourceContext: String?
    let status: ProviderStatus?
    let sessionSummary: UsageTelemetryStore.SessionSummary?
    let isOnline: Bool

    var id: String {
        self.provider.rawValue
    }

    var latestUpdatedAt: Date? {
        switch (self.snapshot?.updatedAt, self.tokenSnapshot?.updatedAt) {
        case let (snapshotDate?, tokenDate?):
            max(snapshotDate, tokenDate)
        case let (snapshotDate?, nil):
            snapshotDate
        case let (nil, tokenDate?):
            tokenDate
        case (nil, nil):
            nil
        }
    }
}

private struct PlanPricingBaseline {
    let planLabel: String
    let monthlyUSD: Double
}

private struct BreakEvenComparison {
    let paidUSD: Double
    let valueUSD: Double
    let deltaUSD: Double
    let baselineKnown: Bool
    let planSummary: String
    let note: String
}

private enum DashboardTheme {
    static let background = Color(red: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0)
    static let panel = Color(red: 24.0 / 255.0, green: 24.0 / 255.0, blue: 24.0 / 255.0)
    static let panelStroke = Color.white.opacity(0.10)

    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.74)
    static let textMuted = Color.white.opacity(0.52)

    static let accent = Color(red: 0.67, green: 0.84, blue: 0.99)
    static let accentStrong = Color(red: 0.56, green: 0.79, blue: 0.97)
    static let positive = Color(red: 0.40, green: 0.84, blue: 0.58)
    static let warning = Color(red: 0.95, green: 0.73, blue: 0.39)
    static let negative = Color(red: 0.92, green: 0.46, blue: 0.42)

    static let chromeFill = Color.white.opacity(0.055)
    static let chromeStroke = Color.white.opacity(0.10)
}

private enum DashboardProviderPresence {
    case live
    case offline

    var badgeTitle: String {
        switch self {
        case .live:
            "LIVE"
        case .offline:
            "OFFLINE"
        }
    }

    var badgeTint: Color {
        switch self {
        case .live:
            DashboardTheme.positive
        case .offline:
            DashboardTheme.textSecondary
        }
    }

    var badgeBackground: Color {
        switch self {
        case .live:
            DashboardTheme.positive.opacity(0.18)
        case .offline:
            Color.white.opacity(0.08)
        }
    }

    var isDimmed: Bool {
        self == .offline
    }
}

private enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .day:
            "Day"
        case .week:
            "Week"
        case .month:
            "Month"
        case .year:
            "Year"
        }
    }

    var days: Int {
        switch self {
        case .day:
            1
        case .week:
            7
        case .month:
            30
        case .year:
            365
        }
    }
}

private enum DashboardProviderScope: String, CaseIterable, Identifiable {
    case live
    case all

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .live:
            "Live only"
        case .all:
            "All"
        }
    }
}

@MainActor
struct AppDashboardView: View {
    static let windowID = "tokenbar-dashboard-window"

    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    let account: AccountInfo

    @State private var selectedRange: DashboardTimeRange = .month
    @State private var selectedScope: DashboardProviderScope = .all
    @State private var selectedProvider: UsageProvider?
    @State private var selectedModel: String?
    @State private var showDetailedAnalytics = true
    @State private var runningCLIProviders: Set<UsageProvider> = []

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let groupedIntegerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private var connectedProviders: [UsageProvider] {
        var ordered = self.store.enabledProviders()
        for provider in UsageProvider.allCases {
            if self.store.snapshot(for: provider) != nil || self.store.tokenSnapshot(for: provider) != nil,
               !ordered.contains(provider)
            {
                ordered.append(provider)
            }
        }
        return ordered
    }

    private var allRows: [DashboardProviderRow] {
        self.connectedProviders.map { provider in
            DashboardProviderRow(
                provider: provider,
                snapshot: self.store.snapshot(for: provider),
                tokenSnapshot: self.store.tokenSnapshot(for: provider),
                sourceContext: self.store.sourceContextHint(for: provider),
                status: self.store.status(for: provider),
                sessionSummary: self.store.sessionTrackingSummary(for: provider),
                isOnline: self.runningCLIProviders.contains(provider))
        }
    }

    private var liveRows: [DashboardProviderRow] {
        self.allRows.filter(\.isOnline)
    }

    private var onlineRows: [DashboardProviderRow] {
        self.liveRows
    }

    private var offlineRows: [DashboardProviderRow] {
        let onlineIDs = Set(self.onlineRows.map(\.id))
        return self.allRows.filter { !onlineIDs.contains($0.id) }
    }

    private var rowsForScope: [DashboardProviderRow] {
        switch self.selectedScope {
        case .live:
            self.onlineRows
        case .all:
            self.allRows
        }
    }

    private var providerFilterOptions: [UsageProvider] {
        self.rowsForScope.map(\.provider)
    }

    private var selectedProviderFilter: UsageProvider? {
        guard let selectedProvider, self.providerFilterOptions.contains(selectedProvider) else {
            return nil
        }
        return selectedProvider
    }

    private var rowsForAnalytics: [DashboardProviderRow] {
        guard let provider = self.selectedProviderFilter else { return self.rowsForScope }
        return self.rowsForScope.filter { $0.provider == provider }
    }

    private var providersForAnalytics: [UsageProvider] {
        self.rowsForAnalytics.map(\.provider)
    }

    private var availableModelOptions: [String] {
        self.collectModelNames(days: self.selectedRange.days, providers: self.providersForAnalytics)
    }

    private var selectedModelFilter: String? {
        guard let selectedModel else { return nil }
        return self.availableModelOptions.first(where: {
            $0.caseInsensitiveCompare(selectedModel) == .orderedSame
        })
    }

    private var usageTrend: [DashboardUsagePoint] {
        self.makeUsageTrendPoints(days: self.selectedRange.days, providers: self.providersForAnalytics)
    }

    private var spendTrend: [DashboardSpendPoint] {
        self.makeSpendTrendPoints(
            days: self.selectedRange.days,
            providers: self.providersForAnalytics,
            modelName: self.selectedModelFilter)
    }

    private var historyDayCount: Int {
        switch self.selectedRange {
        case .day, .week:
            90
        case .month:
            180
        case .year:
            365
        }
    }

    private var historyEntries: [DashboardHistoryEntry] {
        self.makeHistoryEntries(
            days: self.historyDayCount,
            providers: self.providersForAnalytics,
            modelName: self.selectedModelFilter)
    }

    private var historyActiveDays: Int {
        self.historyEntries.filter(\.isActive).count
    }

    private var historyMaxCost: Double {
        self.historyEntries.map(\.costUSD).max() ?? 0
    }

    private var historyMostActiveEntry: DashboardHistoryEntry? {
        self.historyEntries.max { lhs, rhs in
            if lhs.costUSD == rhs.costUSD {
                return lhs.date < rhs.date
            }
            return lhs.costUSD < rhs.costUSD
        }
    }

    private var historyLongestStreak: Int {
        var current = 0
        var best = 0
        for entry in self.historyEntries {
            if entry.isActive {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    private var historyCurrentStreak: Int {
        var streak = 0
        for entry in self.historyEntries.reversed() {
            guard entry.isActive else { break }
            streak += 1
        }
        return streak
    }

    private var selectedRangeSpendUSD: Double {
        self.spendTrend.reduce(0) { $0 + $1.costUSD }
    }

    private var selectedRangeTokens: Int {
        self.spendTrend.reduce(0) { $0 + $1.tokens }
    }

    private var spendByProvider: [UsageProvider: Double] {
        self.makeProviderSpendTotals(
            days: self.selectedRange.days,
            providers: self.providersForAnalytics,
            modelName: self.selectedModelFilter)
    }

    private var topModelSpend: [DashboardModelSpend] {
        self.makeModelSpendRanking(days: self.selectedRange.days, providers: self.providersForAnalytics)
    }

    private var rowsForQuotaMetrics: [DashboardProviderRow] {
        if !self.rowsForAnalytics.isEmpty {
            return self.rowsForAnalytics
        }
        return self.rowsForScope
    }

    private var minimumSessionRemaining: Double? {
        let values = self.rowsForQuotaMetrics.compactMap { row in
            self.sessionWindow(for: row.provider, snapshot: row.snapshot)?.remainingPercent
        }
        guard !values.isEmpty else { return nil }
        return values.min()
    }

    private var minimumWeeklyRemaining: Double? {
        let values = self.rowsForQuotaMetrics.compactMap { row in
            self.weeklyWindow(for: row.provider, snapshot: row.snapshot)?.remainingPercent
        }
        guard !values.isEmpty else { return nil }
        return values.min()
    }

    private var selectedScopeProviderCount: Int {
        if !self.rowsForAnalytics.isEmpty {
            return self.rowsForAnalytics.count
        }
        return self.rowsForScope.count
    }

    private var selectedScopeTodayMinutes: Int {
        self.rowsForAnalytics.reduce(0) { partial, row in
            partial + max(0, row.sessionSummary?.providerTodayMinutes ?? 0)
        }
    }

    private var selectedScopeWeekMinutes: Int {
        self.rowsForAnalytics.reduce(0) { partial, row in
            partial + max(0, row.sessionSummary?.providerWeekMinutes ?? 0)
        }
    }

    private var spendActiveDayCount: Int {
        self.spendTrend.count
    }

    private var averageSpendPerActiveDayUSD: Double {
        guard self.spendActiveDayCount > 0 else { return 0 }
        return self.selectedRangeSpendUSD / Double(self.spendActiveDayCount)
    }

    private var rangeLeadingSummaryMetrics: [DashboardSummaryMetric] {
        let providerDetail = if self.selectedScopeProviderCount == 1 {
            "Across 1 visible provider"
        } else {
            "Across \(self.selectedScopeProviderCount) visible providers"
        }

        switch self.selectedRange {
        case .day:
            return [
                DashboardSummaryMetric(
                    label: "Session Left",
                    value: self.percentText(self.minimumSessionRemaining),
                    detail: providerDetail,
                    tint: self.usageTint(for: self.minimumSessionRemaining)),
                DashboardSummaryMetric(
                    label: "Today Active",
                    value: Self.minutesText(self.selectedScopeTodayMinutes),
                    detail: "\(Self.minutesText(self.selectedScopeWeekMinutes)) this week",
                    tint: DashboardTheme.textPrimary),
            ]
        case .week:
            return [
                DashboardSummaryMetric(
                    label: "Weekly Left",
                    value: self.percentText(self.minimumWeeklyRemaining),
                    detail: providerDetail,
                    tint: self.usageTint(for: self.minimumWeeklyRemaining)),
                DashboardSummaryMetric(
                    label: "Week Active",
                    value: Self.minutesText(self.selectedScopeWeekMinutes),
                    detail: "\(Self.minutesText(self.selectedScopeTodayMinutes)) today",
                    tint: DashboardTheme.textPrimary),
            ]
        case .month:
            return [
                DashboardSummaryMetric(
                    label: "Active Days",
                    value: "\(self.spendActiveDayCount)/\(self.selectedRange.days)",
                    detail: "Days with measured spend in range",
                    tint: DashboardTheme.textPrimary),
                DashboardSummaryMetric(
                    label: "Avg Active Day",
                    value: UsageFormatter.usdString(self.averageSpendPerActiveDayUSD),
                    detail: "Based on \(max(1, self.spendActiveDayCount)) active day(s)",
                    tint: DashboardTheme.textPrimary),
            ]
        case .year:
            return [
                DashboardSummaryMetric(
                    label: "Active Days",
                    value: "\(self.spendActiveDayCount)/\(self.selectedRange.days)",
                    detail: "Days with measured spend in range",
                    tint: DashboardTheme.textPrimary),
                DashboardSummaryMetric(
                    label: "Models Tracked",
                    value: "\(self.availableModelOptions.count)",
                    detail: "Models with measured spend in this filter",
                    tint: DashboardTheme.textPrimary),
            ]
        }
    }

    private var breakEvenProviders: [UsageProvider] {
        if let selectedProvider = self.selectedProviderFilter {
            return [selectedProvider]
        }
        return self.providersForAnalytics.filter { provider in
            (self.spendByProvider[provider] ?? 0) > 0
        }
    }

    private var breakEvenResult: (comparison: BreakEvenComparison?, unavailable: String?) {
        let providers = self.breakEvenProviders
        guard !providers.isEmpty else {
            return (nil, "No measured spend in this filter yet.")
        }

        let measuredValue = providers.reduce(0.0) { partial, provider in
            partial + (self.spendByProvider[provider] ?? 0)
        }
        if let selectedModel = self.selectedModelFilter {
            guard measuredValue > 0 else {
                return (
                    nil,
                    "No measured spend for \(selectedModel) in this \(self.selectedRange.title.lowercased()) range.")
            }
            let comparison = BreakEvenComparison(
                paidUSD: 0,
                valueUSD: measuredValue,
                deltaUSD: measuredValue,
                baselineKnown: false,
                planSummary: "Plan allocation per model is unavailable.",
                note: "Showing measured usage for \(selectedModel).")
            return (comparison, nil)
        }

        var paidTotal = 0.0
        var planParts: [String] = []
        var unknownPlans: [String] = []

        for provider in providers {
            let providerName = self.store.metadata(for: provider).displayName
            guard let baseline = Self.planPricingBaseline(provider: provider, planText: self.planText(for: provider))
            else {
                unknownPlans.append(providerName)
                continue
            }
            let paid = Self.periodPlanSpend(
                monthlyUSD: baseline.monthlyUSD,
                periodDays: self.selectedRange.days,
                now: Date())
            paidTotal += paid
            planParts
                .append("\(providerName) \(baseline.planLabel) \(UsageFormatter.usdString(baseline.monthlyUSD))/mo")
        }

        let summary = if planParts.isEmpty {
            "No detected paid plans."
        } else {
            "Estimate includes: \(planParts.joined(separator: " · "))"
        }

        if paidTotal <= 0 {
            if measuredValue <= 0 {
                return (nil, "No measured spend in this filter yet.")
            }
            let unknownNote = if unknownPlans.isEmpty {
                "No subscription baseline for the current provider/model."
            } else {
                "No plan price detected for \(unknownPlans.joined(separator: ", "))."
            }
            let comparison = BreakEvenComparison(
                paidUSD: 0,
                valueUSD: max(0, measuredValue),
                deltaUSD: measuredValue,
                baselineKnown: false,
                planSummary: unknownNote,
                note: "Showing measured usage only for this filter.")
            return (comparison, nil)
        }

        let note = if unknownPlans.isEmpty {
            "Paid is estimated from detected plan tiers; value is measured usage cost."
        } else {
            "Missing plan price for \(unknownPlans.joined(separator: ", ")). Estimate is partial."
        }

        let comparison = BreakEvenComparison(
            paidUSD: paidTotal,
            valueUSD: max(0, measuredValue),
            deltaUSD: measuredValue - paidTotal,
            baselineKnown: true,
            planSummary: summary,
            note: note)
        return (comparison, nil)
    }

    private var breakEvenComparison: BreakEvenComparison? {
        self.breakEvenResult.comparison
    }

    private var breakEvenUnavailableMessage: String {
        self.breakEvenResult.unavailable ?? "Unavailable"
    }

    private var usageRangeLabel: String {
        guard let first = self.usageTrend.first?.date,
              let last = self.usageTrend.last?.date
        else {
            return "No date range"
        }
        return "\(Self.fullDateString(first)) to \(Self.fullDateString(last))"
    }

    private var spendRangeLabel: String {
        guard let first = self.spendTrend.first?.date,
              let last = self.spendTrend.last?.date
        else {
            return "No date range"
        }
        return "\(Self.fullDateString(first)) to \(Self.fullDateString(last))"
    }

    private var spendMetricDetail: String {
        let averageText = UsageFormatter.usdString(self.averageSpendPerActiveDayUSD)
        let activeDaysText = "\(self.spendActiveDayCount)d active"
        let tokensText = "\(Self.groupedIntegerString(self.selectedRangeTokens)) tokens"

        if let model = self.selectedModelFilter {
            if self.selectedRangeTokens > 0 {
                return "\(tokensText) · \(model) · avg/day \(averageText)"
            }
            return "\(model) · token split unavailable · avg/day \(averageText)"
        }
        return "\(tokensText) · \(activeDaysText) · avg/day \(averageText)"
    }

    private var providerMenuTitle: String {
        guard let provider = self.selectedProviderFilter else { return "All providers" }
        return self.store.metadata(for: provider).displayName
    }

    private var modelMenuTitle: String {
        self.selectedModelFilter ?? "All models"
    }

    var body: some View {
        Group {
            if self.settings.isLicenseUnlocked {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        self.header
                        self.controlRow
                        self.summaryRow
                        if let comparison = self.breakEvenComparison {
                            self.breakEvenMeterPanel(comparison)
                        }
                        if self.showDetailedAnalytics {
                            self.historyHeatmapPanel
                            self.chartRow
                            self.modelSpendPanel
                        }
                        self.providersSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                }
            } else {
                self.licenseRequiredView
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .background(DashboardTheme.background)
        .task {
            await self.pollRunningProvidersLoop()
        }
        .onAppear {
            self.normalizeFilterSelections()
        }
        .onChange(of: self.selectedScope) { _, _ in
            self.normalizeFilterSelections()
        }
        .onChange(of: self.selectedProvider) { _, _ in
            self.normalizeFilterSelections()
        }
        .onChange(of: self.selectedRange) { _, _ in
            self.normalizeFilterSelections()
        }
        .onChange(of: self.runningCLIProviders) { _, _ in
            self.normalizeFilterSelections()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokenbarOpenDashboard)) { _ in
            self.selectedScope = .all
            self.selectedProvider = nil
            self.selectedModel = nil
        }
    }

    private var licenseRequiredView: some View {
        VStack {
            VStack(spacing: 22) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("TokenBar Lifetime Access")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.45)
                        .textCase(.uppercase)
                }
                .foregroundStyle(Color.white.opacity(0.76))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 70, height: 70)
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.17), lineWidth: 0.8)
                        .frame(width: 70, height: 70)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                }

                VStack(spacing: 10) {
                    Text("TokenBar is locked")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)

                    Text(self.settings.licenseStatusMessage)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 540)
                }

                HStack(spacing: 8) {
                    self.licenseTag("One-time $5")
                    self.licenseTag("Lifetime")
                    self.licenseTag("1 device")
                }

                VStack(alignment: .leading, spacing: 8) {
                    self.licenseFeatureRow(icon: "circle.fill", text: "Premium dashboard, provider insights, spend analytics")
                    self.licenseFeatureRow(icon: "circle.fill", text: "No recurring subscription")
                    self.licenseFeatureRow(icon: "circle.fill", text: "Refund/dispute protection with automatic revocation")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    self.licenseCTAButton("Open Settings", isPrimary: true) {
                        self.openSettings()
                    }
                    self.licenseCTAButton("Buy Lifetime ($5)", isPrimary: false) {
                        self.openLicenseCheckout()
                    }
                }
                .padding(.top, 2)

                Text("Your license key is shown once after purchase. Save it securely.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 680)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.85)
                    }
                    .shadow(color: Color.black.opacity(0.28), radius: 28, y: 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
    }

    private func licenseTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.09))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
            }
    }

    private func licenseFeatureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.52))
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func licenseCTAButton(
        _ title: String,
        isPrimary: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.black.opacity(0.88) : Color.white.opacity(0.90))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isPrimary ? Color.white.opacity(0.98) : Color.white.opacity(0.10))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(isPrimary ? 0.0 : 0.16), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TokenBar Dashboard")
                    .font(.system(size: 49, weight: .bold))
                    .foregroundStyle(DashboardTheme.textPrimary)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text("Live usage and spend analytics from your real provider data")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DashboardTheme.textSecondary)
            }

            Spacer()

            Text("Live \(self.onlineRows.count) · Offline \(self.offlineRows.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashboardTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(DashboardTheme.chromeFill)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(DashboardTheme.chromeStroke, lineWidth: 0.8)
                }

            self.actionPillButton("Refresh", prominence: .subtle) {
                self.refreshNow()
            }

            self.actionPillButton(
                self.showDetailedAnalytics ? "Essentials" : "Details",
                prominence: .subtle)
            {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showDetailedAnalytics.toggle()
                }
            }

            self.actionPillButton("Settings", prominence: .normal) {
                self.openSettings()
            }
        }
    }

    private var controlRow: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(DashboardTimeRange.allCases) { range in
                        self.filterPill(
                            title: range.title,
                            isSelected: self.selectedRange == range,
                            action: { self.selectedRange = range })
                    }
                }

                Spacer(minLength: 6)
            }

            if self.showDetailedAnalytics {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(DashboardProviderScope.allCases) { scope in
                            self.filterPill(
                                title: scope.title,
                                isSelected: self.selectedScope == scope,
                                action: { self.selectedScope = scope })
                        }
                    }

                    Spacer(minLength: 6)

                    Menu {
                        Button("All providers") {
                            self.selectedProvider = nil
                        }
                        if !self.providerFilterOptions.isEmpty {
                            Divider()
                        }
                        ForEach(self.providerFilterOptions, id: \.self) { provider in
                            Button(self.store.metadata(for: provider).displayName) {
                                self.selectedProvider = provider
                            }
                        }
                    } label: {
                        self.selectionMenuLabel(title: "Provider", value: self.providerMenuTitle)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(minWidth: 182)

                    if !self.availableModelOptions.isEmpty {
                        Menu {
                            Button("All models") {
                                self.selectedModel = nil
                            }
                            Divider()
                            ForEach(self.availableModelOptions, id: \.self) { modelName in
                                Button(modelName) {
                                    self.selectedModel = modelName
                                }
                            }
                        } label: {
                            self.selectionMenuLabel(title: "Model", value: self.modelMenuTitle)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(minWidth: 214)
                    }
                }
            }

            if self.showDetailedAnalytics {
                Text("Data source: live provider snapshots, token usage exports, and local telemetry.")
                    .font(.caption2)
                    .foregroundStyle(DashboardTheme.textMuted)
                Text("Provider = app/service (Codex, Claude, Gemini). Model = model IDs inside provider usage.")
                    .font(.caption2)
                    .foregroundStyle(DashboardTheme.textMuted.opacity(0.86))
            }
        }
        .padding(14)
        .background(self.panelBackground)
    }

    private var summaryRow: some View {
        let breakEvenValue = if let comparison = self.breakEvenComparison {
            if !comparison.baselineKnown {
                "Usage \(UsageFormatter.usdString(comparison.valueUSD))"
            } else if comparison.deltaUSD >= 0 {
                "Gain \(UsageFormatter.usdString(comparison.deltaUSD))"
            } else {
                "Loss \(UsageFormatter.usdString(abs(comparison.deltaUSD)))"
            }
        } else {
            "Unavailable"
        }

        let breakEvenDetail = if let comparison = self.breakEvenComparison {
            if comparison.baselineKnown {
                "Paid \(UsageFormatter.usdString(comparison.paidUSD))"
                    + " · Value \(UsageFormatter.usdString(comparison.valueUSD))"
            } else {
                comparison.planSummary
            }
        } else {
            self.breakEvenUnavailableMessage
        }

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(self.rangeLeadingSummaryMetrics) { metric in
                    self.statCard(
                        label: metric.label,
                        value: metric.value,
                        detail: metric.detail,
                        tint: metric.tint)
                }
            }
            HStack(spacing: 12) {
                self.statCard(
                    label: "\(self.selectedRange.title) Spend (Real)",
                    value: UsageFormatter.usdString(self.selectedRangeSpendUSD),
                    detail: self.spendMetricDetail,
                    tint: DashboardTheme.textPrimary)
                self.statCard(
                    label: "\(self.selectedRange.title) Gain / Loss",
                    value: breakEvenValue,
                    detail: breakEvenDetail,
                    tint: self.breakEvenTint)
            }
        }
    }

    private func breakEvenMeterPanel(_ comparison: BreakEvenComparison) -> some View {
        let normalizedDelta: Double = if comparison.baselineKnown, comparison.paidUSD > 0 {
            min(1, abs(comparison.deltaUSD) / comparison.paidUSD)
        } else {
            0
        }
        let statusText = if !comparison.baselineKnown {
            "Usage-only mode"
        } else if comparison.deltaUSD >= 0 {
            "You are ahead"
        } else {
            "You are behind"
        }
        let statusTint = if !comparison.baselineKnown {
            DashboardTheme.textSecondary
        } else if comparison.deltaUSD >= 0 {
            DashboardTheme.positive
        } else {
            DashboardTheme.negative
        }
        let netText = if comparison.deltaUSD >= 0 {
            "Net +\(UsageFormatter.usdString(abs(comparison.deltaUSD)))"
        } else {
            "Net -\(UsageFormatter.usdString(abs(comparison.deltaUSD)))"
        }
        let netTint: Color = comparison.deltaUSD >= 0
            ? DashboardTheme.positive
            : DashboardTheme.negative

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(self.selectedRange.title) Gain / Loss Meter")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DashboardTheme.textSecondary)
                Spacer()
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusTint)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let half = width / 2
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    if comparison.baselineKnown {
                        HStack(spacing: 0) {
                            Rectangle().fill(DashboardTheme.negative.opacity(0.24))
                            Rectangle().fill(DashboardTheme.positive.opacity(0.22))
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.70))
                            .frame(width: 1)

                        if comparison.deltaUSD >= 0 {
                            Rectangle()
                                .fill(DashboardTheme.positive.opacity(0.86))
                                .frame(width: half * normalizedDelta)
                                .offset(x: (half * normalizedDelta) / 2)
                        } else {
                            Rectangle()
                                .fill(DashboardTheme.negative.opacity(0.88))
                                .frame(width: half * normalizedDelta)
                                .offset(x: -(half * normalizedDelta) / 2)
                        }
                    } else {
                        Rectangle()
                            .fill(DashboardTheme.accent.opacity(0.32))
                    }
                }
                .clipShape(Capsule(style: .continuous))
            }
            .frame(height: 12)

            HStack {
                Text("Paid \(UsageFormatter.usdString(comparison.paidUSD))")
                    .foregroundStyle(DashboardTheme.textMuted)
                Spacer()
                Text("Value \(UsageFormatter.usdString(comparison.valueUSD))")
                    .foregroundStyle(DashboardTheme.textSecondary)
                Spacer()
                Text(netText)
                    .foregroundStyle(netTint)
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()

            if self.showDetailedAnalytics {
                Text(comparison.note)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
            }
        }
        .padding(14)
        .background(self.panelBackground)
    }

    private var historyHeatmapPanel: some View {
        let weeks = self.historyHeatmapWeeks
        let hasActivity = self.historyActiveDays > 0
        let mostActiveDayText = if let entry = self.historyMostActiveEntry, entry.costUSD > 0 {
            Self.fullDateString(entry.date)
        } else {
            "None"
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DashboardTheme.textSecondary)
                    Text("Daily activity over the last \(self.historyDayCount) days")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textMuted)
                }

                Spacer()

                HStack(spacing: 16) {
                    self.historyStat(title: "Active Days", value: "\(self.historyActiveDays)")
                    self.historyStat(title: "Longest Streak", value: "\(self.historyLongestStreak)d")
                    self.historyStat(title: "Current Streak", value: "\(self.historyCurrentStreak)d")
                    self.historyStat(title: "Most Active Day", value: mostActiveDayText)
                }
            }

            if !hasActivity {
                self.emptyChartPlaceholder(text: "No activity yet in this history range.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { weekdayIndex in
                                    self.historyCell(week[weekdayIndex])
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 90)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.panelBackground)
    }

    private func historyStat(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DashboardTheme.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashboardTheme.textPrimary)
                .monospacedDigit()
        }
    }

    private func historyCell(_ entry: DashboardHistoryEntry?) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(self.historyCellColor(entry))
            .frame(width: 10, height: 10)
    }

    private func historyCellColor(_ entry: DashboardHistoryEntry?) -> Color {
        guard let entry else { return .clear }
        guard entry.costUSD > 0, self.historyMaxCost > 0 else {
            return Color.white.opacity(0.08)
        }

        let ratio = min(1, entry.costUSD / self.historyMaxCost)
        if ratio < 0.25 {
            return DashboardTheme.positive.opacity(0.32)
        }
        if ratio < 0.50 {
            return DashboardTheme.positive.opacity(0.48)
        }
        if ratio < 0.75 {
            return DashboardTheme.positive.opacity(0.66)
        }
        return DashboardTheme.positive.opacity(0.84)
    }

    private var historyHeatmapWeeks: [[DashboardHistoryEntry?]] {
        guard let firstDay = self.historyEntries.first?.date,
              let lastDay = self.historyEntries.last?.date
        else {
            return []
        }

        let calendar = Calendar.current
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay
        let dayLookup = Dictionary(uniqueKeysWithValues: self.historyEntries.map { ($0.date, $0) })

        var weeks: [[DashboardHistoryEntry?]] = []
        var cursor = firstWeekStart

        while cursor <= lastDay {
            var week = Array<DashboardHistoryEntry?>(repeating: nil, count: 7)
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: cursor) else { continue }
                guard day >= firstDay, day <= lastDay else { continue }
                week[offset] = dayLookup[day] ?? DashboardHistoryEntry(date: day, costUSD: 0)
            }
            weeks.append(week)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }

        return weeks
    }

    private var chartRow: some View {
        HStack(alignment: .top, spacing: 12) {
            self.usageChartPanel
            self.spendChartPanel
        }
    }

    private var usageChartPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Usage Trend")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DashboardTheme.textSecondary)
            Text("Average used % over the selected \(self.selectedRange.title.lowercased())")
                .font(.caption)
                .foregroundStyle(DashboardTheme.textMuted)

            if self.usageTrend.isEmpty {
                self.emptyChartPlaceholder(text: "No usage history in this range yet.")
            } else {
                Chart {
                    RuleMark(y: .value("Reference", 50))
                        .foregroundStyle(Color.white.opacity(0.16))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(self.usageTrend) { point in
                        AreaMark(
                            x: .value("Day", point.date),
                            y: .value("Used", point.usedPercent))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        DashboardTheme.accent.opacity(0.28),
                                        DashboardTheme.accent.opacity(0.03),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom))

                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Used", point.usedPercent))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                            .foregroundStyle(DashboardTheme.accentStrong)

                        PointMark(
                            x: .value("Day", point.date),
                            y: .value("Used", point.usedPercent))
                            .symbolSize(24)
                            .foregroundStyle(DashboardTheme.accent)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)%")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(DashboardTheme.textMuted)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 208)

                Text(self.usageRangeLabel)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.panelBackground)
    }

    private var spendChartPanel: some View {
        let averageSpend = self.spendTrend.isEmpty ? 0 : self.selectedRangeSpendUSD / Double(max(
            1,
            self.spendTrend.count))
        let subtitle = if let selectedModel = self.selectedModelFilter {
            "Daily spend for \(selectedModel)"
        } else {
            "Daily spend for visible providers"
        }

        return VStack(alignment: .leading, spacing: 11) {
            Text("Compute Spend")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DashboardTheme.textSecondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(DashboardTheme.textMuted)

            if self.spendTrend.isEmpty {
                self.emptyChartPlaceholder(text: "No spend data in this range yet.")
            } else {
                Chart {
                    RuleMark(y: .value("Average", averageSpend))
                        .foregroundStyle(Color.white.opacity(0.16))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(self.spendTrend) { point in
                        BarMark(
                            x: .value("Day", point.date),
                            y: .value("Cost", point.costUSD))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        DashboardTheme.accent.opacity(0.94),
                                        DashboardTheme.accentStrong.opacity(0.86),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(UsageFormatter.usdString(cost))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(DashboardTheme.textMuted)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 208)

                Text(self.spendRangeLabel)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.panelBackground)
    }

    private var modelSpendPanel: some View {
        let maxCost = self.topModelSpend.map(\.costUSD).max() ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Spend")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DashboardTheme.textSecondary)
                Spacer()
                if let selectedModel = self.selectedModelFilter {
                    Text("Filtered: \(selectedModel)")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textMuted)
                }
            }

            if self.topModelSpend.isEmpty {
                Text("No model-level breakdown available in this range.")
                    .font(.subheadline)
                    .foregroundStyle(DashboardTheme.textMuted)
            } else {
                ForEach(self.topModelSpend.prefix(5)) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.modelName)
                                .font(.subheadline)
                                .foregroundStyle(DashboardTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(UsageFormatter.usdString(entry.costUSD))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DashboardTheme.textPrimary)
                                .monospacedDigit()
                        }

                        GeometryReader { proxy in
                            let scale = maxCost > 0 ? entry.costUSD / maxCost : 0
                            let width = proxy.size.width * scale
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                                Capsule(style: .continuous)
                                    .fill(DashboardTheme.accentStrong.opacity(0.95))
                                    .frame(width: width)
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.panelBackground)
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Providers")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardTheme.textSecondary)

            if self.selectedScope == .live {
                self.providerSubsection(
                    title: "Online",
                    subtitle: "Detected live in your system",
                    rows: self.filteredRows(self.onlineRows),
                    emptyText: "No online providers are running right now.")
            } else if !self.showDetailedAnalytics {
                self.providerSubsection(
                    title: "Online",
                    subtitle: "Detected live in your system",
                    rows: self.filteredRows(self.onlineRows),
                    emptyText: "No online providers right now.")
                if !self.filteredRows(self.offlineRows).isEmpty {
                    Text("\(self.filteredRows(self.offlineRows).count) offline provider(s) hidden in Essentials.")
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.textMuted)
                        .padding(.horizontal, 2)
                }
            } else {
                self.providerSubsection(
                    title: "Online",
                    subtitle: "Detected live in your system",
                    rows: self.filteredRows(self.onlineRows),
                    emptyText: "No online providers right now.")
                self.providerSubsection(
                    title: "Offline",
                    subtitle: "Not currently detected as live",
                    rows: self.filteredRows(self.offlineRows),
                    emptyText: "No offline providers detected.")
            }
        }
    }

    private func providerSubsection(
        title: String,
        subtitle: String,
        rows: [DashboardProviderRow],
        emptyText: String) -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.textSecondary)
                Text("\(rows.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DashboardTheme.textMuted)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
            }
            if rows.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(DashboardTheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                ForEach(rows) { row in
                    self.providerCard(row: row)
                }
            }
        }
    }

    private func providerCard(row: DashboardProviderRow) -> some View {
        let metadata = self.store.metadata(for: row.provider)
        let snapshot = row.snapshot
        let presence = self.providerPresence(for: row)
        let sessionWindow = self.sessionWindow(for: row.provider, snapshot: snapshot)
        let weeklyWindow = self.weeklyWindow(for: row.provider, snapshot: snapshot)
        let sessionLeft = sessionWindow?.remainingPercent
        let weeklyLeft = weeklyWindow?.remainingPercent
        let todayMinutes = row.sessionSummary?.providerTodayMinutes ?? 0
        let weeklyMinutes = row.sessionSummary?.providerWeekMinutes ?? 0
        let updatedText = if let updatedAt = row.latestUpdatedAt {
            UsageFormatter.updatedString(from: updatedAt)
        } else {
            "No snapshot yet"
        }
        let statusText = row.status?.indicator.label

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(metadata.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DashboardTheme.textPrimary.opacity(presence.isDimmed ? 0.74 : 1))
                Spacer()
                Text(presence.badgeTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(presence.badgeTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(presence.badgeBackground)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                    }
            }

            HStack(spacing: 12) {
                self.providerMetric(label: "Session", value: self.percentText(sessionLeft))
                self.providerMetric(label: "Weekly", value: self.percentText(weeklyLeft))
                self.providerMetric(label: "Today active", value: Self.minutesText(todayMinutes))
            }

            self.progressRow(label: "Session", remaining: sessionLeft)
            self.progressRow(label: "Weekly", remaining: weeklyLeft)

            HStack {
                let runtimeDetail = "\(self.providerRuntimeLine(row)) · Week active \(Self.minutesText(weeklyMinutes))"
                Text(runtimeDetail)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
                Spacer()
                if self.showDetailedAnalytics {
                    HStack(spacing: 8) {
                        if let statusText {
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(DashboardTheme.textMuted)
                        }
                        Text(updatedText)
                            .font(.caption)
                            .foregroundStyle(DashboardTheme.textMuted)
                    }
                }
            }

            if self.showDetailedAnalytics {
                HStack(spacing: 8) {
                    Menu {
                        Button("Usage Dashboard") { self.openProviderDashboard(row.provider) }
                        Button("Status") { self.openProviderStatusPage(row.provider) }
                        if row.provider == .codex {
                            Button("Buy Credits") { self.openCreditsPurchase() }
                        }
                    } label: {
                        self.actionPillButtonLabel("Open")
                    }
                    .menuStyle(.borderlessButton)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(self.panelBackground)
        .opacity(presence.isDimmed ? 0.92 : 1)
    }

    private enum DashboardActionProminence {
        case normal
        case subtle
    }

    private func actionPillButton(
        _ title: String,
        prominence: DashboardActionProminence,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            self.actionPillButtonLabel(title, prominence: prominence)
        }
        .buttonStyle(.plain)
    }

    private func actionPillButtonLabel(
        _ title: String,
        prominence: DashboardActionProminence = .subtle) -> some View
    {
        let fillColor: Color = switch prominence {
        case .normal:
            DashboardTheme.accent.opacity(0.20)
        case .subtle:
            DashboardTheme.chromeFill
        }
        let strokeColor: Color = switch prominence {
        case .normal:
            DashboardTheme.accent.opacity(0.42)
        case .subtle:
            DashboardTheme.chromeStroke
        }

        return Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DashboardTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(fillColor)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.8)
            }
    }

    private func filterPill(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? DashboardTheme.textPrimary : DashboardTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? DashboardTheme.accent.opacity(0.21) : DashboardTheme.chromeFill)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? DashboardTheme.accent.opacity(0.46) : DashboardTheme.chromeStroke,
                            lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }

    private func selectionMenuLabel(title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Text("\(title):")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DashboardTheme.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashboardTheme.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DashboardTheme.textMuted)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            Capsule(style: .continuous)
                .fill(DashboardTheme.chromeFill)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(DashboardTheme.chromeStroke, lineWidth: 0.8)
        }
    }

    private func statCard(label: String, value: String, detail: String, tint: Color) -> some View {
        let isUsagePriority = label.localizedCaseInsensitiveContains("session")
            || label.localizedCaseInsensitiveContains("weekly")
        let isCostPriority = label.localizedCaseInsensitiveContains("spend")
            || label.localizedCaseInsensitiveContains("break-even")
            || label.localizedCaseInsensitiveContains("plan")
        let valueSize: CGFloat = if isUsagePriority {
            34
        } else if isCostPriority {
            30
        } else {
            26
        }

        return VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DashboardTheme.textMuted)
            Text(value)
                .font(.system(size: valueSize, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DashboardTheme.textMuted)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.panelBackground)
    }

    private func providerMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DashboardTheme.textMuted)
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(DashboardTheme.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressRow(label: String, remaining: Double?) -> some View {
        let usedPercent = 100 - (remaining ?? 0)
        let normalized = min(max(usedPercent / 100, 0), 1)
        let tint = self.usageTint(for: remaining)

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(DashboardTheme.textMuted)
                Spacer()
                Text(self.percentText(remaining))
                    .font(.caption)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: true)
            }
            GeometryReader { proxy in
                let width = max(0, proxy.size.width * normalized)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.92))
                        .frame(width: width)
                }
            }
            .frame(height: 7)
        }
    }

    private func emptyChartPlaceholder(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DashboardTheme.textMuted)
            Spacer(minLength: 0)
        }
        .frame(height: 208, alignment: .topLeading)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(DashboardTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DashboardTheme.panelStroke, lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 4, y: 1)
    }

    private var breakEvenTint: Color {
        guard let comparison = self.breakEvenComparison else { return DashboardTheme.textSecondary }
        if !comparison.baselineKnown {
            return DashboardTheme.textPrimary
        }
        let delta = comparison.deltaUSD
        return delta >= 0
            ? DashboardTheme.positive
            : DashboardTheme.negative
    }

    private func providerPresence(for row: DashboardProviderRow) -> DashboardProviderPresence {
        if row.isOnline {
            return .live
        }
        return .offline
    }

    private func providerRuntimeLine(_ row: DashboardProviderRow) -> String {
        let source = row.sourceContext ?? "Source unknown"
        switch self.providerPresence(for: row) {
        case .live:
            return "Live now · \(source)"
        case .offline:
            return "Offline · \(source)"
        }
    }

    private func planText(for provider: UsageProvider) -> String? {
        self.store.snapshot(for: provider)?.loginMethod(for: provider)
    }

    private func makeUsageTrendPoints(days: Int, providers: [UsageProvider]) -> [DashboardUsagePoint] {
        guard days > 0 else { return [] }
        var totalsByDay: [Date: (sum: Double, sampleCount: Int)] = [:]
        let calendar = Calendar.current

        for provider in providers {
            let series = self.store.timelineDaySeries(for: provider, days: days, now: Date())
            for point in series {
                let day = calendar.startOfDay(for: point.date)
                let used = min(max(point.usedPercent, 0), 100)
                var total = totalsByDay[day] ?? (0, 0)
                total.sum += used
                total.sampleCount += 1
                totalsByDay[day] = total
            }
        }

        if totalsByDay.isEmpty {
            let today = calendar.startOfDay(for: Date())
            for provider in providers {
                guard let snapshot = self.store.snapshot(for: provider) else { continue }
                let used = self.sessionWindow(for: provider, snapshot: snapshot)?.usedPercent
                    ?? snapshot.secondary?.usedPercent
                    ?? 0
                var total = totalsByDay[today] ?? (0, 0)
                total.sum += min(max(used, 0), 100)
                total.sampleCount += 1
                totalsByDay[today] = total
            }
        }

        return totalsByDay
            .compactMap { day, total in
                guard total.sampleCount > 0 else { return nil }
                return DashboardUsagePoint(date: day, usedPercent: total.sum / Double(total.sampleCount))
            }
            .sorted { $0.date < $1.date }
    }

    private func makeSpendTrendPoints(
        days: Int,
        providers: [UsageProvider],
        modelName: String?) -> [DashboardSpendPoint]
    {
        guard days > 0 else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end

        var totalsByDay: [Date: (cost: Double, tokens: Int)] = [:]
        for provider in providers {
            guard let snapshot = self.store.tokenSnapshot(for: provider) else { continue }
            for entry in snapshot.daily {
                guard let date = Self.dayKeyToDate(entry.date) else { continue }
                let day = calendar.startOfDay(for: date)
                guard day >= start, day <= end else { continue }
                guard let measured = Self.measuredCostAndTokens(entry: entry, modelName: modelName) else { continue }
                var total = totalsByDay[day] ?? (0, 0)
                total.cost += measured.costUSD
                total.tokens += measured.tokens
                totalsByDay[day] = total
            }
        }

        return totalsByDay
            .map { day, total in
                DashboardSpendPoint(date: day, costUSD: total.cost, tokens: total.tokens)
            }
            .sorted { $0.date < $1.date }
    }

    private func makeHistoryEntries(
        days: Int,
        providers: [UsageProvider],
        modelName: String?) -> [DashboardHistoryEntry]
    {
        guard days > 0 else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end

        let spendPoints = self.makeSpendTrendPoints(
            days: days,
            providers: providers,
            modelName: modelName)
        let dayToCost = Dictionary(uniqueKeysWithValues: spendPoints.map { ($0.date, $0.costUSD) })

        var entries: [DashboardHistoryEntry] = []
        var cursor = start
        while cursor <= end {
            let day = calendar.startOfDay(for: cursor)
            let cost = max(0, dayToCost[day] ?? 0)
            entries.append(DashboardHistoryEntry(date: day, costUSD: cost))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            cursor = next
        }

        return entries
    }

    private func makeProviderSpendTotals(
        days: Int,
        providers: [UsageProvider],
        modelName: String?) -> [UsageProvider: Double]
    {
        guard days > 0 else { return [:] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        var totals: [UsageProvider: Double] = [:]

        for provider in providers {
            guard let snapshot = self.store.tokenSnapshot(for: provider) else { continue }
            for entry in snapshot.daily {
                guard let date = Self.dayKeyToDate(entry.date) else { continue }
                let day = calendar.startOfDay(for: date)
                guard day >= start, day <= end else { continue }
                guard let measured = Self.measuredCostAndTokens(entry: entry, modelName: modelName) else { continue }
                totals[provider, default: 0] += measured.costUSD
            }
        }
        return totals
    }

    private func makeModelSpendRanking(days: Int, providers: [UsageProvider]) -> [DashboardModelSpend] {
        guard days > 0 else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        var totals: [String: Double] = [:]

        for provider in providers {
            guard let snapshot = self.store.tokenSnapshot(for: provider) else { continue }
            for entry in snapshot.daily {
                guard let date = Self.dayKeyToDate(entry.date) else { continue }
                let day = calendar.startOfDay(for: date)
                guard day >= start, day <= end else { continue }

                if let breakdowns = entry.modelBreakdowns, !breakdowns.isEmpty {
                    let allowedModels = Self.normalizedModelNames(entry.modelsUsed)
                    for breakdown in breakdowns {
                        let cleaned = breakdown.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleaned.isEmpty else { continue }
                        if let allowedModels,
                           !allowedModels.contains(Self.normalizedModelName(cleaned))
                        {
                            continue
                        }
                        let cost = max(0, breakdown.costUSD ?? 0)
                        guard cost > 0 else { continue }
                        totals[cleaned, default: 0] += cost
                    }
                    continue
                }

                // Fallback only when a day has a single model label and one measured cost value.
                if let modelsUsed = entry.modelsUsed, modelsUsed.count == 1 {
                    let cleaned = modelsUsed[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { continue }
                    let cost = max(0, entry.costUSD ?? 0)
                    guard cost > 0 else { continue }
                    totals[cleaned, default: 0] += cost
                }
            }
        }

        return totals
            .map { DashboardModelSpend(modelName: $0.key, costUSD: $0.value) }
            .sorted { lhs, rhs in
                if lhs.costUSD == rhs.costUSD {
                    return lhs.modelName.localizedCaseInsensitiveCompare(rhs.modelName) == .orderedAscending
                }
                return lhs.costUSD > rhs.costUSD
            }
    }

    private func collectModelNames(days: Int, providers: [UsageProvider]) -> [String] {
        let ranking = self.makeModelSpendRanking(days: days, providers: providers)
        return ranking.map(\.modelName)
    }

    private func filteredRows(_ rows: [DashboardProviderRow]) -> [DashboardProviderRow] {
        guard let provider = self.selectedProviderFilter else { return rows }
        return rows.filter { $0.provider == provider }
    }

    private func normalizeFilterSelections() {
        if let selectedProvider,
           !self.providerFilterOptions.contains(selectedProvider)
        {
            self.selectedProvider = nil
        }

        if let selectedModel {
            let hasModel = self.availableModelOptions.contains(where: {
                $0.caseInsensitiveCompare(selectedModel) == .orderedSame
            })
            if !hasModel {
                self.selectedModel = nil
            }
        }
    }

    private static func measuredCostAndTokens(
        entry: CostUsageDailyReport.Entry,
        modelName: String?) -> (costUSD: Double, tokens: Int)?
    {
        guard let modelName else {
            let cost = max(0, entry.costUSD ?? 0)
            let tokens = max(0, entry.totalTokens ?? 0)
            if cost <= 0, tokens <= 0 { return nil }
            return (cost, tokens)
        }

        let target = Self.normalizedModelName(modelName)

        if let breakdowns = entry.modelBreakdowns, !breakdowns.isEmpty {
            let allowedModels = Self.normalizedModelNames(entry.modelsUsed)
            let matched = breakdowns.filter { breakdown in
                let normalized = Self.normalizedModelName(breakdown.modelName)
                if let allowedModels, !allowedModels.contains(normalized) {
                    return false
                }
                return normalized == target
            }
            guard !matched.isEmpty else { return nil }
            let cost = matched.reduce(0.0) { partial, breakdown in
                partial + max(0, breakdown.costUSD ?? 0)
            }
            guard cost > 0 else { return nil }
            // Per-model token split is unavailable in this payload; keep tokens at 0.
            return (cost, 0)
        }

        // Conservative fallback: only attribute full-day values when exactly one model is reported.
        if let modelsUsed = entry.modelsUsed, modelsUsed.count == 1 {
            let model = Self.normalizedModelName(modelsUsed[0])
            guard model == target else { return nil }
            let cost = max(0, entry.costUSD ?? 0)
            let tokens = max(0, entry.totalTokens ?? 0)
            if cost <= 0, tokens <= 0 { return nil }
            return (cost, tokens)
        }

        return nil
    }

    private static func normalizedModelName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedModelNames(_ raw: [String]?) -> Set<String>? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = Set(raw.map { self.normalizedModelName($0) }.filter { !$0.isEmpty })
        return normalized.isEmpty ? nil : normalized
    }

    private func sessionWindow(for provider: UsageProvider, snapshot: UsageSnapshot?) -> RateWindow? {
        guard let snapshot else { return nil }
        _ = provider
        return snapshot.primary ?? snapshot.secondary ?? snapshot.tertiary
    }

    private func weeklyWindow(for provider: UsageProvider, snapshot: UsageSnapshot?) -> RateWindow? {
        guard let snapshot else { return nil }
        return snapshot.switcherWeeklyWindow(for: provider, showUsed: false)
            ?? snapshot.secondary
            ?? snapshot.primary
    }

    private func pollRunningProvidersLoop() async {
        await self.refreshRunningProviders()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await self.refreshRunningProviders()
        }
    }

    private func refreshRunningProviders() async {
        let detected = await ProviderProcessProbe.runningProviders()
        if detected != self.runningCLIProviders {
            self.runningCLIProviders = detected
        }
    }

    private func refreshNow() {
        Task {
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await self.store.refresh(forceTokenUsage: true)
            }
            await self.refreshRunningProviders()
        }
    }

    private func openSettings() {
        NotificationCenter.default.post(
            name: .tokenbarOpenSettings,
            object: nil,
            userInfo: ["tab": PreferencesTab.general.rawValue])
    }

    private func openLicenseCheckout() {
        Task {
            await self.settings.startLicenseCheckout()
        }
    }

    private func openProviderDashboard(_ provider: UsageProvider) {
        let metadata = self.store.metadata(for: provider)
        let urlString: String? = if provider == .claude, self.store.isClaudeSubscription() {
            metadata.subscriptionDashboardURL ?? metadata.dashboardURL
        } else {
            metadata.dashboardURL
        }
        guard let urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openProviderStatusPage(_ provider: UsageProvider) {
        let metadata = self.store.metadata(for: provider)
        guard let urlString = metadata.statusPageURL ?? metadata.statusLinkURL,
              let url = URL(string: urlString)
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openCreditsPurchase() {
        let purchaseURL = Self.sanitizedCreditsPurchaseURL(self.store.openAIDashboard?.creditsPurchaseURL)
        let fallbackURL = self.store.metadata(for: .codex).dashboardURL
        guard let urlString = purchaseURL ?? fallbackURL,
              let url = URL(string: urlString)
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func usageTint(for remaining: Double?) -> Color {
        guard let remaining else { return DashboardTheme.textSecondary }
        if remaining < 20 {
            return DashboardTheme.negative
        }
        if remaining < 50 {
            return DashboardTheme.warning
        }
        if remaining < 80 {
            return DashboardTheme.positive.opacity(0.85)
        }
        return DashboardTheme.positive
    }

    private static func groupedIntegerString(_ value: Int) -> String {
        self.groupedIntegerFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func fullDateString(_ date: Date) -> String {
        self.fullDateFormatter.string(from: date)
    }

    private static func dayKeyToDate(_ key: String) -> Date? {
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
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    private static func minutesText(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hours = safeMinutes / 60
        let remainder = safeMinutes % 60
        if hours == 0 {
            return "\(remainder)m"
        }
        if remainder == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainder)m"
    }

    private static func planPricingBaseline(provider: UsageProvider, planText: String?) -> PlanPricingBaseline? {
        guard let planText else { return nil }
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

    private static func periodPlanSpend(monthlyUSD: Double, periodDays: Int, now: Date) -> Double {
        let daysInMonth = max(1, Calendar.current.range(of: .day, in: .month, for: now)?.count ?? 30)
        let daily = monthlyUSD / Double(daysInMonth)
        return daily * Double(max(1, periodDays))
    }

    private static func sanitizedCreditsPurchaseURL(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw) else { return nil }
        guard let host = url.host?.lowercased(), host.contains("chatgpt.com") else { return nil }
        let path = url.path.lowercased()
        let allowed = ["settings", "usage", "billing", "credits"]
        guard allowed.contains(where: { path.contains($0) }) else { return nil }
        return url.absoluteString
    }
}

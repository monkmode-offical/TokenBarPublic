import Foundation

public enum CostUsageError: LocalizedError, Sendable {
    case unsupportedProvider(UsageProvider)
    case timedOut(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProvider(provider):
            return "Cost summary is not supported for \(provider.rawValue)."
        case let .timedOut(seconds):
            if seconds >= 60, seconds % 60 == 0 {
                return "Cost refresh timed out after \(seconds / 60)m."
            }
            return "Cost refresh timed out after \(seconds)s."
        }
    }
}

public struct CostUsageFetcher: Sendable {
    public init() {}

    public func loadTokenSnapshot(
        provider: UsageProvider,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false) async throws -> CostUsageTokenSnapshot
    {
        guard provider == .codex || provider == .claude || provider == .vertexai else {
            throw CostUsageError.unsupportedProvider(provider)
        }

        let until = now
        // Rolling window: last 30 days (inclusive). Use -29 for inclusive boundaries.
        let since = Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now

        var options = CostUsageScanner.Options()
        if provider == .vertexai {
            options.claudeLogProviderFilter = allowVertexClaudeFallback ? .all : .vertexAIOnly
        } else if provider == .claude {
            options.claudeLogProviderFilter = .excludeVertexAI
        }
        if forceRefresh {
            options.refreshMinIntervalSeconds = 0
            options.forceRescan = true
        }

        let daily = Self.loadDailyReport(
            provider: provider,
            request: DailyReportRequest(
                since: since,
                until: until,
                now: now,
                options: options,
                allowVertexClaudeFallback: allowVertexClaudeFallback))

        var allTimeOptions = options
        allTimeOptions.cacheRoot = Self.allTimeCacheRoot(from: options.cacheRoot)
        let allTimeDaily = Self.loadDailyReport(
            provider: provider,
            request: DailyReportRequest(
                since: Date(timeIntervalSince1970: 0),
                until: until,
                now: now,
                options: allTimeOptions,
                allowVertexClaudeFallback: allowVertexClaudeFallback))
        let allTimeTotals = Self.reportTotals(from: allTimeDaily)

        return Self.tokenSnapshot(from: daily, allTimeTotals: allTimeTotals, now: now)
    }

    static func tokenSnapshot(from daily: CostUsageDailyReport, now: Date) -> CostUsageTokenSnapshot {
        self.tokenSnapshot(from: daily, allTimeTotals: nil, now: now)
    }

    private static func tokenSnapshot(
        from daily: CostUsageDailyReport,
        allTimeTotals: ReportTotals?,
        now: Date) -> CostUsageTokenSnapshot
    {
        // Pick the most recent day; break ties by cost/tokens to keep a stable "session" row.
        let currentDay = daily.data.max { lhs, rhs in
            let lDate = CostUsageDateParser.parse(lhs.date) ?? .distantPast
            let rDate = CostUsageDateParser.parse(rhs.date) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.date < rhs.date
        }
        // Prefer summary totals when present; fall back to summing daily entries.
        let totalFromSummary = daily.summary?.totalCostUSD
        let totalFromEntries = daily.data.compactMap(\.costUSD).reduce(0, +)
        let last30DaysCostUSD = totalFromSummary ?? (totalFromEntries > 0 ? totalFromEntries : nil)
        let totalTokensFromSummary = daily.summary?.totalTokens
        let totalTokensFromEntries = daily.data.compactMap(\.totalTokens).reduce(0, +)
        let last30DaysTokens = totalTokensFromSummary ?? (totalTokensFromEntries > 0 ? totalTokensFromEntries : nil)

        return CostUsageTokenSnapshot(
            sessionTokens: currentDay?.totalTokens,
            sessionCostUSD: currentDay?.costUSD,
            last30DaysTokens: last30DaysTokens,
            last30DaysCostUSD: last30DaysCostUSD,
            allTimeTokens: allTimeTotals?.tokens,
            allTimeCostUSD: allTimeTotals?.costUSD,
            allTimeSince: allTimeTotals?.since,
            daily: daily.data,
            updatedAt: now)
    }

    private struct ReportTotals {
        let tokens: Int?
        let costUSD: Double?
        let since: Date?
    }

    private struct DailyReportRequest {
        let since: Date
        let until: Date
        let now: Date
        let options: CostUsageScanner.Options
        let allowVertexClaudeFallback: Bool
    }

    private static func reportTotals(from report: CostUsageDailyReport) -> ReportTotals? {
        guard !report.data.isEmpty else { return nil }

        let totalCostFromSummary = report.summary?.totalCostUSD
        let totalCostFromEntries = report.data.compactMap(\.costUSD).reduce(0, +)
        let costUSD = totalCostFromSummary ?? (totalCostFromEntries > 0 ? totalCostFromEntries : nil)

        let totalTokensFromSummary = report.summary?.totalTokens
        let totalTokensFromEntries = report.data.compactMap(\.totalTokens).reduce(0, +)
        let tokens = totalTokensFromSummary ?? (totalTokensFromEntries > 0 ? totalTokensFromEntries : nil)

        let since = report.data
            .compactMap { CostUsageDateParser.parse($0.date) }
            .min()

        return ReportTotals(tokens: tokens, costUSD: costUSD, since: since)
    }

    private static func loadDailyReport(
        provider: UsageProvider,
        request: DailyReportRequest) -> CostUsageDailyReport
    {
        var daily = CostUsageScanner.loadDailyReport(
            provider: provider,
            since: request.since,
            until: request.until,
            now: request.now,
            options: request.options)

        if provider == .vertexai,
           !request.allowVertexClaudeFallback,
           request.options.claudeLogProviderFilter == .vertexAIOnly,
           daily.data.isEmpty
        {
            var fallback = request.options
            fallback.claudeLogProviderFilter = .all
            daily = CostUsageScanner.loadDailyReport(
                provider: provider,
                since: request.since,
                until: request.until,
                now: request.now,
                options: fallback)
        }
        return daily
    }

    private static func allTimeCacheRoot(from cacheRoot: URL?) -> URL {
        let base: URL
        if let cacheRoot {
            base = cacheRoot
        } else {
            let userCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            base = userCache.appendingPathComponent("TokenBar", isDirectory: true)
        }
        return base.appendingPathComponent("cost-usage-all-time", isDirectory: true)
    }

    static func selectCurrentSession(from sessions: [CostUsageSessionReport.Entry])
        -> CostUsageSessionReport.Entry?
    {
        if sessions.isEmpty { return nil }
        return sessions.max { lhs, rhs in
            let lDate = CostUsageDateParser.parse(lhs.lastActivity) ?? .distantPast
            let rDate = CostUsageDateParser.parse(rhs.lastActivity) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.session < rhs.session
        }
    }

    static func selectMostRecentMonth(from months: [CostUsageMonthlyReport.Entry])
        -> CostUsageMonthlyReport.Entry?
    {
        if months.isEmpty { return nil }
        return months.max { lhs, rhs in
            let lDate = CostUsageDateParser.parseMonth(lhs.month) ?? .distantPast
            let rDate = CostUsageDateParser.parseMonth(rhs.month) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.month < rhs.month
        }
    }
}

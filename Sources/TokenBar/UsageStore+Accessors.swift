import TokenBarCore
import Foundation

extension ProviderStatusIndicator {
    fileprivate var severityRank: Int {
        switch self {
        case .none: 0
        case .minor: 1
        case .maintenance: 2
        case .major: 3
        case .critical: 4
        case .unknown: 5
        }
    }

    static func maxSeverity(_ lhs: ProviderStatusIndicator, _ rhs: ProviderStatusIndicator)
        -> ProviderStatusIndicator
    {
        lhs.severityRank >= rhs.severityRank ? lhs : rhs
    }
}

extension UsageStore {
    func priorityWindow(for provider: UsageProvider) -> RateWindow? {
        guard let snapshot = self.snapshots[provider] else { return nil }
        return snapshot.secondary ?? snapshot.primary ?? snapshot.tertiary
    }

    func priorityRemainingPercent(for provider: UsageProvider) -> Double? {
        self.priorityWindow(for: provider)?.remainingPercent
    }

    func nextResetDate(for provider: UsageProvider) -> Date? {
        self.priorityWindow(for: provider)?.resetsAt
    }

    func timelineDaySeries(for provider: UsageProvider, days: Int = 56, now: Date = .init())
        -> [UsageTelemetryStore.DayPoint]
    {
        self.telemetryStore.daySeries(provider: provider, days: days, now: now)
    }

    func usageDeltaSnapshot(for provider: UsageProvider, now: Date = .init()) -> UsageTelemetryStore.DeltaSnapshot? {
        self.telemetryStore.deltaSnapshot(provider: provider, now: now)
    }

    func sessionTrackingSummary(for provider: UsageProvider, now: Date = .init())
        -> UsageTelemetryStore.SessionSummary?
    {
        self.telemetryStore.sessionSummary(provider: provider, now: now)
    }

    func recordTelemetry(provider: UsageProvider, snapshot: UsageSnapshot, now: Date = .init()) {
        self.telemetryStore.record(
            provider: provider,
            snapshot: snapshot,
            sessionTrackingEnabled: self.settings.sessionTrackingModeEnabled,
            now: now)
    }

    var codexSnapshot: UsageSnapshot? {
        self.snapshots[.codex]
    }

    var claudeSnapshot: UsageSnapshot? {
        self.snapshots[.claude]
    }

    var lastCodexError: String? {
        self.errors[.codex]
    }

    var lastClaudeError: String? {
        self.errors[.claude]
    }

    func error(for provider: UsageProvider) -> String? {
        self.errors[provider]
    }

    func status(for provider: UsageProvider) -> ProviderStatus? {
        guard self.statusChecksEnabled else { return nil }
        return self.statuses[provider]
    }

    func statusIndicator(for provider: UsageProvider) -> ProviderStatusIndicator {
        self.status(for: provider)?.indicator ?? .none
    }

    func usageAlertIndicator(for provider: UsageProvider) -> ProviderStatusIndicator {
        guard self.settings.usageAlertNotificationsEnabled else { return .none }
        guard let snapshot = self.snapshots[provider] else { return .none }
        let window = snapshot.primary ?? snapshot.secondary
        guard let usedPercent = window?.usedPercent else { return .none }
        guard let highestThreshold = self.settings.usageAlertThresholds
            .filter({ usedPercent >= Double($0) })
            .max()
        else {
            return .none
        }
        let thresholds = self.settings.usageAlertThresholds
        let top = thresholds.last ?? highestThreshold
        let mid = thresholds.dropLast().last ?? highestThreshold
        if highestThreshold >= top { return .critical }
        if highestThreshold >= mid { return .major }
        return .minor
    }

    func iconIndicator(for provider: UsageProvider) -> ProviderStatusIndicator {
        ProviderStatusIndicator.maxSeverity(
            self.statusIndicator(for: provider),
            self.usageAlertIndicator(for: provider))
    }

    func accountInfo() -> AccountInfo {
        self.codexFetcher.loadAccountInfo()
    }
}

import TokenBarCore
import Foundation

@MainActor
final class UsageTelemetryStore {
    struct DayPoint: Identifiable, Sendable {
        let date: Date
        let usedPercent: Double
        let cycleResetAt: Date?

        var id: String {
            String(Int(self.date.timeIntervalSince1970 / 86_400))
        }
    }

    struct DeltaSnapshot: Sendable {
        let todayDeltaPercent: Double?
        let cycleDeltaPercent: Double?
    }

    struct SessionSummary: Sendable {
        let providerTodayMinutes: Int
        let providerWeekMinutes: Int
        let totalWeekMinutes: Int
    }

    private struct PersistedState: Codable, Sendable {
        var samplesByProvider: [String: [Sample]] = [:]
        var sessionTrackersByProvider: [String: SessionTracker] = [:]
        var activeMinutesByDay: [String: [String: Int]] = [:]
    }

    private struct Sample: Codable, Sendable {
        let recordedAt: Date
        let cycleUsedPercent: Double
        let cycleResetAt: Date?
        let sessionUsedPercent: Double?
    }

    private struct SessionTracker: Codable, Sendable {
        let observedAt: Date
        let sessionUsedPercent: Double?
    }

    private struct CyclePeak {
        var peakUsedPercent: Double
        var lastObservedAt: Date
    }

    private static let retentionDays = 84
    private static let minimumSampleInterval: TimeInterval = 10 * 60
    private static let maximumActivityInterval: TimeInterval = 45 * 60

    private static let keyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let fileManager: FileManager
    private let calendar: Calendar
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var state: PersistedState

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.storageURL = Self.storageURL(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.state = Self.loadState(from: self.storageURL, decoder: decoder, fileManager: fileManager)
        self.prune(now: Date())
        self.persist()
    }

    func record(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        sessionTrackingEnabled: Bool,
        now: Date = .init())
    {
        self.recordTimelineSample(provider: provider, snapshot: snapshot, now: now)
        self.recordSessionActivity(
            provider: provider,
            snapshot: snapshot,
            enabled: sessionTrackingEnabled,
            now: now)
        self.prune(now: now)
        self.persist()
    }

    func daySeries(provider: UsageProvider, days: Int = 56, now: Date = .init()) -> [DayPoint] {
        let effectiveDays = max(1, days)
        guard let samples = self.state.samplesByProvider[provider.rawValue], !samples.isEmpty else {
            return []
        }
        let todayStart = self.calendar.startOfDay(for: now)
        let lowerBound = self.calendar.date(
            byAdding: .day,
            value: -(effectiveDays - 1),
            to: todayStart) ?? todayStart

        var latestByDay: [String: Sample] = [:]
        latestByDay.reserveCapacity(samples.count)
        for sample in samples {
            let key = Self.dayKey(for: sample.recordedAt)
            if let existing = latestByDay[key], existing.recordedAt >= sample.recordedAt {
                continue
            }
            latestByDay[key] = sample
        }

        return latestByDay
            .compactMap { key, sample in
                guard let day = Self.date(fromDayKey: key) else { return nil }
                guard day >= lowerBound else { return nil }
                return DayPoint(
                    date: day,
                    usedPercent: sample.cycleUsedPercent,
                    cycleResetAt: sample.cycleResetAt)
            }
            .sorted { lhs, rhs in lhs.date < rhs.date }
    }

    func deltaSnapshot(provider: UsageProvider, now: Date = .init()) -> DeltaSnapshot? {
        let daily = self.daySeries(provider: provider, days: 14, now: now)
        let todayKey = Self.dayKey(for: now)
        let yesterdayDate = self.calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayKey = Self.dayKey(for: yesterdayDate)

        let todayUsed = daily.first(where: { Self.dayKey(for: $0.date) == todayKey })?.usedPercent
        let yesterdayUsed = daily.first(where: { Self.dayKey(for: $0.date) == yesterdayKey })?.usedPercent
        let dayDelta: Double? = if let todayUsed, let yesterdayUsed {
            todayUsed - yesterdayUsed
        } else {
            nil
        }

        let cycleDelta = self.cyclePeakDelta(provider: provider)
        if dayDelta == nil, cycleDelta == nil { return nil }
        return DeltaSnapshot(todayDeltaPercent: dayDelta, cycleDeltaPercent: cycleDelta)
    }

    func sessionSummary(provider: UsageProvider, now: Date = .init()) -> SessionSummary? {
        let todayKey = Self.dayKey(for: now)
        let weekStart = self.calendar.date(byAdding: .day, value: -6, to: self.calendar.startOfDay(for: now))
            ?? self.calendar.startOfDay(for: now)

        var providerTodayMinutes = 0
        var providerWeekMinutes = 0
        var totalWeekMinutes = 0

        for (dayKey, providerMinutes) in self.state.activeMinutesByDay {
            guard let day = Self.date(fromDayKey: dayKey), day >= weekStart else { continue }
            let providerDayMinutes = providerMinutes[provider.rawValue] ?? 0
            providerWeekMinutes += providerDayMinutes
            totalWeekMinutes += providerMinutes.values.reduce(0, +)
            if dayKey == todayKey {
                providerTodayMinutes = providerDayMinutes
            }
        }

        if providerWeekMinutes == 0, totalWeekMinutes == 0 { return nil }
        return SessionSummary(
            providerTodayMinutes: providerTodayMinutes,
            providerWeekMinutes: providerWeekMinutes,
            totalWeekMinutes: totalWeekMinutes)
    }

    private func recordTimelineSample(provider: UsageProvider, snapshot: UsageSnapshot, now: Date) {
        guard let cycleWindow = Self.cycleWindow(from: snapshot) else { return }
        let cycleUsed = Self.clampedPercent(cycleWindow.usedPercent)
        let sessionUsed = Self.sessionWindow(from: snapshot).map { Self.clampedPercent($0.usedPercent) }
        let sample = Sample(
            recordedAt: now,
            cycleUsedPercent: cycleUsed,
            cycleResetAt: cycleWindow.resetsAt,
            sessionUsedPercent: sessionUsed)

        var samples = self.state.samplesByProvider[provider.rawValue] ?? []
        if let last = samples.last {
            let interval = now.timeIntervalSince(last.recordedAt)
            let resetChanged = last.cycleResetAt != sample.cycleResetAt
            let usageChanged = abs(last.cycleUsedPercent - sample.cycleUsedPercent) >= 2
            let shouldAppend = interval >= Self.minimumSampleInterval || resetChanged || usageChanged
            if shouldAppend {
                samples.append(sample)
            } else {
                samples[samples.count - 1] = sample
            }
        } else {
            samples.append(sample)
        }
        self.state.samplesByProvider[provider.rawValue] = samples
    }

    private func recordSessionActivity(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        enabled: Bool,
        now: Date)
    {
        let providerKey = provider.rawValue
        let currentSessionUsed = Self.sessionWindow(from: snapshot).map { Self.clampedPercent($0.usedPercent) }
        let previous = self.state.sessionTrackersByProvider[providerKey]

        if enabled,
           let previous,
           let previousUsed = previous.sessionUsedPercent,
           let currentSessionUsed,
           currentSessionUsed > previousUsed + 0.1
        {
            let elapsed = now.timeIntervalSince(previous.observedAt)
            if elapsed > 20, elapsed <= Self.maximumActivityInterval {
                let clampedMinutes = max(1, min(30, Int((elapsed / 60).rounded())))
                self.addActivityMinutes(
                    dayKey: Self.dayKey(for: now),
                    providerKey: providerKey,
                    minutes: clampedMinutes)
            }
        }

        self.state.sessionTrackersByProvider[providerKey] = SessionTracker(
            observedAt: now,
            sessionUsedPercent: currentSessionUsed)
    }

    private func addActivityMinutes(dayKey: String, providerKey: String, minutes: Int) {
        guard minutes > 0 else { return }
        var dayRecord = self.state.activeMinutesByDay[dayKey] ?? [:]
        dayRecord[providerKey, default: 0] += minutes
        self.state.activeMinutesByDay[dayKey] = dayRecord
    }

    private func cyclePeakDelta(provider: UsageProvider) -> Double? {
        guard let samples = self.state.samplesByProvider[provider.rawValue], !samples.isEmpty else { return nil }
        var cyclesByKey: [String: CyclePeak] = [:]
        cyclesByKey.reserveCapacity(samples.count)

        for sample in samples {
            guard let resetAt = sample.cycleResetAt else { continue }
            let key = Self.cycleKey(for: resetAt)
            if var existing = cyclesByKey[key] {
                existing.peakUsedPercent = max(existing.peakUsedPercent, sample.cycleUsedPercent)
                existing.lastObservedAt = max(existing.lastObservedAt, sample.recordedAt)
                cyclesByKey[key] = existing
            } else {
                cyclesByKey[key] = CyclePeak(
                    peakUsedPercent: sample.cycleUsedPercent,
                    lastObservedAt: sample.recordedAt)
            }
        }

        let orderedCycles = cyclesByKey.values.sorted { lhs, rhs in lhs.lastObservedAt < rhs.lastObservedAt }
        guard orderedCycles.count >= 2 else { return nil }
        let current = orderedCycles[orderedCycles.count - 1]
        let previous = orderedCycles[orderedCycles.count - 2]
        return current.peakUsedPercent - previous.peakUsedPercent
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)

        var trimmedSamplesByProvider: [String: [Sample]] = [:]
        for (provider, samples) in self.state.samplesByProvider {
            let trimmed = samples.filter { $0.recordedAt >= cutoff }
            if !trimmed.isEmpty {
                trimmedSamplesByProvider[provider] = trimmed
            }
        }
        self.state.samplesByProvider = trimmedSamplesByProvider

        var trimmedActivityByDay: [String: [String: Int]] = [:]
        for (dayKey, providerMinutes) in self.state.activeMinutesByDay {
            guard let dayDate = Self.date(fromDayKey: dayKey), dayDate >= self.calendar.startOfDay(for: cutoff) else {
                continue
            }
            let filteredProviderMinutes = providerMinutes.filter { _, minutes in minutes > 0 }
            if !filteredProviderMinutes.isEmpty {
                trimmedActivityByDay[dayKey] = filteredProviderMinutes
            }
        }
        self.state.activeMinutesByDay = trimmedActivityByDay
    }

    private func persist() {
        let directory = self.storageURL.deletingLastPathComponent()
        do {
            try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try self.encoder.encode(self.state)
            try data.write(to: self.storageURL, options: .atomic)
        } catch {
            // Keep telemetry best-effort and never interrupt menu/refresh flows.
        }
    }

    private static func loadState(
        from url: URL,
        decoder: JSONDecoder,
        fileManager: FileManager) -> PersistedState
    {
        guard fileManager.fileExists(atPath: url.path) else { return PersistedState() }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(PersistedState.self, from: data)
        else {
            return PersistedState()
        }
        return decoded
    }

    private static func storageURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("TokenBar", isDirectory: true)
        return directory.appendingPathComponent("usage-telemetry-v1.json", isDirectory: false)
    }

    private static func cycleWindow(from snapshot: UsageSnapshot) -> RateWindow? {
        snapshot.secondary ?? snapshot.primary ?? snapshot.tertiary
    }

    private static func sessionWindow(from snapshot: UsageSnapshot) -> RateWindow? {
        snapshot.primary ?? snapshot.secondary
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func dayKey(for date: Date) -> String {
        Self.keyDateFormatter.string(from: date)
    }

    private static func date(fromDayKey key: String) -> Date? {
        Self.keyDateFormatter.date(from: key)
    }

    private static func cycleKey(for date: Date) -> String {
        String(Int(date.timeIntervalSince1970 / 60))
    }
}

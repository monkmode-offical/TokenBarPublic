import Charts
import TokenBarCore
import SwiftUI

@MainActor
struct UsageTimelineChartMenuView: View {
    private struct WeekPoint: Identifiable {
        let weekStart: Date
        let averageUsedPercent: Double
        let dayCount: Int

        var id: String {
            "\(Int(self.weekStart.timeIntervalSince1970))"
        }
    }

    private struct CycleSummary {
        let currentPeak: Double
        let previousPeak: Double

        var delta: Double {
            self.currentPeak - self.previousPeak
        }
    }

    private struct Model {
        let weeklyPoints: [WeekPoint]
        let currentWeekAverage: Double?
        let previousWeekAverage: Double?
        let cycleSummary: CycleSummary?
        let barColor: Color
    }

    private let provider: UsageProvider
    private let points: [UsageTelemetryStore.DayPoint]
    private let width: CGFloat

    init(provider: UsageProvider, points: [UsageTelemetryStore.DayPoint], width: CGFloat) {
        self.provider = provider
        self.points = points
        self.width = width
    }

    var body: some View {
        let model = Self.makeModel(provider: self.provider, points: self.points)
        VStack(alignment: .leading, spacing: 10) {
            if model.weeklyPoints.isEmpty {
                Text("No timeline data yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(model.weeklyPoints) { point in
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value("Average used", point.averageUsedPercent))
                            .foregroundStyle(model.barColor)
                            .opacity(max(0.38, min(1, Double(point.dayCount) / 7)))
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: model.weeklyPoints.map(\.weekStart)) { value in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisTick().foregroundStyle(Color.clear)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
                .frame(height: 120)

                VStack(alignment: .leading, spacing: 2) {
                    if let currentWeekAverage = model.currentWeekAverage {
                        Text("This week: \(Self.percentText(currentWeekAverage)) avg used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let previousWeekAverage = model.previousWeekAverage {
                        let delta = (model.currentWeekAverage ?? previousWeekAverage) - previousWeekAverage
                        Text("Last week: \(Self.percentText(previousWeekAverage)) · \(Self.deltaText(delta))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let cycleSummary = model.cycleSummary {
                        Text("Reset cycle peak: \(Self.deltaText(cycleSummary.delta))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .leading)
    }

    private static func makeModel(provider: UsageProvider, points: [UsageTelemetryStore.DayPoint]) -> Model {
        let sortedPoints = points.sorted { lhs, rhs in lhs.date < rhs.date }
        let calendar = Calendar.current
        var groupedWeeks: [Date: [UsageTelemetryStore.DayPoint]] = [:]
        groupedWeeks.reserveCapacity(sortedPoints.count)

        for point in sortedPoints {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: point.date)?.start else { continue }
            groupedWeeks[weekStart, default: []].append(point)
        }

        let weeklyPoints = groupedWeeks
            .map { weekStart, points in
                let average = points.map(\.usedPercent).reduce(0, +) / Double(points.count)
                return WeekPoint(weekStart: weekStart, averageUsedPercent: average, dayCount: points.count)
            }
            .sorted { lhs, rhs in lhs.weekStart < rhs.weekStart }
            .suffix(8)

        let currentWeekAverage = weeklyPoints.last?.averageUsedPercent
        let previousWeekAverage: Double? = if weeklyPoints.count >= 2 {
            weeklyPoints[weeklyPoints.count - 2].averageUsedPercent
        } else {
            nil
        }

        let cycleSummary = Self.cycleSummary(from: sortedPoints)
        let brandingColor = ProviderDescriptorRegistry.descriptor(for: provider).branding.color
        let barColor = Color(red: brandingColor.red, green: brandingColor.green, blue: brandingColor.blue)

        return Model(
            weeklyPoints: Array(weeklyPoints),
            currentWeekAverage: currentWeekAverage,
            previousWeekAverage: previousWeekAverage,
            cycleSummary: cycleSummary,
            barColor: barColor)
    }

    private static func cycleSummary(from points: [UsageTelemetryStore.DayPoint]) -> CycleSummary? {
        struct CycleAccumulator {
            var peakUsedPercent: Double
            var lastObservedDay: Date
        }

        var byCycle: [String: CycleAccumulator] = [:]
        byCycle.reserveCapacity(points.count)
        for point in points {
            guard let resetAt = point.cycleResetAt else { continue }
            let cycleKey = String(Int(resetAt.timeIntervalSince1970 / 60))
            if var current = byCycle[cycleKey] {
                current.peakUsedPercent = max(current.peakUsedPercent, point.usedPercent)
                current.lastObservedDay = max(current.lastObservedDay, point.date)
                byCycle[cycleKey] = current
            } else {
                byCycle[cycleKey] = CycleAccumulator(
                    peakUsedPercent: point.usedPercent,
                    lastObservedDay: point.date)
            }
        }

        let ordered = byCycle.values.sorted { lhs, rhs in lhs.lastObservedDay < rhs.lastObservedDay }
        guard ordered.count >= 2 else { return nil }
        let current = ordered[ordered.count - 1]
        let previous = ordered[ordered.count - 2]
        return CycleSummary(currentPeak: current.peakUsedPercent, previousPeak: previous.peakUsedPercent)
    }

    private static func percentText(_ value: Double) -> String {
        String(format: "%.0f%%", min(100, max(0, value)))
    }

    private static func deltaText(_ value: Double) -> String {
        let rounded = Int(abs(value).rounded())
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(rounded)% vs baseline"
    }
}

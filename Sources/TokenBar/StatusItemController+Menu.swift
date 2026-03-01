import AppKit
import Observation
import QuartzCore
import SwiftUI
import TokenBarCore

extension ProviderSwitcherSelection {
    fileprivate var provider: UsageProvider? {
        switch self {
        case .overview:
            nil
        case let .provider(provider):
            provider
        }
    }
}

private struct OverviewMenuCardRowView: View {
    let model: UsageMenuCardView.Model
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.model.providerName)
                    .font(.system(size: 25, weight: .semibold, design: .default))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                Spacer(minLength: 6)
                if let plan = self.model.planText, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.35)
                        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(MenuHighlightStyle.pillBackground(self.isHighlighted))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(MenuHighlightStyle.cardBorder(self.isHighlighted), lineWidth: 0.5)
                                }
                        }
                }
            }

            HStack(alignment: .top, spacing: 9) {
                self.overviewMetricColumn(
                    title: "Now",
                    value: self.nowPercentValue,
                    subtitle: self.nowSubtitle)
                self.overviewMetricDivider
                self.overviewMetricColumn(
                    title: "Reset",
                    value: self.resetValue,
                    subtitle: "to reset")
                self.overviewMetricDivider
                self.overviewMetricColumn(
                    title: "Pace",
                    value: self.paceValue,
                    subtitle: "burn rate")
            }
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            self.overviewProgressBar

            if self.model.subtitleStyle == .error {
                Text(self.model.subtitleText)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: self.width, alignment: .leading)
    }

    private var primaryMetric: UsageMenuCardView.Model.Metric? {
        self.model.metrics.first
    }

    private var nowPercentValue: String {
        guard let metric = self.primaryMetric else { return "—" }
        if let remaining = Self.remainingDurationValue(for: metric) {
            return remaining
        }
        return "\(Int(metric.percent.rounded()))%"
    }

    private var nowSubtitle: String {
        guard let metric = self.primaryMetric else { return "No data" }
        if Self.remainingDurationValue(for: metric) != nil {
            return "remaining"
        }
        return metric.percentStyle == .left ? "remaining" : "used"
    }

    private var resetValue: String {
        let raw = self.model.metrics.compactMap(\.resetText).first
        return Self.compactReset(raw) ?? "—"
    }

    private var paceValue: String {
        guard let insight = self.model.insights.first(where: { $0.id == "burn-rate" || $0.id == "budget-mode" }) else {
            return "Normal"
        }
        switch insight.style {
        case .success:
            return "Safe"
        case .warning:
            return "Watch"
        case .danger:
            return "Risk"
        case .info:
            return "Normal"
        }
    }

    private func overviewMetricColumn(
        title: String,
        value: String,
        subtitle: String) -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.32)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .allowsTightening(true)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewMetricDivider: some View {
        Rectangle()
            .fill(MenuHighlightStyle.subtleDivider(self.isHighlighted))
            .frame(width: 0.6, height: 52)
            .padding(.top, 1)
    }

    private var overviewProgressBar: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 0)
            let percent = max(0, min(100, self.primaryMetric?.percent ?? 0))
            let fillWidth = width * (percent / 100)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MenuHighlightStyle.progressTrack(self.isHighlighted))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                MenuHighlightStyle.progressTint(self.isHighlighted, fallback: .white)
                                    .opacity(self.isHighlighted ? 0.88 : 0.82),
                                MenuHighlightStyle.progressTint(self.isHighlighted, fallback: .white)
                                    .opacity(self.isHighlighted ? 0.72 : 0.64),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing))
                    .frame(width: fillWidth)
                    .animation(.spring(response: 0.22, dampingFraction: 0.92), value: fillWidth)
            }
        }
        .frame(height: 2.5)
    }

    private static func remainingDurationValue(for metric: UsageMenuCardView.Model.Metric) -> String? {
        guard metric.percentStyle == .left,
              let windowMinutes = metric.windowMinutes,
              windowMinutes > 0
        else {
            return nil
        }
        let clampedPercent = max(0, min(100, metric.percent))
        let remainingMinutes = Int((Double(windowMinutes) * clampedPercent / 100).rounded())
        return self.compactDuration(minutes: remainingMinutes)
    }

    private static func compactDuration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        if clamped >= 24 * 60 {
            let days = max(1, Int((Double(clamped) / 1440).rounded()))
            return "\(days)d"
        }
        if clamped >= 60 {
            let hours = max(1, Int((Double(clamped) / 60).rounded()))
            return "\(hours)h"
        }
        return "\(clamped)m"
    }

    private static func compactReset(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized: String
        if trimmed.hasPrefix("Reset ") {
            normalized = String(trimmed.dropFirst("Reset ".count))
        } else if trimmed.hasPrefix("Resets ") {
            normalized = String(trimmed.dropFirst("Resets ".count))
        } else {
            normalized = trimmed
        }
        if normalized.lowercased().hasPrefix("in ") {
            return String(normalized.dropFirst(3))
        }
        return normalized
    }
}

// MARK: - NSMenu construction

extension StatusItemController {
    private static let menuCardBaseWidth: CGFloat = 320
    private static let maxOverviewProviders = SettingsStore.mergedOverviewProviderLimit
    private static let overviewRowIdentifierPrefix = "overviewRow-"
    private static let menuOpenRefreshDelay: Duration = .seconds(1.2)
    private static let runningProvidersCacheTTL: TimeInterval = 3
    private static let menuProviderRecentContextWindow: TimeInterval = 10 * 60
    private struct OpenAIWebMenuItems {
        let hasUsageBreakdown: Bool
        let hasCreditsHistory: Bool
        let hasCostHistory: Bool
    }

    private struct TokenAccountMenuDisplay {
        let provider: UsageProvider
        let accounts: [ProviderTokenAccount]
        let snapshots: [TokenAccountUsageSnapshot]
        let activeIndex: Int
        let showAll: Bool
        let showSwitcher: Bool
    }

    private func menuCardWidth(for providers: [UsageProvider], menu: NSMenu? = nil) -> CGFloat {
        _ = menu
        let count = max(1, providers.count)
        if count <= 1 { return max(Self.menuCardBaseWidth, 344) }
        if count <= 3 { return max(Self.menuCardBaseWidth, 352) }
        return max(Self.menuCardBaseWidth, 360)
    }

    private func configureMenuChrome(_ menu: NSMenu) {
        // Reduce wallpaper bleed-through so card spacing/typography reads cleaner.
        menu.appearance = NSAppearance(named: .darkAqua)
    }

    func makeMenu() -> NSMenu {
        guard self.shouldMergeIcons else {
            return self.makeMenu(for: nil)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        self.configureMenuChrome(menu)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if self.isHostedSubviewMenu(menu) {
            self.refreshHostedSubviewHeights(in: menu)
            if Self.menuRefreshEnabled, self.isOpenAIWebSubviewMenu(menu) {
                self.store.requestOpenAIDashboardRefreshIfStale(reason: "submenu open")
            }
            self.openMenus[ObjectIdentifier(menu)] = menu
            // Removed redundant async refresh - single pass is sufficient after initial layout
            return
        }

        _ = self.runningProvidersForMenu(forceRefresh: true)

        var provider: UsageProvider?
        if self.shouldMergeIcons {
            let resolvedProvider = self.resolvedMenuProvider()
            self.lastMenuProvider = resolvedProvider ?? .codex
            provider = resolvedProvider
        } else {
            if let menuProvider = self.menuProviders[ObjectIdentifier(menu)] {
                self.lastMenuProvider = menuProvider
                provider = menuProvider
            } else if menu === self.fallbackMenu {
                self.lastMenuProvider = self.store.enabledProviders().first ?? .codex
                provider = nil
            } else {
                let resolved = self.store.enabledProviders().first ?? .codex
                self.lastMenuProvider = resolved
                provider = resolved
            }
        }

        let didRefresh = self.menuNeedsRefresh(menu)
        if didRefresh {
            self.populateMenu(menu, provider: provider)
            self.markMenuFresh(menu)
            // Heights are already set during populateMenu, no need to remeasure
        }
        self.openMenus[ObjectIdentifier(menu)] = menu
        // Only schedule refresh after menu is registered as open - refreshNow is called async
        if Self.menuRefreshEnabled {
            self.scheduleOpenMenuRefresh(for: menu)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        let key = ObjectIdentifier(menu)

        self.openMenus.removeValue(forKey: key)
        self.menuRefreshTasks.removeValue(forKey: key)?.cancel()

        let isPersistentMenu = menu === self.mergedMenu ||
            menu === self.fallbackMenu ||
            self.providerMenus.values.contains { $0 === menu }
        if !isPersistentMenu {
            self.menuProviders.removeValue(forKey: key)
            self.menuVersions.removeValue(forKey: key)
        }
        for menuItem in menu.items {
            (menuItem.view as? MenuCardHighlighting)?.setHighlighted(false)
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            let highlighted = menuItem == item && menuItem.isEnabled
            (menuItem.view as? MenuCardHighlighting)?.setHighlighted(highlighted)
        }
    }

    private func populateMenu(_ menu: NSMenu, provider: UsageProvider?) {
        let enabledProviders = self.store.enabledProviders()
        let runningProviders = self.runningProvidersForMenu()
        let displayedProviders = self.displayedProviders(
            from: enabledProviders,
            runningProviders: runningProviders)
        let includesOverview = self.includesOverviewTab(enabledProviders: displayedProviders)
        let shouldShowSwitcher = self.shouldMergeIcons &&
            (includesOverview || !displayedProviders.isEmpty)
        let switcherSelection = shouldShowSwitcher
            ? self.resolvedSwitcherSelection(
                enabledProviders: displayedProviders,
                includesOverview: includesOverview)
            : nil
        let isOverviewSelected = switcherSelection == .overview
        let selectedProvider = if isOverviewSelected {
            self.resolvedMenuProvider(enabledProviders: displayedProviders, runningProviders: runningProviders)
        } else {
            switcherSelection?.provider ?? provider
        }
        let menuWidth = self.menuCardWidth(for: displayedProviders, menu: menu)
        let currentProvider = selectedProvider ?? displayedProviders.first ?? enabledProviders.first ?? .codex
        let tokenAccountDisplay = isOverviewSelected ? nil : self.tokenAccountMenuDisplay(for: currentProvider)
        let showAllTokenAccounts = tokenAccountDisplay?.showAll ?? false
        let openAIContext = self.openAIWebContext(
            currentProvider: currentProvider,
            showAllTokenAccounts: showAllTokenAccounts)

        let hasTokenAccountSwitcher = menu.items.contains { $0.view is TokenAccountSwitcherView }
        let switcherProvidersMatch = displayedProviders == self.lastSwitcherProviders
        let switcherUsageBarsShowUsedMatch = self.settings.usageBarsShowUsed == self.lastSwitcherUsageBarsShowUsed
        let switcherSelectionMatches = switcherSelection == self.lastMergedSwitcherSelection
        let switcherOverviewAvailabilityMatches = includesOverview == self.lastSwitcherIncludesOverview
        let canSmartUpdate = self.shouldMergeIcons &&
            displayedProviders.count > 1 &&
            !isOverviewSelected &&
            switcherProvidersMatch &&
            switcherUsageBarsShowUsedMatch &&
            switcherSelectionMatches &&
            switcherOverviewAvailabilityMatches &&
            tokenAccountDisplay == nil &&
            !hasTokenAccountSwitcher &&
            !menu.items.isEmpty &&
            (menu.items.first?.view is ProviderSwitcherView ||
                menu.items.first?.view is PagedProviderSwitcherView)

        if canSmartUpdate {
            self.updateMenuContent(
                menu,
                provider: selectedProvider,
                currentProvider: currentProvider,
                menuWidth: menuWidth,
                openAIContext: openAIContext)
            return
        }

        menu.removeAllItems()

        let descriptor = MenuDescriptor.build(
            provider: selectedProvider,
            store: self.store,
            settings: self.settings,
            account: self.account,
            updateReady: self.updater.updateStatus.isUpdateReady,
            includeContextualActions: !isOverviewSelected)

        self.addProviderSwitcherIfNeeded(
            to: menu,
            enabledProviders: displayedProviders,
            includesOverview: includesOverview,
            selection: switcherSelection ?? .provider(currentProvider))
        // Track which providers the switcher was built with for smart update detection
        if shouldShowSwitcher {
            self.lastSwitcherProviders = displayedProviders
            self.lastSwitcherUsageBarsShowUsed = self.settings.usageBarsShowUsed
            self.lastMergedSwitcherSelection = switcherSelection
            self.lastSwitcherIncludesOverview = includesOverview
        }
        self.addTokenAccountSwitcherIfNeeded(to: menu, display: tokenAccountDisplay)
        let menuContext = MenuCardContext(
            currentProvider: currentProvider,
            selectedProvider: selectedProvider,
            menuWidth: menuWidth,
            tokenAccountDisplay: tokenAccountDisplay,
            openAIContext: openAIContext)
        if isOverviewSelected {
            if self.addOverviewRows(
                to: menu,
                enabledProviders: displayedProviders,
                menuWidth: menuWidth)
            {
            } else {
                self.addOverviewEmptyState(to: menu, enabledProviders: displayedProviders)
            }
        } else {
            let addedOpenAIWebItems = self.addMenuCards(to: menu, context: menuContext)
            self.addOpenAIWebItemsIfNeeded(
                to: menu,
                currentProvider: currentProvider,
                context: openAIContext,
                addedOpenAIWebItems: addedOpenAIWebItems)
        }
        self.addActionableSections(descriptor.sections, to: menu)
    }

    /// Smart update: only rebuild content sections when switching providers (keep the switcher intact).
    private func updateMenuContent(
        _ menu: NSMenu,
        provider: UsageProvider?,
        currentProvider: UsageProvider,
        menuWidth: CGFloat,
        openAIContext: OpenAIWebContext)
    {
        // Batch menu updates to prevent visual flickering during provider switch.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        var contentStartIndex = 0
        if menu.items.first?.view is ProviderSwitcherView ||
            menu.items.first?.view is PagedProviderSwitcherView
        {
            contentStartIndex = 2
        }
        if menu.items.count > contentStartIndex,
           menu.items[contentStartIndex].view is TokenAccountSwitcherView
        {
            contentStartIndex += 2
        }
        while menu.items.count > contentStartIndex {
            menu.removeItem(at: contentStartIndex)
        }

        let descriptor = MenuDescriptor.build(
            provider: provider,
            store: self.store,
            settings: self.settings,
            account: self.account,
            updateReady: self.updater.updateStatus.isUpdateReady)

        let menuContext = MenuCardContext(
            currentProvider: currentProvider,
            selectedProvider: provider,
            menuWidth: menuWidth,
            tokenAccountDisplay: nil,
            openAIContext: openAIContext)
        let addedOpenAIWebItems = self.addMenuCards(to: menu, context: menuContext)
        self.addOpenAIWebItemsIfNeeded(
            to: menu,
            currentProvider: currentProvider,
            context: openAIContext,
            addedOpenAIWebItems: addedOpenAIWebItems)
        self.addActionableSections(descriptor.sections, to: menu)
    }

    private func appendSeparatorIfNeeded(to menu: NSMenu) {
        if menu.items.last?.isSeparatorItem == false,
           (menu.items.last?.representedObject as? String) != "insetDivider"
        {
            let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
            self.addInsetDivider(
                to: menu,
                width: width,
                topSpacing: 4,
                bottomSpacing: 4)
        }
    }

    private func addInsetDivider(
        to menu: NSMenu,
        width: CGFloat,
        topSpacing: CGFloat,
        bottomSpacing: CGFloat,
        horizontalInset: CGFloat = 10,
        maxLineWidth: CGFloat? = nil,
        showsLine: Bool = false)
    {
        let totalHeight = max(2, topSpacing + bottomSpacing + (showsLine ? 2 : 0))
        let safeInset = max(0, horizontalInset)
        let availableLineWidth = max(1, width - safeInset * 2)
        let lineWidth = max(1, min(maxLineWidth ?? availableLineWidth, availableLineWidth))
        let lineX = floor((width - lineWidth) / 2)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        container.wantsLayer = false

        if showsLine {
            let line = NSView(
                frame: NSRect(
                    x: lineX,
                    y: floor((totalHeight - 0.7) / 2),
                    width: lineWidth,
                    height: 0.7))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            line.layer?.cornerRadius = 0.35
            container.addSubview(line)
        }

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        item.representedObject = "insetDivider"
        menu.addItem(item)
    }

    private struct OpenAIWebContext {
        let hasUsageBreakdown: Bool
        let hasCreditsHistory: Bool
        let hasCostHistory: Bool
        let hasOpenAIWebMenuItems: Bool
    }

    private struct MenuCardContext {
        let currentProvider: UsageProvider
        let selectedProvider: UsageProvider?
        let menuWidth: CGFloat
        let tokenAccountDisplay: TokenAccountMenuDisplay?
        let openAIContext: OpenAIWebContext
    }

    private func openAIWebContext(
        currentProvider: UsageProvider,
        showAllTokenAccounts: Bool) -> OpenAIWebContext
    {
        let dashboard = self.store.openAIDashboard
        let openAIWebEligible = currentProvider == .codex &&
            self.store.openAIDashboardRequiresLogin == false &&
            dashboard != nil
        let hasCreditsHistory = openAIWebEligible && !(dashboard?.dailyBreakdown ?? []).isEmpty
        let hasUsageBreakdown = openAIWebEligible && !(dashboard?.usageBreakdown ?? []).isEmpty
        let hasCostHistory = self.settings.isCostUsageEffectivelyEnabled(for: currentProvider) &&
            (self.store.tokenSnapshot(for: currentProvider)?.daily.isEmpty == false)
        let hasOpenAIWebMenuItems = !showAllTokenAccounts &&
            (hasCreditsHistory || hasUsageBreakdown || hasCostHistory)
        return OpenAIWebContext(
            hasUsageBreakdown: hasUsageBreakdown,
            hasCreditsHistory: hasCreditsHistory,
            hasCostHistory: hasCostHistory,
            hasOpenAIWebMenuItems: hasOpenAIWebMenuItems)
    }

    private func addProviderSwitcherIfNeeded(
        to menu: NSMenu,
        enabledProviders: [UsageProvider],
        includesOverview: Bool,
        selection: ProviderSwitcherSelection)
    {
        guard self.shouldMergeIcons else { return }
        guard includesOverview || !enabledProviders.isEmpty else { return }
        let switcherItem = self.makeProviderSwitcherItem(
            providers: enabledProviders,
            includesOverview: includesOverview,
            selected: selection,
            menu: menu)
        menu.addItem(switcherItem)
        let width = self.menuCardWidth(for: enabledProviders, menu: menu)
        if selection == .overview {
            self.addInsetDivider(
                to: menu,
                width: width,
                topSpacing: 4,
                bottomSpacing: 4)
            return
        }
        self.addInsetDivider(
            to: menu,
            width: width,
            topSpacing: 4,
            bottomSpacing: 4)
    }

    private func addTokenAccountSwitcherIfNeeded(to menu: NSMenu, display: TokenAccountMenuDisplay?) {
        guard let display, display.showSwitcher else { return }
        let switcherItem = self.makeTokenAccountSwitcherItem(display: display, menu: menu)
        menu.addItem(switcherItem)
        let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
        self.addInsetDivider(
            to: menu,
            width: width,
            topSpacing: 4,
            bottomSpacing: 4)
    }

    @discardableResult
    private func addOverviewRows(
        to menu: NSMenu,
        enabledProviders: [UsageProvider],
        menuWidth: CGFloat) -> Bool
    {
        let overviewProviders = self.settings.reconcileMergedOverviewSelectedProviders(
            activeProviders: enabledProviders)
        let orderedOverviewProviders = self.sortedOverviewProviders(overviewProviders)
        let rows: [(provider: UsageProvider, model: UsageMenuCardView.Model)] = orderedOverviewProviders
            .compactMap { provider in
                guard let model = self.menuCardModel(for: provider) else { return nil }
                return (provider: provider, model: model)
            }
        guard !rows.isEmpty else { return false }

        for row in rows {
            let identifier = "\(Self.overviewRowIdentifierPrefix)\(row.provider.rawValue)"
            let item = self.makeMenuCardItem(
                OverviewMenuCardRowView(model: row.model, width: menuWidth),
                id: identifier,
                width: menuWidth,
                cardHorizontalInset: 8,
                cardVerticalInset: 6,
                cardShadow: false,
                onClick: { [weak self, weak menu] in
                    guard let self, let menu else { return }
                    self.selectOverviewProvider(row.provider, menu: menu)
                })
            // Keep menu item action wired for keyboard activation and accessibility action paths.
            item.target = self
            item.action = #selector(self.selectOverviewProvider(_:))
            menu.addItem(item)
        }
        return true
    }

    private struct OverviewSortMetrics {
        let remainingPercent: Double?
        let resetAt: Date?
        let hasIssue: Bool
    }

    private func sortedOverviewProviders(_ providers: [UsageProvider]) -> [UsageProvider] {
        guard providers.count > 1 else { return providers }
        let mode = self.settings.overviewPrioritySortMode
        if mode == .providerOrder { return providers }

        let fallbackOrder = Dictionary(uniqueKeysWithValues: providers.enumerated().map { ($0.element, $0.offset) })
        let metricsByProvider = Dictionary(uniqueKeysWithValues: providers
            .map { ($0, self.overviewSortMetrics(for: $0)) })

        func fallbackRank(_ provider: UsageProvider) -> Int {
            fallbackOrder[provider] ?? Int.max
        }

        func compareMostConstrained(_ lhs: UsageProvider, _ rhs: UsageProvider) -> Bool {
            let lhsMetrics = metricsByProvider[lhs]!
            let rhsMetrics = metricsByProvider[rhs]!
            let lhsRemaining = lhsMetrics.remainingPercent ?? 101
            let rhsRemaining = rhsMetrics.remainingPercent ?? 101
            if lhsRemaining != rhsRemaining { return lhsRemaining < rhsRemaining }

            let lhsReset = lhsMetrics.resetAt?.timeIntervalSince1970 ?? .infinity
            let rhsReset = rhsMetrics.resetAt?.timeIntervalSince1970 ?? .infinity
            if lhsReset != rhsReset { return lhsReset < rhsReset }
            return fallbackRank(lhs) < fallbackRank(rhs)
        }

        func compareBestAvailable(_ lhs: UsageProvider, _ rhs: UsageProvider) -> Bool {
            let lhsMetrics = metricsByProvider[lhs]!
            let rhsMetrics = metricsByProvider[rhs]!
            if lhsMetrics.hasIssue != rhsMetrics.hasIssue {
                return rhsMetrics.hasIssue
            }
            let lhsRemaining = lhsMetrics.remainingPercent ?? -1
            let rhsRemaining = rhsMetrics.remainingPercent ?? -1
            if lhsRemaining != rhsRemaining { return lhsRemaining > rhsRemaining }

            let lhsReset = lhsMetrics.resetAt?.timeIntervalSince1970 ?? .infinity
            let rhsReset = rhsMetrics.resetAt?.timeIntervalSince1970 ?? .infinity
            if lhsReset != rhsReset { return lhsReset > rhsReset }
            return fallbackRank(lhs) < fallbackRank(rhs)
        }

        func compareNextReset(_ lhs: UsageProvider, _ rhs: UsageProvider) -> Bool {
            let lhsMetrics = metricsByProvider[lhs]!
            let rhsMetrics = metricsByProvider[rhs]!
            let lhsReset = lhsMetrics.resetAt?.timeIntervalSince1970 ?? .infinity
            let rhsReset = rhsMetrics.resetAt?.timeIntervalSince1970 ?? .infinity
            if lhsReset != rhsReset { return lhsReset < rhsReset }

            let lhsRemaining = lhsMetrics.remainingPercent ?? 101
            let rhsRemaining = rhsMetrics.remainingPercent ?? 101
            if lhsRemaining != rhsRemaining { return lhsRemaining < rhsRemaining }
            return fallbackRank(lhs) < fallbackRank(rhs)
        }

        switch mode {
        case .providerOrder:
            return providers
        case .mostConstrained:
            return providers.sorted(by: compareMostConstrained)
        case .bestAvailable:
            return providers.sorted(by: compareBestAvailable)
        case .nextResetSoonest:
            return providers.sorted(by: compareNextReset)
        }
    }

    private func overviewSortMetrics(for provider: UsageProvider) -> OverviewSortMetrics {
        let remaining = self.store.priorityRemainingPercent(for: provider)
        let resetAt = self.store.nextResetDate(for: provider)
        let hasIssue = self.store.iconIndicator(for: provider).hasIssue
        return OverviewSortMetrics(remainingPercent: remaining, resetAt: resetAt, hasIssue: hasIssue)
    }

    private func addOverviewEmptyState(to menu: NSMenu, enabledProviders: [UsageProvider]) {
        let resolvedProviders = self.settings.resolvedMergedOverviewProviders(
            activeProviders: enabledProviders,
            maxVisibleProviders: Self.maxOverviewProviders)
        let message = if resolvedProviders.isEmpty {
            "No providers selected for Overview."
        } else {
            "No overview data available."
        }
        let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.representedObject = "overviewEmptyState"
        menu.addItem(item)
    }

    private func addMenuCards(to menu: NSMenu, context: MenuCardContext) -> Bool {
        if let tokenAccountDisplay = context.tokenAccountDisplay, tokenAccountDisplay.showAll {
            let accountSnapshots = tokenAccountDisplay.snapshots
            let cards = accountSnapshots.isEmpty
                ? []
                : accountSnapshots.compactMap { accountSnapshot in
                    self.menuCardModel(
                        for: context.currentProvider,
                        snapshotOverride: accountSnapshot.snapshot,
                        errorOverride: accountSnapshot.error)
                }
            if cards.isEmpty, let model = self.menuCardModel(for: context.selectedProvider) {
                menu.addItem(self.makeMenuCardItem(
                    UsageMenuCardView(model: model, width: context.menuWidth),
                    id: "menuCard",
                    width: context.menuWidth))
                self.addInsetDivider(
                    to: menu,
                    width: context.menuWidth,
                    topSpacing: 4,
                    bottomSpacing: 4)
            } else {
                for (index, model) in cards.enumerated() {
                    menu.addItem(self.makeMenuCardItem(
                        UsageMenuCardView(model: model, width: context.menuWidth),
                        id: "menuCard-\(index)",
                        width: context.menuWidth))
                    if index < cards.count - 1 {
                        self.addInsetDivider(
                            to: menu,
                            width: context.menuWidth,
                            topSpacing: 4,
                            bottomSpacing: 4)
                    }
                }
                if !cards.isEmpty {
                    self.addInsetDivider(
                        to: menu,
                        width: context.menuWidth,
                        topSpacing: 4,
                        bottomSpacing: 4)
                }
            }
            return false
        }

        guard let model = self.menuCardModel(for: context.selectedProvider) else { return false }
        if context.openAIContext.hasOpenAIWebMenuItems {
            let webItems = OpenAIWebMenuItems(
                hasUsageBreakdown: context.openAIContext.hasUsageBreakdown,
                hasCreditsHistory: context.openAIContext.hasCreditsHistory,
                hasCostHistory: context.openAIContext.hasCostHistory)
            self.addMenuCardSections(
                to: menu,
                model: model,
                provider: context.currentProvider,
                width: context.menuWidth,
                webItems: webItems)
            return false
        }

        menu.addItem(self.makeMenuCardItem(
            UsageMenuCardView(model: model, width: context.menuWidth),
            id: "menuCard",
            width: context.menuWidth))
        if context.currentProvider == .codex, model.creditsText != nil {
            menu.addItem(self.makeBuyCreditsItem())
        }
        self.addInsetDivider(
            to: menu,
            width: context.menuWidth,
            topSpacing: 4,
            bottomSpacing: 4)
        return false
    }

    private func addOpenAIWebItemsIfNeeded(
        to menu: NSMenu,
        currentProvider: UsageProvider,
        context: OpenAIWebContext,
        addedOpenAIWebItems: Bool)
    {
        guard context.hasOpenAIWebMenuItems else { return }
        var didAddAny = addedOpenAIWebItems
        if !addedOpenAIWebItems {
            // Only show these when we actually have additional data.
            if context.hasUsageBreakdown {
                if self.addUsageBreakdownSubmenu(to: menu) {
                    didAddAny = true
                }
            }
            if context.hasCreditsHistory {
                if self.addCreditsHistorySubmenu(to: menu) {
                    didAddAny = true
                }
            }
            let hasInlineCostHistory = menu.items.contains { item in
                (item.representedObject as? String) == "menuCardCost"
            }
            if context.hasCostHistory, !hasInlineCostHistory {
                if self.addCostHistorySubmenu(to: menu, provider: currentProvider) {
                    didAddAny = true
                }
            }
        }
        guard didAddAny else { return }
        let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
        self.addInsetDivider(
            to: menu,
            width: width,
            topSpacing: 4,
            bottomSpacing: 4)
    }

    private func addActionableSections(_ sections: [MenuDescriptor.Section], to menu: NSMenu) {
        let actionableSections = sections.filter { section in
            section.entries.contains { entry in
                if case .action = entry { return true }
                return false
            }
        }
        for (index, section) in actionableSections.enumerated() {
            for entry in section.entries {
                switch entry {
                case let .text(text, style):
                    let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    if style == .headline {
                        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
                        item.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
                    } else if style == .secondary {
                        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                        item.attributedTitle = NSAttributedString(
                            string: text,
                            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
                    }
                    menu.addItem(item)
                case let .action(title, action):
                    let (selector, represented) = self.selector(for: action)
                    let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                    item.target = self
                    item.representedObject = represented
                    if let iconName = action.systemImageName,
                       let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                    {
                        image.isTemplate = true
                        image.size = NSSize(width: 16, height: 16)
                        item.image = image
                    }
                    if case let .switchAccount(targetProvider) = action,
                       let subtitle = self.switchAccountSubtitle(for: targetProvider)
                    {
                        item.isEnabled = false
                        self.applySubtitle(subtitle, to: item, title: title)
                    }
                    menu.addItem(item)
                case .divider:
                    let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
                    self.addInsetDivider(
                        to: menu,
                        width: width,
                        topSpacing: 4,
                        bottomSpacing: 4)
                }
            }
            if index < actionableSections.count - 1 {
                let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
                self.addInsetDivider(
                    to: menu,
                    width: width,
                    topSpacing: 4,
                    bottomSpacing: 4)
            }
        }
    }

    func makeMenu(for provider: UsageProvider?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        self.configureMenuChrome(menu)
        if let provider {
            self.menuProviders[ObjectIdentifier(menu)] = provider
        }
        return menu
    }

    private func makeProviderSwitcherItem(
        providers: [UsageProvider],
        includesOverview: Bool,
        selected: ProviderSwitcherSelection,
        menu: NSMenu) -> NSMenuItem
    {
        let menuWidth = self.menuCardWidth(for: providers, menu: menu)
        let horizontalInset: CGFloat = 8
        let view = PagedProviderSwitcherView(
            providers: providers,
            selected: selected,
            includesOverview: includesOverview,
            width: max(1, menuWidth - horizontalInset * 2),
            showsIcons: self.settings.switcherShowsIcons,
            iconProvider: { [weak self] provider in
                self?.switcherIcon(for: provider) ?? NSImage()
            },
            weeklyRemainingProvider: { [weak self] provider in
                self?.switcherWeeklyRemaining(for: provider)
            },
            onSelect: { [weak self, weak menu] selection in
                guard let self, let menu else { return }
                switch selection {
                case .overview:
                    self.settings.mergedMenuLastSelectedWasOverview = true
                    self.lastMergedSwitcherSelection = .overview
                    let provider = self.resolvedMenuProvider()
                    self.lastMenuProvider = provider ?? .codex
                    self.populateMenu(menu, provider: provider)
                case let .provider(provider):
                    self.settings.mergedMenuLastSelectedWasOverview = false
                    self.lastMergedSwitcherSelection = .provider(provider)
                    self.selectedMenuProvider = provider
                    self.lastMenuProvider = provider
                    self.populateMenu(menu, provider: provider)
                }
                self.markMenuFresh(menu)
                self.applyIcon(phase: nil)
            })
        let containerHeight = max(50, view.intrinsicContentSize.height)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: containerHeight))
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
    }

    private func makeTokenAccountSwitcherItem(
        display: TokenAccountMenuDisplay,
        menu: NSMenu) -> NSMenuItem
    {
        let view = TokenAccountSwitcherView(
            accounts: display.accounts,
            selectedIndex: display.activeIndex,
            width: self.menuCardWidth(for: self.store.enabledProviders(), menu: menu),
            onSelect: { [weak self, weak menu] index in
                guard let self, let menu else { return }
                self.settings.setActiveTokenAccountIndex(index, for: display.provider)
                Task { @MainActor in
                    await ProviderInteractionContext.$current.withValue(.userInitiated) {
                        await self.store.refresh()
                    }
                }
                self.populateMenu(menu, provider: display.provider)
                self.markMenuFresh(menu)
                self.applyIcon(phase: nil)
            })
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    private func resolvedMenuProvider(enabledProviders: [UsageProvider]? = nil) -> UsageProvider? {
        let sourceProviders = enabledProviders ?? self.store.enabledProviders()
        let displayed = self.displayedProviders(from: sourceProviders)
        if displayed.isEmpty { return sourceProviders.first ?? .codex }
        if let selected = self.selectedMenuProvider, displayed.contains(selected) {
            return selected
        }
        return displayed.first
    }

    private func resolvedMenuProvider(
        enabledProviders: [UsageProvider]? = nil,
        runningProviders: Set<UsageProvider>) -> UsageProvider?
    {
        let sourceProviders = enabledProviders ?? self.store.enabledProviders()
        let displayed = self.displayedProviders(from: sourceProviders, runningProviders: runningProviders)
        if displayed.isEmpty { return sourceProviders.first ?? .codex }
        if let selected = self.selectedMenuProvider, displayed.contains(selected) {
            return selected
        }
        return displayed.first
    }

    private func displayedProviders(
        from enabledProviders: [UsageProvider],
        runningProviders: Set<UsageProvider>? = nil) -> [UsageProvider]
    {
        guard !enabledProviders.isEmpty else { return [] }
        let activeRunningProviders = runningProviders ?? self.runningProvidersForMenu()
        let liveProviders = enabledProviders.filter { activeRunningProviders.contains($0) }
        if !liveProviders.isEmpty {
            return liveProviders
        }

        if let selected = self.selectedMenuProvider, enabledProviders.contains(selected) {
            return [selected]
        }
        if let lastProvider = self.lastMenuProvider, enabledProviders.contains(lastProvider) {
            return [lastProvider]
        }
        guard enabledProviders.count > 1 else { return enabledProviders }

        let recentProviders = Set(enabledProviders.filter {
            self.hasRecentProviderActivity($0, maxAge: Self.menuProviderRecentContextWindow)
        })

        let recentOnly = enabledProviders.filter { recentProviders.contains($0) }
        if !recentOnly.isEmpty {
            return recentOnly
        }
        return [enabledProviders[0]]
    }

    private func includesOverviewTab(enabledProviders: [UsageProvider]) -> Bool {
        !self.settings.resolvedMergedOverviewProviders(
            activeProviders: enabledProviders,
            maxVisibleProviders: Self.maxOverviewProviders).isEmpty
    }

    private func runningProvidersForMenu(forceRefresh: Bool = false) -> Set<UsageProvider> {
        let now = Date()
        let cacheIsFresh = now.timeIntervalSince(self.runningProvidersCacheUpdatedAt) <= Self.runningProvidersCacheTTL
        if forceRefresh || !cacheIsFresh {
            self.runningProvidersCache = ProviderProcessProbe.runningProvidersNow()
            self.runningProvidersCacheUpdatedAt = now
        }
        return self.runningProvidersCache
    }

    private func hasRecentProviderActivity(
        _ provider: UsageProvider,
        maxAge: TimeInterval,
        now: Date = Date()) -> Bool
    {
        let snapshot = self.store.snapshot(for: provider)
        let tokenSnapshot = self.store.tokenSnapshot(for: provider)

        let latestUpdate: Date? = switch (snapshot?.updatedAt, tokenSnapshot?.updatedAt) {
        case let (left?, right?):
            max(left, right)
        case let (left?, nil):
            left
        case let (nil, right?):
            right
        case (nil, nil):
            nil
        }

        guard let latestUpdate else { return false }
        guard now.timeIntervalSince(latestUpdate) <= maxAge else { return false }

        if let tokenSnapshot {
            let hasSessionSignal = (tokenSnapshot.sessionCostUSD ?? 0) > 0
                || (tokenSnapshot.sessionTokens ?? 0) > 0
            if hasSessionSignal || self.hasTodayTokenSignal(tokenSnapshot, now: now) {
                return true
            }
        }

        if let snapshot {
            let windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary]
                .compactMap(\.self)
            let hasStrongUsageSignal = windows.contains { $0.usedPercent > 3 || $0.remainingPercent < 97 }
            if hasStrongUsageSignal {
                return true
            }
        }

        return false
    }

    private func hasTodayTokenSignal(_ tokenSnapshot: CostUsageTokenSnapshot, now: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for entry in tokenSnapshot.daily {
            guard let day = Self.dateFromDayKey(entry.date, calendar: calendar) else { continue }
            guard day == today else { continue }
            if (entry.costUSD ?? 0) > 0 || (entry.totalTokens ?? 0) > 0 {
                return true
            }
        }
        return false
    }

    private static func dateFromDayKey(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        return components.date.map { calendar.startOfDay(for: $0) }
    }

    private func runtimeStateText(for provider: UsageProvider, runningProviders: Set<UsageProvider>) -> String {
        if runningProviders.contains(provider) {
            return "Live process detected"
        }
        if self.hasRecentProviderActivity(provider, maxAge: Self.menuProviderRecentContextWindow) {
            return "Open context detected"
        }
        return "Not running right now"
    }

    private func resolvedSwitcherSelection(
        enabledProviders: [UsageProvider],
        includesOverview: Bool) -> ProviderSwitcherSelection
    {
        if includesOverview, self.settings.mergedMenuLastSelectedWasOverview {
            return .overview
        }
        return .provider(self.resolvedMenuProvider(enabledProviders: enabledProviders) ?? .codex)
    }

    private func tokenAccountMenuDisplay(for provider: UsageProvider) -> TokenAccountMenuDisplay? {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return nil }
        let accounts = self.settings.tokenAccounts(for: provider)
        guard accounts.count > 1 else { return nil }
        let activeIndex = self.settings.tokenAccountsData(for: provider)?.clampedActiveIndex() ?? 0
        let showAll = self.settings.showAllTokenAccountsInMenu
        let snapshots = showAll ? (self.store.accountSnapshots[provider] ?? []) : []
        return TokenAccountMenuDisplay(
            provider: provider,
            accounts: accounts,
            snapshots: snapshots,
            activeIndex: activeIndex,
            showAll: showAll,
            showSwitcher: !showAll)
    }

    private func menuNeedsRefresh(_ menu: NSMenu) -> Bool {
        let key = ObjectIdentifier(menu)
        return self.menuVersions[key] != self.menuContentVersion
    }

    private func markMenuFresh(_ menu: NSMenu) {
        let key = ObjectIdentifier(menu)
        self.menuVersions[key] = self.menuContentVersion
    }

    func refreshOpenMenusIfNeeded() {
        guard !self.openMenus.isEmpty else { return }
        for (key, menu) in self.openMenus {
            guard key == ObjectIdentifier(menu) else {
                // Clean up orphaned menu entries from all tracking dictionaries
                self.openMenus.removeValue(forKey: key)
                self.menuRefreshTasks.removeValue(forKey: key)?.cancel()
                self.menuProviders.removeValue(forKey: key)
                self.menuVersions.removeValue(forKey: key)
                continue
            }

            if self.isHostedSubviewMenu(menu) {
                self.refreshHostedSubviewHeights(in: menu)
                continue
            }

            if self.menuNeedsRefresh(menu) {
                let provider = self.menuProvider(for: menu)
                self.populateMenu(menu, provider: provider)
                self.markMenuFresh(menu)
                // Heights are already set during populateMenu, no need to remeasure
            }
        }
    }

    private func menuProvider(for menu: NSMenu) -> UsageProvider? {
        if self.shouldMergeIcons {
            return self.resolvedMenuProvider()
        }
        if let provider = self.menuProviders[ObjectIdentifier(menu)] {
            return provider
        }
        if menu === self.fallbackMenu {
            return nil
        }
        return self.store.enabledProviders().first ?? .codex
    }

    private func scheduleOpenMenuRefresh(for menu: NSMenu) {
        // Kick off a user-initiated refresh on open (non-forced) and re-check after a delay.
        // NEVER block menu opening with network requests.
        if !self.store.isRefreshing {
            self.refreshStore(forceTokenUsage: false)
        }
        let key = ObjectIdentifier(menu)
        self.menuRefreshTasks[key]?.cancel()
        self.menuRefreshTasks[key] = Task { @MainActor [weak self, weak menu] in
            guard let self, let menu else { return }
            try? await Task.sleep(for: Self.menuOpenRefreshDelay)
            guard !Task.isCancelled else { return }
            guard self.openMenus[ObjectIdentifier(menu)] != nil else { return }
            guard !self.store.isRefreshing else { return }
            guard self.menuNeedsDelayedRefreshRetry(for: menu) else { return }
            self.refreshStore(forceTokenUsage: false)
        }
    }

    private func menuNeedsDelayedRefreshRetry(for menu: NSMenu) -> Bool {
        let providersToCheck = self.delayedRefreshRetryProviders(for: menu)
        guard !providersToCheck.isEmpty else { return false }
        return providersToCheck.contains { provider in
            self.store.isStale(provider: provider) || self.store.snapshot(for: provider) == nil
        }
    }

    private func delayedRefreshRetryProviders(for menu: NSMenu) -> [UsageProvider] {
        let enabledProviders = self.store.enabledProviders()
        guard !enabledProviders.isEmpty else { return [] }
        let includesOverview = self.includesOverviewTab(enabledProviders: enabledProviders)

        if self.shouldMergeIcons,
           enabledProviders.count > 1,
           self.resolvedSwitcherSelection(
               enabledProviders: enabledProviders,
               includesOverview: includesOverview) == .overview
        {
            return self.settings.resolvedMergedOverviewProviders(
                activeProviders: enabledProviders,
                maxVisibleProviders: Self.maxOverviewProviders)
        }

        if let provider = self.menuProvider(for: menu)
            ?? self.resolvedMenuProvider(enabledProviders: enabledProviders)
        {
            return [provider]
        }
        return enabledProviders
    }

    private func refreshMenuCardHeights(in menu: NSMenu) {
        // Re-measure the menu card height right before display to avoid stale/incorrect sizing when content
        // changes (e.g. dashboard error lines causing wrapping).
        let cardItems = menu.items.filter { item in
            (item.representedObject as? String)?.hasPrefix("menuCard") == true
        }
        for item in cardItems {
            guard let view = item.view else { continue }
            let width = self.menuCardWidth(for: self.store.enabledProviders(), menu: menu)
            let height = self.menuCardHeight(for: view, width: width)
            view.frame = NSRect(
                origin: .zero,
                size: NSSize(width: width, height: height))
        }
    }

    private func makeMenuCardItem(
        _ view: some View,
        id: String,
        width: CGFloat,
        submenu: NSMenu? = nil,
        showsSubmenuIndicator: Bool = true,
        cardHorizontalInset: CGFloat = 6,
        cardVerticalInset: CGFloat = 3,
        cardShadow: Bool = false,
        onClick: (() -> Void)? = nil) -> NSMenuItem
    {
        if !Self.menuCardRenderingEnabled {
            let item = NSMenuItem()
            item.isEnabled = true
            item.representedObject = id
            item.submenu = submenu
            if submenu != nil {
                item.target = self
                item.action = #selector(self.menuCardNoOp(_:))
            }
            return item
        }

        let highlightState = MenuCardHighlightState()
        let wrapped = MenuCardSectionContainerView(
            highlightState: highlightState,
            showsSubmenuIndicator: submenu != nil && showsSubmenuIndicator,
            cardHorizontalInset: cardHorizontalInset,
            cardVerticalInset: cardVerticalInset,
            cardShadow: cardShadow)
        {
            view
        }
        let hosting = MenuCardItemHostingView(rootView: wrapped, highlightState: highlightState, onClick: onClick)
        // Set frame with target width immediately
        let height = self.menuCardHeight(for: hosting, width: width)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = true
        item.representedObject = id
        item.submenu = submenu
        if submenu != nil {
            item.target = self
            item.action = #selector(self.menuCardNoOp(_:))
        }
        return item
    }

    private func menuCardHeight(for view: NSView, width: CGFloat) -> CGFloat {
        let basePadding: CGFloat = 4
        let descenderSafety: CGFloat = 1

        // Fast path: use protocol-based measurement when available (avoids layout passes)
        if let measured = view as? MenuCardMeasuring {
            return max(1, ceil(measured.measuredHeight(width: width) + basePadding + descenderSafety))
        }

        // Set frame with target width before measuring.
        view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))

        // Use fittingSize directly - SwiftUI hosting views respect the frame width for wrapping
        let fitted = view.fittingSize

        return max(1, ceil(fitted.height + basePadding + descenderSafety))
    }

    private func addMenuCardSections(
        to menu: NSMenu,
        model: UsageMenuCardView.Model,
        provider: UsageProvider,
        width: CGFloat,
        webItems: OpenAIWebMenuItems)
    {
        _ = webItems
        let hasUsageBlock = !model.metrics.isEmpty || !model.usageNotes.isEmpty || !model.insights.isEmpty ||
            model.placeholder != nil
        let hasCredits = model.creditsText != nil
        let hasExtraUsage = model.providerCost != nil
        let hasCost = model.tokenUsage != nil
        let bottomPadding = CGFloat(10)
        let sectionSpacing = CGFloat(10)
        let usageBottomPadding = CGFloat(10)
        let creditsBottomPadding = CGFloat(9)

        let headerView = UsageMenuCardHeaderSectionView(
            model: model,
            showDivider: false,
            width: width)
        menu.addItem(self.makeMenuCardItem(headerView, id: "menuCardHeader", width: width))

        if hasUsageBlock {
            let usageView = UsageMenuCardUsageSectionView(
                model: model,
                showBottomDivider: false,
                bottomPadding: usageBottomPadding,
                width: width)
            menu.addItem(self.makeMenuCardItem(
                usageView,
                id: "menuCardUsage",
                width: width))
        }

        let hasAnyDetailSection = hasCredits || hasExtraUsage || hasCost
        if hasAnyDetailSection {
            self.addInsetDivider(
                to: menu,
                width: width,
                topSpacing: 4,
                bottomSpacing: 4)
        }

        var didAddDetailSection = false

        if hasCredits {
            let creditsView = UsageMenuCardCreditsSectionView(
                model: model,
                showBottomDivider: false,
                topPadding: sectionSpacing,
                bottomPadding: creditsBottomPadding,
                width: width)
            menu.addItem(self.makeMenuCardItem(
                creditsView,
                id: "menuCardCredits",
                width: width))
            didAddDetailSection = true
            if provider == .codex {
                menu.addItem(self.makeBuyCreditsItem())
            }
        }
        if hasExtraUsage {
            if didAddDetailSection {
                self.addInsetDivider(
                    to: menu,
                    width: width,
                    topSpacing: 4,
                    bottomSpacing: 4)
            }
            let extraUsageView = UsageMenuCardExtraUsageSectionView(
                model: model,
                topPadding: sectionSpacing,
                bottomPadding: bottomPadding,
                width: width)
            menu.addItem(self.makeMenuCardItem(
                extraUsageView,
                id: "menuCardExtraUsage",
                width: width))
            didAddDetailSection = true
        }
        if hasCost {
            if didAddDetailSection {
                self.addInsetDivider(
                    to: menu,
                    width: width,
                    topSpacing: 4,
                    bottomSpacing: 4)
            }
            let costView = UsageMenuCardCostSectionView(
                model: model,
                topPadding: sectionSpacing,
                bottomPadding: bottomPadding,
                width: width)
            let costSubmenu = self.makeCostHistorySubmenu(
                provider: provider,
                tokenUsage: model.tokenUsage)
            menu.addItem(self.makeMenuCardItem(
                costView,
                id: "menuCardCost",
                width: width,
                submenu: costSubmenu,
                showsSubmenuIndicator: false))
        }
    }

    private func switcherIcon(for provider: UsageProvider) -> NSImage {
        if let brand = ProviderBrandIcon.image(for: provider) {
            return brand
        }

        // Fallback to the dynamic icon renderer if resources are missing (e.g. dev bundle mismatch).
        let snapshot = self.store.snapshot(for: provider)
        let showUsed = self.settings.usageBarsShowUsed
        let primary = showUsed ? snapshot?.primary?.usedPercent : snapshot?.primary?.remainingPercent
        var weekly = showUsed ? snapshot?.secondary?.usedPercent : snapshot?.secondary?.remainingPercent
        if showUsed,
           provider == .warp,
           let remaining = snapshot?.secondary?.remainingPercent,
           remaining <= 0
        {
            // Preserve Warp "no bonus/exhausted bonus" layout even in show-used mode.
            weekly = 0
        }
        if showUsed,
           provider == .warp,
           let remaining = snapshot?.secondary?.remainingPercent,
           remaining > 0,
           weekly == 0
        {
            // In show-used mode, `0` means "unused", not "missing". Keep the weekly lane present.
            weekly = 0.0001
        }
        let credits = provider == .codex ? self.store.credits?.remaining : nil
        let stale = self.store.isStale(provider: provider)
        let style = self.store.style(for: provider)
        let indicator = self.store.iconIndicator(for: provider)
        let image = IconRenderer.makeIcon(
            primaryRemaining: primary,
            weeklyRemaining: weekly,
            creditsRemaining: credits,
            stale: stale,
            style: style,
            blink: 0,
            wiggle: 0,
            tilt: 0,
            statusIndicator: indicator)
        image.isTemplate = true
        return image
    }

    nonisolated static func switcherWeeklyMetricPercent(
        for provider: UsageProvider,
        snapshot: UsageSnapshot?,
        showUsed: Bool) -> Double?
    {
        let window = snapshot?.switcherWeeklyWindow(for: provider, showUsed: showUsed)
        guard let window else { return nil }
        return showUsed ? window.usedPercent : window.remainingPercent
    }

    private func switcherWeeklyRemaining(for provider: UsageProvider) -> Double? {
        Self.switcherWeeklyMetricPercent(
            for: provider,
            snapshot: self.store.snapshot(for: provider),
            showUsed: self.settings.usageBarsShowUsed)
    }

    private func selector(for action: MenuDescriptor.MenuAction) -> (Selector, Any?) {
        switch action {
        case .installUpdate: (#selector(self.installUpdate), nil)
        case .refresh: (#selector(self.refreshNow), nil)
        case .refreshAugmentSession: (#selector(self.refreshAugmentSession), nil)
        case .openApp: (#selector(self.openAppWindow), nil)
        case .dashboard: (#selector(self.openDashboard), nil)
        case .statusPage: (#selector(self.openStatusPage), nil)
        case let .switchAccount(provider): (#selector(self.runSwitchAccount(_:)), provider.rawValue)
        case let .openTerminal(command): (#selector(self.openTerminalCommand(_:)), command)
        case let .loginToProvider(url): (#selector(self.openLoginToProvider(_:)), url)
        case .settings: (#selector(self.showSettingsGeneral), nil)
        case .about: (#selector(self.showSettingsAbout), nil)
        case .quit: (#selector(self.quit), nil)
        case let .copyError(message): (#selector(self.copyError(_:)), message)
        }
    }

    @MainActor
    private protocol MenuCardHighlighting: AnyObject {
        func setHighlighted(_ highlighted: Bool)
    }

    @MainActor
    private protocol MenuCardMeasuring: AnyObject {
        func measuredHeight(width: CGFloat) -> CGFloat
    }

    @MainActor
    @Observable
    fileprivate final class MenuCardHighlightState {
        var isHighlighted = false
    }

    private final class MenuHostingView<Content: View>: NSHostingView<Content> {
        override var allowsVibrancy: Bool {
            true
        }
    }

    @MainActor
    private final class MenuCardItemHostingView<Content: View>: NSHostingView<Content>, MenuCardHighlighting,
    MenuCardMeasuring {
        private let highlightState: MenuCardHighlightState
        private let onClick: (() -> Void)?
        override var allowsVibrancy: Bool {
            true
        }

        override var intrinsicContentSize: NSSize {
            let size = super.intrinsicContentSize
            guard self.frame.width > 0 else { return size }
            return NSSize(width: self.frame.width, height: size.height)
        }

        init(rootView: Content, highlightState: MenuCardHighlightState, onClick: (() -> Void)? = nil) {
            self.highlightState = highlightState
            self.onClick = onClick
            super.init(rootView: rootView)
            if onClick != nil {
                let recognizer = NSClickGestureRecognizer(target: self, action: #selector(self.handlePrimaryClick(_:)))
                recognizer.buttonMask = 0x1
                self.addGestureRecognizer(recognizer)
            }
        }

        required init(rootView: Content) {
            self.highlightState = MenuCardHighlightState()
            self.onClick = nil
            super.init(rootView: rootView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        @objc private func handlePrimaryClick(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            self.onClick?()
        }

        func measuredHeight(width: CGFloat) -> CGFloat {
            let controller = NSHostingController(rootView: self.rootView)
            let measured = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            return measured.height
        }

        func setHighlighted(_ highlighted: Bool) {
            guard self.highlightState.isHighlighted != highlighted else { return }
            self.highlightState.isHighlighted = highlighted
        }
    }

    private struct MenuCardSectionContainerView<Content: View>: View {
        @Bindable var highlightState: MenuCardHighlightState
        let showsSubmenuIndicator: Bool
        let cardHorizontalInset: CGFloat
        let cardVerticalInset: CGFloat
        let cardShadow: Bool
        let content: Content

        init(
            highlightState: MenuCardHighlightState,
            showsSubmenuIndicator: Bool,
            cardHorizontalInset: CGFloat = 8,
            cardVerticalInset: CGFloat = 6,
            cardShadow: Bool = true,
            @ViewBuilder content: () -> Content)
        {
            self.highlightState = highlightState
            self.showsSubmenuIndicator = showsSubmenuIndicator
            self.cardHorizontalInset = cardHorizontalInset
            self.cardVerticalInset = cardVerticalInset
            self.cardShadow = cardShadow
            self.content = content()
        }

        var body: some View {
            self.content
                .environment(\.menuItemHighlighted, self.highlightState.isHighlighted)
                .foregroundStyle(MenuHighlightStyle.primary(self.highlightState.isHighlighted))
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(self.highlightState.isHighlighted ? MenuHighlightStyle.selectionBackground(true) : .clear)
                        .padding(.horizontal, self.cardHorizontalInset)
                        .padding(.vertical, self.cardVerticalInset)
                }
                .overlay(alignment: .trailing) {
                    if self.showsSubmenuIndicator {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                            .padding(.trailing, 14)
                    }
                }
                .animation(
                    .easeOut(duration: 0.14),
                    value: self.highlightState.isHighlighted)
        }
    }

    private func makeBuyCreditsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Buy Credits...", action: #selector(self.openCreditsPurchase), keyEquivalent: "")
        item.target = self
        if let image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }
        return item
    }

    @discardableResult
    private func addCreditsHistorySubmenu(to menu: NSMenu) -> Bool {
        guard let submenu = self.makeCreditsHistorySubmenu() else { return false }
        let item = NSMenuItem(title: "Credits history", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    @discardableResult
    private func addUsageBreakdownSubmenu(to menu: NSMenu) -> Bool {
        guard let submenu = self.makeUsageBreakdownSubmenu() else { return false }
        let item = NSMenuItem(title: "Usage breakdown", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    @discardableResult
    private func addCostHistorySubmenu(to menu: NSMenu, provider: UsageProvider) -> Bool {
        guard let submenu = self.makeCostHistorySubmenu(provider: provider) else { return false }
        let item = NSMenuItem(title: "Usage history (30 days)", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    @discardableResult
    private func addUsageTimelineSubmenu(to menu: NSMenu, provider: UsageProvider) -> Bool {
        guard let submenu = self.makeUsageTimelineSubmenu(provider: provider) else { return false }
        let item = NSMenuItem(title: "Timeline (local, 8 weeks)", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.submenu = submenu
        menu.addItem(item)
        return true
    }

    private func makeUsageSubmenu(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        webItems: OpenAIWebMenuItems) -> NSMenu?
    {
        if provider == .codex, webItems.hasUsageBreakdown {
            return self.makeUsageBreakdownSubmenu()
        }
        if provider == .zai {
            return self.makeZaiUsageDetailsSubmenu(snapshot: snapshot)
        }
        return nil
    }

    private func makeZaiUsageDetailsSubmenu(snapshot: UsageSnapshot?) -> NSMenu? {
        guard let timeLimit = snapshot?.zaiUsage?.timeLimit else { return nil }
        guard !timeLimit.usageDetails.isEmpty else { return nil }

        let submenu = NSMenu()
        submenu.delegate = self
        self.configureMenuChrome(submenu)
        let titleItem = NSMenuItem(title: "MCP details", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        submenu.addItem(titleItem)

        if let window = timeLimit.windowLabel {
            let item = NSMenuItem(title: "Window: \(window)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        if let resetTime = timeLimit.nextResetTime {
            let reset = self.settings.resetTimeDisplayStyle == .absolute
                ? UsageFormatter.resetDescription(from: resetTime)
                : UsageFormatter.resetCountdownDescription(from: resetTime)
            let item = NSMenuItem(title: "Resets: \(reset)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
        submenu.addItem(.separator())

        let sortedDetails = timeLimit.usageDetails.sorted {
            $0.modelCode.localizedCaseInsensitiveCompare($1.modelCode) == .orderedAscending
        }
        for detail in sortedDetails {
            let usage = UsageFormatter.tokenCountString(detail.usage)
            let item = NSMenuItem(title: "\(detail.modelCode): \(usage)", action: nil, keyEquivalent: "")
            submenu.addItem(item)
        }
        return submenu
    }

    private func makeUsageBreakdownSubmenu() -> NSMenu? {
        let breakdown = self.store.openAIDashboard?.usageBreakdown ?? []
        let width = Self.menuCardBaseWidth
        guard !breakdown.isEmpty else { return nil }

        if !Self.menuCardRenderingEnabled {
            let submenu = NSMenu()
            submenu.delegate = self
            self.configureMenuChrome(submenu)
            let chartItem = NSMenuItem()
            chartItem.isEnabled = false
            chartItem.representedObject = "usageBreakdownChart"
            submenu.addItem(chartItem)
            return submenu
        }

        let submenu = NSMenu()
        submenu.delegate = self
        self.configureMenuChrome(submenu)
        let chartView = UsageBreakdownChartMenuView(breakdown: breakdown, width: width)
        let hosting = MenuHostingView(rootView: chartView)
        // Use NSHostingController for efficient size calculation without multiple layout passes
        let controller = NSHostingController(rootView: chartView)
        let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "usageBreakdownChart"
        submenu.addItem(chartItem)
        return submenu
    }

    private func makeCreditsHistorySubmenu() -> NSMenu? {
        let breakdown = self.store.openAIDashboard?.dailyBreakdown ?? []
        let width = Self.menuCardBaseWidth
        guard !breakdown.isEmpty else { return nil }

        if !Self.menuCardRenderingEnabled {
            let submenu = NSMenu()
            submenu.delegate = self
            self.configureMenuChrome(submenu)
            let chartItem = NSMenuItem()
            chartItem.isEnabled = false
            chartItem.representedObject = "creditsHistoryChart"
            submenu.addItem(chartItem)
            return submenu
        }

        let submenu = NSMenu()
        submenu.delegate = self
        self.configureMenuChrome(submenu)
        let chartView = CreditsHistoryChartMenuView(breakdown: breakdown, width: width)
        let hosting = MenuHostingView(rootView: chartView)
        // Use NSHostingController for efficient size calculation without multiple layout passes
        let controller = NSHostingController(rootView: chartView)
        let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "creditsHistoryChart"
        submenu.addItem(chartItem)
        return submenu
    }

    private func makeCostHistorySubmenu(
        provider: UsageProvider,
        tokenUsage: UsageMenuCardView.Model.TokenUsageSection? = nil) -> NSMenu?
    {
        guard provider == .codex || provider == .claude || provider == .vertexai else { return nil }
        let width = Self.menuCardBaseWidth
        guard let tokenSnapshot = self.store.tokenSnapshot(for: provider) else { return nil }
        guard !tokenSnapshot.daily.isEmpty else { return nil }
        let summaryLines = self.costSummaryLines(from: tokenUsage)

        if !Self.menuCardRenderingEnabled {
            let submenu = NSMenu()
            submenu.delegate = self
            self.configureMenuChrome(submenu)
            let chartItem = NSMenuItem()
            chartItem.isEnabled = false
            chartItem.representedObject = "costHistoryChart"
            submenu.addItem(chartItem)
            return submenu
        }

        let submenu = NSMenu()
        submenu.delegate = self
        self.configureMenuChrome(submenu)
        let chartView = CostHistoryChartMenuView(
            provider: provider,
            daily: tokenSnapshot.daily,
            totalCostUSD: tokenSnapshot.last30DaysCostUSD,
            summaryLines: summaryLines,
            width: width)
        let hosting = MenuHostingView(rootView: chartView)
        // Use NSHostingController for efficient size calculation without multiple layout passes
        let controller = NSHostingController(rootView: chartView)
        let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "costHistoryChart"
        submenu.addItem(chartItem)
        return submenu
    }

    private func costSummaryLines(from section: UsageMenuCardView.Model.TokenUsageSection?) -> [String] {
        guard let section else { return [] }
        let economicsLines: [String?] = [
            section.todayEconomicsLine,
            section.weekEconomicsLine,
            section.monthEconomicsLine,
        ]
        let fallbackLines: [String?] = [
            section.modelSpendLine,
            section.allTimeLine,
            section.effectiveRateLine,
        ]
        let normalizedEconomics = economicsLines.compactMap { raw -> String? in
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if !normalizedEconomics.isEmpty {
            return Array(normalizedEconomics.prefix(2))
        }
        let normalizedFallback = fallbackLines.compactMap { raw -> String? in
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return Array(normalizedFallback.prefix(2))
    }

    private func makeUsageTimelineSubmenu(provider: UsageProvider) -> NSMenu? {
        guard Self.menuCardRenderingEnabled else { return nil }
        let points = self.store.timelineDaySeries(for: provider, days: 56)
        guard points.count >= 3 else { return nil }
        let width = Self.menuCardBaseWidth

        let submenu = NSMenu()
        submenu.delegate = self
        self.configureMenuChrome(submenu)
        let chartView = UsageTimelineChartMenuView(provider: provider, points: points, width: width)
        let hosting = MenuHostingView(rootView: chartView)
        let controller = NSHostingController(rootView: chartView)
        let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))

        let chartItem = NSMenuItem()
        chartItem.view = hosting
        chartItem.isEnabled = false
        chartItem.representedObject = "usageTimelineChart"
        submenu.addItem(chartItem)
        return submenu
    }

    private func isHostedSubviewMenu(_ menu: NSMenu) -> Bool {
        let ids: Set<String> = [
            "usageBreakdownChart",
            "creditsHistoryChart",
            "costHistoryChart",
            "usageTimelineChart",
        ]
        return menu.items.contains { item in
            guard let id = item.representedObject as? String else { return false }
            return ids.contains(id)
        }
    }

    private func isOpenAIWebSubviewMenu(_ menu: NSMenu) -> Bool {
        let ids: Set<String> = [
            "usageBreakdownChart",
            "creditsHistoryChart",
        ]
        return menu.items.contains { item in
            guard let id = item.representedObject as? String else { return false }
            return ids.contains(id)
        }
    }

    private func refreshHostedSubviewHeights(in menu: NSMenu) {
        let enabledProviders = self.store.enabledProviders()
        let width = self.menuCardWidth(for: enabledProviders, menu: menu)

        for item in menu.items {
            guard let view = item.view else { continue }
            view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
            view.layoutSubtreeIfNeeded()
            let height = view.fittingSize.height
            view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        }
    }

    private func menuCardModel(
        for provider: UsageProvider?,
        snapshotOverride: UsageSnapshot? = nil,
        errorOverride: String? = nil) -> UsageMenuCardView.Model?
    {
        let target = provider ?? self.store.enabledProviders().first ?? .codex
        let metadata = self.store.metadata(for: target)

        let snapshot = snapshotOverride ?? self.store.snapshot(for: target)
        let credits: CreditsSnapshot?
        let creditsError: String?
        let dashboard: OpenAIDashboardSnapshot?
        let dashboardError: String?
        let tokenSnapshot: CostUsageTokenSnapshot?
        let tokenError: String?
        if target == .codex, snapshotOverride == nil {
            credits = self.store.credits
            creditsError = self.store.lastCreditsError
            dashboard = self.store.openAIDashboardRequiresLogin ? nil : self.store.openAIDashboard
            dashboardError = self.store.lastOpenAIDashboardError
            tokenSnapshot = self.store.tokenSnapshot(for: target)
            tokenError = self.store.tokenError(for: target)
        } else if target == .claude || target == .vertexai, snapshotOverride == nil {
            credits = nil
            creditsError = nil
            dashboard = nil
            dashboardError = nil
            tokenSnapshot = self.store.tokenSnapshot(for: target)
            tokenError = self.store.tokenError(for: target)
        } else {
            credits = nil
            creditsError = nil
            dashboard = nil
            dashboardError = nil
            tokenSnapshot = nil
            tokenError = nil
        }

        let now = Date()
        let localInsights = snapshotOverride == nil ? self.localUsageInsights(for: target, now: now) : []
        let runningProviders = self.runningProvidersForMenu()
        let runtimeStateText = self.runtimeStateText(for: target, runningProviders: runningProviders)
        let sourceContextText = if let context = self.store.sourceContextHint(for: target),
                                   !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            "\(runtimeStateText) · \(context)"
        } else {
            runtimeStateText
        }

        let input = UsageMenuCardView.Model.Input(
            provider: target,
            metadata: metadata,
            snapshot: snapshot,
            sourceContextText: sourceContextText,
            credits: credits,
            creditsError: creditsError,
            dashboard: dashboard,
            dashboardError: dashboardError,
            tokenSnapshot: tokenSnapshot,
            tokenError: tokenError,
            account: self.account,
            isRefreshing: self.store.isRefreshing,
            lastError: errorOverride ?? self.store.error(for: target),
            usageBarsShowUsed: self.settings.usageBarsShowUsed,
            resetTimeDisplayStyle: self.settings.resetTimeDisplayStyle,
            usageBudgetModeEnabled: self.settings.usageBudgetModeEnabled,
            usageBudgetTargetDays: self.settings.usageBudgetTargetDays,
            tokenCostUsageEnabled: self.settings.isCostUsageEffectivelyEnabled(for: target),
            showOptionalCreditsAndExtraUsage: self.settings.showOptionalCreditsAndExtraUsage,
            hidePersonalInfo: self.settings.hidePersonalInfo,
            now: now,
            localInsights: localInsights)
        return UsageMenuCardView.Model.make(input)
    }

    private func localUsageInsights(
        for provider: UsageProvider,
        now: Date) -> [UsageMenuCardView.Model.Insight]
    {
        var insights: [UsageMenuCardView.Model.Insight] = []

        if let delta = self.store.usageDeltaSnapshot(for: provider, now: now) {
            if let todayDelta = delta.todayDeltaPercent {
                let rounded = Int(abs(todayDelta).rounded())
                let sign = todayDelta >= 0 ? "+" : "-"
                let style: UsageMenuCardView.Model.InsightStyle = if todayDelta <= -4 {
                    .success
                } else if todayDelta >= 8 {
                    .danger
                } else if todayDelta >= 4 {
                    .warning
                } else {
                    .info
                }
                insights.append(.init(
                    id: "delta-day",
                    text: "Today vs yesterday: \(sign)\(rounded)%",
                    style: style))
            }
            if let cycleDelta = delta.cycleDeltaPercent {
                let rounded = Int(abs(cycleDelta).rounded())
                let descriptor = cycleDelta >= 0 ? "higher" : "lower"
                let style: UsageMenuCardView.Model.InsightStyle = if cycleDelta <= -4 {
                    .success
                } else if cycleDelta >= 8 {
                    .danger
                } else if cycleDelta >= 4 {
                    .warning
                } else {
                    .info
                }
                insights.append(.init(
                    id: "delta-cycle",
                    text: "Vs last cycle: \(rounded)% \(descriptor)",
                    style: style))
            }
        }

        if self.settings.sessionTrackingModeEnabled,
           let sessionSummary = self.store.sessionTrackingSummary(for: provider, now: now)
        {
            let todayText = self.hoursAndMinutesText(minutes: sessionSummary.providerTodayMinutes)
            let weekText = self.hoursAndMinutesText(minutes: sessionSummary.totalWeekMinutes)
            insights.append(.init(
                id: "session-tracking",
                text: "AI time: today \(todayText) | week \(weekText)",
                style: .info))
        }

        return insights
    }

    private func hoursAndMinutesText(minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let mins = clamped % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    @objc private func menuCardNoOp(_ sender: NSMenuItem) {
        _ = sender
    }

    @objc private func selectOverviewProvider(_ sender: NSMenuItem) {
        guard let represented = sender.representedObject as? String,
              represented.hasPrefix(Self.overviewRowIdentifierPrefix)
        else {
            return
        }
        let rawProvider = String(represented.dropFirst(Self.overviewRowIdentifierPrefix.count))
        guard let provider = UsageProvider(rawValue: rawProvider),
              let menu = sender.menu
        else {
            return
        }

        self.selectOverviewProvider(provider, menu: menu)
    }

    private func selectOverviewProvider(_ provider: UsageProvider, menu: NSMenu) {
        if !self.settings.mergedMenuLastSelectedWasOverview, self.selectedMenuProvider == provider { return }
        self.settings.mergedMenuLastSelectedWasOverview = false
        self.lastMergedSwitcherSelection = nil
        self.selectedMenuProvider = provider
        self.lastMenuProvider = provider
        self.populateMenu(menu, provider: provider)
        self.markMenuFresh(menu)
        self.applyIcon(phase: nil)
    }

    private func applySubtitle(_ subtitle: String, to item: NSMenuItem, title: String) {
        if #available(macOS 14.4, *) {
            // NSMenuItem.subtitle is only available on macOS 14.4+.
            item.subtitle = subtitle
        } else {
            item.view = self.makeMenuSubtitleView(title: title, subtitle: subtitle, isEnabled: item.isEnabled)
            item.toolTip = "\(title) — \(subtitle)"
        }
    }

    private func makeMenuSubtitleView(title: String, subtitle: String, isEnabled: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alphaValue = isEnabled ? 1.0 : 0.7

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        subtitleField.textColor = NSColor.secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleField, subtitleField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])

        return container
    }
}

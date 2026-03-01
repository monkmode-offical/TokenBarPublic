import AppKit
import QuartzCore
import TokenBarCore

final class PagedProviderSwitcherView: NSView {
    private struct Segment {
        let selection: ProviderSwitcherSelection
        let image: NSImage
        let title: String
    }

    private static let controlHeight: CGFloat = 56
    private static let pageSize = 3
    private static let minimumIndicatorRatio: CGFloat = 0.03

    private let allSegments: [Segment]
    private let onSelect: (ProviderSwitcherSelection) -> Void
    private let showsIcons: Bool
    private let showsWeeklyIndicators = false
    private let weeklyRemainingProvider: (UsageProvider) -> Double?
    private var selectedSelection: ProviderSwitcherSelection
    private var pageIndex: Int
    private var preferredWidth: CGFloat

    private let rootStack = NSStackView()
    private let slotStack = NSStackView()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private var backWidthConstraint: NSLayoutConstraint?
    private var forwardWidthConstraint: NSLayoutConstraint?
    private var slotButtons: [NSButton] = []
    private var slotSegmentIndices: [Int?] = Array(repeating: nil, count: PagedProviderSwitcherView.pageSize)
    private var slotWeeklySelections: [Int: ProviderSwitcherSelection] = [:]
    private var slotWeeklyRemaining: [Int: Double] = [:]
    private var weeklyIndicators: [Int: WeeklyIndicator] = [:]
    private var hoverTrackingArea: NSTrackingArea?
    private var hoveredButtonTag: Int?

    private final class WeeklyIndicator {
        let track: NSView
        let fill: NSView
        var fillWidthConstraint: NSLayoutConstraint

        init(track: NSView, fill: NSView, fillWidthConstraint: NSLayoutConstraint) {
            self.track = track
            self.fill = fill
            self.fillWidthConstraint = fillWidthConstraint
        }
    }

    init(
        providers: [UsageProvider],
        selected: ProviderSwitcherSelection?,
        includesOverview: Bool,
        width: CGFloat,
        showsIcons: Bool,
        iconProvider: (UsageProvider) -> NSImage,
        weeklyRemainingProvider: @escaping (UsageProvider) -> Double?,
        onSelect: @escaping (ProviderSwitcherSelection) -> Void)
    {
        var segments = providers.map { provider in
            let icon = iconProvider(provider)
            icon.isTemplate = true
            icon.size = NSSize(width: 14, height: 14)
            return Segment(
                selection: .provider(provider),
                image: icon,
                title: Self.switcherTitle(for: provider))
        }
        if includesOverview {
            let overviewIcon = Self.overviewIcon()
            overviewIcon.size = NSSize(width: 14, height: 14)
            segments.insert(
                Segment(
                    selection: .overview,
                    image: overviewIcon,
                    title: "All"),
                at: 0)
        }

        self.allSegments = segments
        self.onSelect = onSelect
        self.showsIcons = showsIcons
        self.weeklyRemainingProvider = weeklyRemainingProvider
        let initialSelection = selected ?? segments.first?.selection ?? .overview
        self.selectedSelection = initialSelection
        let selectedIndex = segments.firstIndex { $0.selection == initialSelection } ?? 0
        self.pageIndex = selectedIndex / Self.pageSize
        self.preferredWidth = width

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.controlHeight))

        self.wantsLayer = true
        self.layer?.masksToBounds = true
        self.updateContainerStyle()
        self.configureLayout()
        self.configureNavigationButton(
            self.backButton,
            symbol: "chevron.left",
            action: #selector(self.showPreviousPage))
        self.configureNavigationButton(
            self.forwardButton,
            symbol: "chevron.right",
            action: #selector(self.showNextPage))
        self.buildSlotButtons()
        self.applyCurrentPage(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: self.preferredWidth, height: Self.controlHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.updateContainerStyle()
        self.updateButtonStyles()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            self.removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
            ],
            owner: self,
            userInfo: nil)
        self.addTrackingArea(trackingArea)
        self.hoverTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let location = self.convert(event.locationInWindow, from: nil)
        let hoveredTag = self.slotButtons.first(where: { !$0.isHidden && $0.frame.contains(location) })?.tag
        guard hoveredTag != self.hoveredButtonTag else { return }
        self.hoveredButtonTag = hoveredTag
        self.updateButtonStyles()
    }

    override func mouseExited(with event: NSEvent) {
        guard self.hoveredButtonTag != nil else { return }
        self.hoveredButtonTag = nil
        self.updateButtonStyles()
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(self.allSegments.count) / Double(Self.pageSize))))
    }

    private func configureLayout() {
        self.rootStack.orientation = .horizontal
        self.rootStack.alignment = .centerY
        self.rootStack.spacing = 7
        self.rootStack.distribution = .fill
        self.rootStack.translatesAutoresizingMaskIntoConstraints = false

        self.slotStack.orientation = .horizontal
        self.slotStack.alignment = .centerY
        self.slotStack.spacing = 6
        self.slotStack.distribution = .fillEqually
        self.slotStack.wantsLayer = true
        self.slotStack.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(self.rootStack)
        self.rootStack.addArrangedSubview(self.backButton)
        self.rootStack.addArrangedSubview(self.slotStack)
        self.rootStack.addArrangedSubview(self.forwardButton)

        NSLayoutConstraint.activate([
            self.rootStack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 9),
            self.rootStack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -9),
            self.rootStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 7),
            self.rootStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -7),
            self.backButton.heightAnchor.constraint(equalToConstant: 28),
            self.forwardButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        let backWidth = self.backButton.widthAnchor.constraint(equalToConstant: 26)
        let forwardWidth = self.forwardButton.widthAnchor.constraint(equalToConstant: 26)
        self.backWidthConstraint = backWidth
        self.forwardWidthConstraint = forwardWidth
        backWidth.isActive = true
        forwardWidth.isActive = true
    }

    private func configureNavigationButton(_ button: NSButton, symbol: String, action: Selector) {
        let config = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true

        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.controlSize = .small
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.layer?.cornerCurve = .continuous
        button.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func buildSlotButtons() {
        self.slotButtons.removeAll()
        self.slotWeeklySelections.removeAll()
        self.slotWeeklyRemaining.removeAll()
        self.weeklyIndicators.removeAll()
        let bottomPadding: CGFloat = self.showsWeeklyIndicators ? 11 : 6

        for slot in 0..<Self.pageSize {
            let button: NSButton
            if self.showsIcons {
                let inline = InlineIconToggleButton(
                    title: "",
                    image: NSImage(),
                    target: self,
                    action: #selector(self.handleSlotSelection(_:)))
                inline.contentPadding = NSEdgeInsets(top: 6, left: 10, bottom: bottomPadding, right: 10)
                inline.setTitleFontSize(NSFont.smallSystemFontSize + 0.3)
                button = inline
            } else {
                let padded = PaddedToggleButton(
                    title: "",
                    target: self,
                    action: #selector(self.handleSlotSelection(_:)))
                padded.contentPadding = NSEdgeInsets(top: 6, left: 10, bottom: bottomPadding, right: 10)
                button = padded
            }

            button.tag = slot
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 0.3, weight: .medium)
            button.setButtonType(.toggle)
            button.alignment = .center
            button.wantsLayer = true
            button.layer?.cornerRadius = 12
            button.layer?.cornerCurve = .continuous
            button.translatesAutoresizingMaskIntoConstraints = false

            if self.showsWeeklyIndicators {
                self.addWeeklyIndicator(to: button, slot: slot)
            }

            self.slotStack.addArrangedSubview(button)
            self.slotButtons.append(button)
        }
    }

    private func applyCurrentPage(animated: Bool) {
        if animated {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = self.transitionSubtype()
            transition.duration = 0.18
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.slotStack.layer?.add(transition, forKey: "page")
        }

        let start = self.pageIndex * Self.pageSize
        let end = min(self.allSegments.count, start + Self.pageSize)

        for slot in 0..<Self.pageSize {
            let button = self.slotButtons[slot]
            let segmentIndex = start + slot
            guard segmentIndex < end else {
                button.isHidden = true
                self.slotSegmentIndices[slot] = nil
                self.slotWeeklySelections.removeValue(forKey: slot)
                self.slotWeeklyRemaining.removeValue(forKey: slot)
                button.state = .off
                self.updateWeeklyIndicator(slot: slot, isSelected: false)
                continue
            }

            let segment = self.allSegments[segmentIndex]
            button.isHidden = false
            self.slotSegmentIndices[slot] = segmentIndex
            button.title = segment.title
            button.toolTip = segment.title
            button.state = self.selectedSelection == segment.selection ? .on : .off

            if self.showsIcons {
                button.image = segment.image
                button.imagePosition = .imageLeft
            } else {
                button.image = nil
                button.imagePosition = .noImage
            }

            self.slotWeeklySelections[slot] = segment.selection
            if let remaining = self.weeklyRemaining(for: segment.selection) {
                self.slotWeeklyRemaining[slot] = remaining
            } else {
                self.slotWeeklyRemaining.removeValue(forKey: slot)
            }
            self.updateWeeklyIndicator(slot: slot, isSelected: button.state == .on)
        }

        let showPagination = self.allSegments.count > Self.pageSize
        let navWidth: CGFloat = showPagination ? 26 : 0
        self.backWidthConstraint?.constant = navWidth
        self.forwardWidthConstraint?.constant = navWidth
        self.backButton.isHidden = !showPagination
        self.forwardButton.isHidden = !showPagination
        self.backButton.isEnabled = showPagination && self.pageIndex > 0
        self.forwardButton.isEnabled = showPagination && self.pageIndex < (self.pageCount - 1)
        self.updateButtonStyles()
    }

    private func transitionSubtype() -> CATransitionSubtype {
        if self.lastTransitionWasForward {
            return .fromRight
        }
        return .fromLeft
    }

    private var lastTransitionWasForward = true

    private func updateContainerStyle() {
        self.layer?.cornerRadius = 13
        self.layer?.cornerCurve = .continuous
        self.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        self.layer?.borderColor = NSColor.white.withAlphaComponent(0.11).cgColor
        self.layer?.borderWidth = 0.58
    }

    private func updateButtonStyles() {
        for button in self.slotButtons {
            guard !button.isHidden else { continue }
            let isSelected = button.state == .on
            let isHovered = self.hoveredButtonTag == button.tag
            let tintColor = isSelected ? NSColor.white.withAlphaComponent(0.96) :
                NSColor.white.withAlphaComponent(0.74)
            button.contentTintColor = tintColor

            let background = if isSelected {
                NSColor.white.withAlphaComponent(0.082).cgColor
            } else if isHovered {
                NSColor.white.withAlphaComponent(0.034).cgColor
            } else {
                NSColor.clear.cgColor
            }
            self.animateBackgroundColor(background, for: button)

            if let layer = button.layer {
                if isSelected {
                    layer.borderWidth = 0.4
                    layer.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
                    layer.shadowOpacity = 0
                    layer.shadowRadius = 0
                    layer.shadowOffset = .zero
                } else if isHovered {
                    layer.borderWidth = 0.3
                    layer.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
                    layer.shadowOpacity = 0
                    layer.shadowRadius = 0
                    layer.shadowOffset = .zero
                } else {
                    layer.borderWidth = 0
                    layer.borderColor = NSColor.clear.cgColor
                    layer.shadowOpacity = 0
                    layer.shadowRadius = 0
                    layer.shadowOffset = .zero
                }
            }

            (button as? InlineIconToggleButton)?.setContentTintColor(tintColor)
            self.updateWeeklyIndicator(slot: button.tag, isSelected: isSelected)
        }

        self.updateNavigationStyles()
    }

    private func updateNavigationStyles() {
        for button in [self.backButton, self.forwardButton] {
            let enabled = button.isEnabled
            button.contentTintColor = enabled
                ? NSColor.white.withAlphaComponent(0.66)
                : NSColor.white.withAlphaComponent(0.28)
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 0
        }
    }

    private func animateBackgroundColor(_ target: CGColor, for button: NSButton) {
        guard let layer = button.layer else { return }
        let fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        if fromValue == target { return }
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = fromValue
        animation.toValue = target
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.backgroundColor = target
        layer.add(animation, forKey: "slotBackground")
    }

    private func addWeeklyIndicator(to button: NSButton, slot: Int) {
        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 1
        track.layer?.cornerCurve = .continuous
        track.layer?.masksToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(track)

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 1
        fill.layer?.cornerCurve = .continuous
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)

        let fillWidthConstraint = fill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            track.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
            track.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1.6),
            track.heightAnchor.constraint(equalToConstant: 1.2),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidthConstraint,
        ])

        self.weeklyIndicators[slot] = WeeklyIndicator(
            track: track,
            fill: fill,
            fillWidthConstraint: fillWidthConstraint)
    }

    private func weeklyRemaining(for selection: ProviderSwitcherSelection) -> Double? {
        switch selection {
        case let .provider(provider):
            return self.weeklyRemainingProvider(provider)
        case .overview:
            let values = self.allSegments.compactMap { segment -> Double? in
                guard case let .provider(provider) = segment.selection else { return nil }
                return self.weeklyRemainingProvider(provider)
            }
            guard !values.isEmpty else { return nil }
            let total = values.reduce(0, +)
            return total / Double(values.count)
        }
    }

    private func updateWeeklyIndicator(slot: Int, isSelected: Bool) {
        guard let indicator = self.weeklyIndicators[slot] else { return }
        guard let selection = self.slotWeeklySelections[slot] else {
            indicator.track.layer?.opacity = 0
            indicator.fill.layer?.opacity = 0
            return
        }

        let rawRemaining = self.slotWeeklyRemaining[slot]
        let clampedRemaining = max(0, min(100, rawRemaining ?? 50))
        let ratio = if let rawRemaining {
            max(Self.minimumIndicatorRatio, CGFloat(rawRemaining / 100))
        } else {
            0.36
        }
        indicator.fillWidthConstraint.isActive = false
        indicator.fillWidthConstraint = indicator.fill.widthAnchor.constraint(
            equalTo: indicator.track.widthAnchor,
            multiplier: ratio)
        indicator.fillWidthConstraint.isActive = true

        let fillColor = rawRemaining == nil
            ? NSColor.white.withAlphaComponent(0.52)
            : Self.weeklyIndicatorColor(for: selection, remainingPercent: clampedRemaining)
        let fillOpacity: CGFloat = isSelected ? 0.74 : 0.28
        let trackOpacity: CGFloat = isSelected ? 0.12 : 0.04
        indicator.track.layer?.backgroundColor = NSColor.white.withAlphaComponent(trackOpacity).cgColor
        indicator.fill.layer?.backgroundColor = fillColor.withAlphaComponent(fillOpacity).cgColor
        indicator.track.layer?.opacity = 1
        indicator.fill.layer?.opacity = 1
    }

    private static func weeklyIndicatorColor(
        for selection: ProviderSwitcherSelection,
        remainingPercent: Double) -> NSColor
    {
        _ = remainingPercent
        if case .overview = selection {
            return NSColor.white.withAlphaComponent(0.86)
        }
        return NSColor.white.withAlphaComponent(0.9)
    }

    @objc private func handleSlotSelection(_ sender: NSButton) {
        guard self.slotButtons.indices.contains(sender.tag),
              let segmentIndex = self.slotSegmentIndices[sender.tag],
              self.allSegments.indices.contains(segmentIndex)
        else {
            return
        }
        let segment = self.allSegments[segmentIndex]
        self.selectedSelection = segment.selection
        self.applyCurrentPage(animated: false)
        self.onSelect(segment.selection)
    }

    @objc private func showPreviousPage() {
        guard self.pageIndex > 0 else { return }
        self.lastTransitionWasForward = false
        self.pageIndex -= 1
        self.applyCurrentPage(animated: true)
    }

    @objc private func showNextPage() {
        guard self.pageIndex < self.pageCount - 1 else { return }
        self.lastTransitionWasForward = true
        self.pageIndex += 1
        self.applyCurrentPage(animated: true)
    }

    private static func overviewIcon() -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()

        func drawBar(x: CGFloat, height: CGFloat) {
            let width: CGFloat = 2.3
            let y: CGFloat = 1.7
            let path = NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: width, height: height),
                xRadius: width / 2,
                yRadius: width / 2)
            path.fill()
        }

        drawBar(x: 1.8, height: 5)
        drawBar(x: 5.6, height: 8)
        drawBar(x: 9.4, height: 10.6)
        image.unlockFocus()
        image.size = size
        image.isTemplate = true
        return image
    }

    private static func switcherTitle(for provider: UsageProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .openrouter: "Router"
        case .opencode: "OpenCode"
        case .factory: "Factory"
        case .antigravity: "Anti"
        case .vertexai: "Vertex"
        case .jetbrains: "JB"
        case .minimax: "MiniMax"
        case .kimik2: "Kimi K2"
        default: ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        }
    }
}

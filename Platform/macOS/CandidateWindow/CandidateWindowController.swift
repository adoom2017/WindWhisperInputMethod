import AppKit

enum CandidateWindowAction: Equatable, Sendable {
    case selectCandidate(index: Int)
    case page(up: Bool)
}

struct CandidateWindowEntry: Equatable, Sendable {
    let index: Int
    let shortcut: String
    let text: String
    let comment: String?
}

struct CandidateWindowModel: Equatable, Sendable {
    let pageNumber: Int
    let isLastPage: Bool
    let highlightedIndex: Int
    let entries: [CandidateWindowEntry]

    init(menu: MenuSnapshot) {
        pageNumber = max(menu.pageNumber, 0)
        isLastPage = menu.isLastPage
        highlightedIndex = menu.candidates.indices.contains(menu.highlightedIndex)
            ? menu.highlightedIndex
            : 0
        entries = menu.candidates.prefix(9).enumerated().map { index, candidate in
            CandidateWindowEntry(
                index: index,
                shortcut: String(index + 1),
                text: candidate.text,
                comment: candidate.comment
            )
        }
    }

    var pageLabel: String {
        "\(pageNumber + 1)"
    }

    var showsPagination: Bool {
        pageNumber > 0 || !isLastPage
    }
}

enum CandidateWindowHitTester {
    static func candidateIndex(at point: NSPoint, candidateFrames: [NSRect]) -> Int? {
        candidateFrames.firstIndex { $0.contains(point) }
    }
}

enum CandidatePanelConfiguration {
    enum RenderingMode: Equatable {
        case nativeGlass
        case visualEffectFallback
    }

    static let styleMask: NSWindow.StyleMask = .nonactivatingPanel
    static let material: NSVisualEffectView.Material = .popover
    static let blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    static var renderingMode: RenderingMode {
        if #available(macOS 26.0, *) {
            return .nativeGlass
        }
        return .visualEffectFallback
    }
}

final class CandidatePanel: NSPanel {}

final class CandidateWindowCoordinator {
    private let panel: CandidatePanel
    private let materialView: NSView
    private let candidateView: CandidateListView
    private let onAction: (CandidateWindowAction) -> Void

    init(onAction: @escaping (CandidateWindowAction) -> Void) {
        self.onAction = onAction
        panel = CandidatePanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 54),
            styleMask: CandidatePanelConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )
        let contentBounds = panel.contentView?.bounds ?? .zero
        candidateView = CandidateListView(frame: contentBounds)
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView(frame: contentBounds)
            glassView.style = .clear
            glassView.cornerRadius = 15
            glassView.contentView = candidateView
            materialView = glassView
        } else {
            let effectView = NSVisualEffectView(frame: contentBounds)
            effectView.material = CandidatePanelConfiguration.material
            effectView.blendingMode = CandidatePanelConfiguration.blendingMode
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.addSubview(candidateView)
            materialView = effectView
        }

        materialView.autoresizingMask = [.width, .height]
        candidateView.autoresizingMask = [.width, .height]
        candidateView.onAction = { [weak self] action in
            self?.onAction(action)
        }

        panel.contentView = materialView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = CandidatePanelConfiguration.renderingMode == .visualEffectFallback
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func update(menu: MenuSnapshot, anchorRect: NSRect, clientWindowLevel: CGWindowLevel) {
        let model = CandidateWindowModel(menu: menu)
        guard !model.entries.isEmpty, anchorRect.isUsableCandidateAnchor else {
            hide()
            return
        }

        let settings = FengYuSettingsStore.shared.snapshot
        let theme = CandidateWindowTheme.system(environment: .current)
        apply(colorScheme: settings.colorScheme)
        apply(theme: theme)
        candidateView.update(
            model: model,
            theme: theme,
            orientation: settings.candidateOrientation
        )
        let size = candidateView.preferredSize
        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        guard
            let visibleFrame = CandidateWindowScreenResolver.visibleFrame(
                containing: anchorRect,
                candidates: screenFrames
            )
        else {
            hide()
            return
        }

        let wasVisible = panel.isVisible
        panel.level = NSWindow.Level(
            rawValue: max(Int(clientWindowLevel) + 1, NSWindow.Level.popUpMenu.rawValue)
        )
        panel.setFrame(
            CandidateWindowPositioner.frame(
                anchor: anchorRect,
                panelSize: size,
                visibleFrame: visibleFrame
            ),
            display: true
        )
        candidateView.frame = materialView.bounds

        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
        }
        if !wasVisible, theme.animationDuration > 0 {
            panel.alphaValue = 0
        }
        panel.orderFront(nil)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        panel.displayIfNeeded()

        if !wasVisible, theme.animationDuration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = theme.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
    }

    func hide() {
        panel.alphaValue = 1
        panel.orderOut(nil)
    }

    private func apply(theme: CandidateWindowTheme) {
        if #available(macOS 26.0, *), let glassView = materialView as? NSGlassEffectView {
            glassView.style = .clear
            glassView.cornerRadius = theme.cornerRadius
            glassView.tintColor = nil
        } else if let effectView = materialView as? NSVisualEffectView {
            effectView.material = CandidatePanelConfiguration.material
            effectView.blendingMode = CandidatePanelConfiguration.blendingMode
            effectView.state = .active
            effectView.layer?.cornerRadius = theme.cornerRadius
            effectView.layer?.cornerCurve = .continuous
            effectView.layer?.masksToBounds = true
        }
    }

    private func apply(colorScheme: CandidateColorScheme) {
        let appearance: NSAppearance?
        switch colorScheme {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        panel.appearance = appearance
        materialView.appearance = appearance
        candidateView.appearance = appearance
    }
}

final class CandidateListView: NSView {
    private(set) var model = CandidateWindowModel(
        menu: MenuSnapshot(
            pageSize: 0,
            pageNumber: 0,
            isLastPage: true,
            highlightedIndex: 0,
            candidates: []
        )
    )
    private(set) var theme = CandidateWindowTheme.system(
        environment: CandidateAccessibilityEnvironment(
            reduceTransparency: false,
            increaseContrast: false,
            reduceMotion: false
        )
    )
    var onAction: ((CandidateWindowAction) -> Void)?
    private(set) var orientation: CandidateOrientation = .horizontal

    private var scrollAccumulator: CGFloat = 0
    private var lastScrollAction = Date.distantPast

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { theme.reduceTransparency }

    var layout: CandidateWindowLayout {
        switch orientation {
        case .horizontal:
            CandidateHorizontalLayout.make(model: model, theme: theme)
        case .vertical:
            CandidateVerticalLayout.make(model: model, theme: theme)
        }
    }

    var preferredSize: NSSize {
        layout.size
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("风语候选")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        model: CandidateWindowModel,
        theme: CandidateWindowTheme,
        orientation: CandidateOrientation = .horizontal
    ) {
        self.model = model
        self.theme = theme
        self.orientation = orientation
        setAccessibilityValue(
            model.entries.map { "\($0.shortcut) \($0.text)" }.joined(separator: "，")
        )
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let currentLayout = layout

        theme.panelBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: theme.cornerRadius,
            yRadius: theme.cornerRadius
        ).fill()

        theme.panelBorderColor.setStroke()
        let borderInset: CGFloat = theme.increaseContrast ? 0.75 : 0.5
        let border = NSBezierPath(
            roundedRect: bounds.insetBy(dx: borderInset, dy: borderInset),
            xRadius: max(theme.cornerRadius - borderInset, 0),
            yRadius: max(theme.cornerRadius - borderInset, 0)
        )
        border.lineWidth = theme.increaseContrast ? 1.5 : 1
        border.stroke()

        for (index, entry) in model.entries.enumerated()
            where currentLayout.candidateFrames.indices.contains(index)
        {
            draw(entry: entry, index: index, in: currentLayout.candidateFrames[index])
        }
        drawPageIndicator(layout: currentLayout)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let currentLayout = layout
        if let index = CandidateWindowHitTester.candidateIndex(
            at: point,
            candidateFrames: currentLayout.candidateFrames
        ) {
            onAction?(.selectCandidate(index: model.entries[index].index))
            return
        }
        if currentLayout.previousPageFrame.contains(point), model.pageNumber > 0 {
            onAction?(.page(up: true))
        } else if currentLayout.nextPageFrame.contains(point), !model.isLastPage {
            onAction?(.page(up: false))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            return
        }
        if scrollAccumulator.sign != delta.sign {
            scrollAccumulator = 0
        }
        scrollAccumulator += delta

        let now = Date()
        guard abs(scrollAccumulator) >= 10, now.timeIntervalSince(lastScrollAction) >= 0.18 else {
            return
        }
        let pageUp = scrollAccumulator > 0
        scrollAccumulator = 0
        lastScrollAction = now
        if (pageUp && model.pageNumber > 0) || (!pageUp && !model.isLastPage) {
            onAction?(.page(up: pageUp))
        }
    }

    private func draw(entry: CandidateWindowEntry, index: Int, in frame: NSRect) {
        let isHighlighted = index == model.highlightedIndex
        if isHighlighted {
            theme.highlightColor.setFill()
            let highlightPath = NSBezierPath(
                roundedRect: frame,
                xRadius: theme.cornerRadius - 4,
                yRadius: theme.cornerRadius - 4
            )
            highlightPath.fill()
            theme.highlightBorderColor.setStroke()
            let highlightBorder = NSBezierPath(
                roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
                xRadius: theme.cornerRadius - 4.5,
                yRadius: theme.cornerRadius - 4.5
            )
            highlightBorder.lineWidth = theme.increaseContrast ? 1.5 : 1
            highlightBorder.stroke()
        }

        let primaryColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor
        let shortcutBackground = isHighlighted
            ? NSColor.selectedContentBackgroundColor
            : NSColor.quaternaryLabelColor.withAlphaComponent(theme.increaseContrast ? 0.38 : 0.22)
        let shortcutTextColor: NSColor = isHighlighted
            ? .alternateSelectedControlTextColor
            : secondaryColor

        let shortcutRect = NSRect(
            x: frame.minX + theme.candidateHorizontalPadding,
            y: frame.midY - 9,
            width: 18,
            height: 18
        )
        shortcutBackground.setFill()
        NSBezierPath(roundedRect: shortcutRect, xRadius: 5, yRadius: 5).fill()
        let shortcutAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: theme.shortcutFontSize,
                weight: .medium
            ),
            .foregroundColor: shortcutTextColor,
        ]
        let shortcutSize = (entry.shortcut as NSString).size(withAttributes: shortcutAttributes)
        (entry.shortcut as NSString).draw(
            at: NSPoint(
                x: shortcutRect.midX - shortcutSize.width / 2,
                y: shortcutRect.midY - shortcutSize.height / 2
            ),
            withAttributes: shortcutAttributes
        )

        let contentX = shortcutRect.maxX + 6
        let contentWidth = max(frame.maxX - theme.candidateHorizontalPadding - contentX, 0)
        guard contentWidth > 0 else {
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(
                ofSize: theme.primaryFontSize,
                weight: isHighlighted ? .semibold : .regular
            ),
            .foregroundColor: primaryColor,
            .paragraphStyle: paragraph,
        ]
        let commentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: theme.commentFontSize),
            .foregroundColor: secondaryColor,
            .paragraphStyle: paragraph,
        ]
        let textNaturalWidth = (entry.text as NSString).size(withAttributes: textAttributes).width
        let comment = entry.comment ?? ""
        let commentNaturalWidth = (comment as NSString).size(withAttributes: commentAttributes).width
        let commentGap: CGFloat = comment.isEmpty ? 0 : 7

        let commentWidth: CGFloat
        if comment.isEmpty {
            commentWidth = 0
        } else if textNaturalWidth + commentGap + commentNaturalWidth <= contentWidth {
            commentWidth = commentNaturalWidth
        } else {
            commentWidth = min(commentNaturalWidth, max(contentWidth * 0.36, 24))
        }
        let textWidth = max(contentWidth - commentGap - commentWidth, 0)
        let textRect = NSRect(
            x: contentX,
            y: frame.midY - 11,
            width: textWidth,
            height: 24
        )
        (entry.text as NSString).draw(
            with: textRect,
            options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin],
            attributes: textAttributes
        )

        if commentWidth > 0 {
            let commentRect = NSRect(
                x: textRect.maxX + commentGap,
                y: frame.midY - 8,
                width: commentWidth,
                height: 20
            )
            (comment as NSString).draw(
                with: commentRect,
                options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin],
                attributes: commentAttributes
            )
        }
    }

    private func drawPageIndicator(layout: CandidateWindowLayout) {
        guard layout.showsPagination else {
            return
        }
        let chromeRect = layout.pageFrame.insetBy(dx: 1, dy: 5)
        let chromePath = NSBezierPath(roundedRect: chromeRect, xRadius: 9, yRadius: 9)
        theme.paginationBackgroundColor.setFill()
        chromePath.fill()
        if theme.increaseContrast {
            NSColor.separatorColor.setStroke()
            chromePath.lineWidth = 1
            chromePath.stroke()
        }

        let enabledColor = NSColor.secondaryLabelColor
        let disabledColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.45)
        let controlAttributes: (NSColor) -> [NSAttributedString.Key: Any] = { color in
            [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: color,
            ]
        }
        drawCentered(
            "‹",
            in: layout.previousPageFrame,
            attributes: controlAttributes(model.pageNumber > 0 ? enabledColor : disabledColor)
        )
        drawCentered(
            model.pageLabel,
            in: layout.pageFrame,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        drawCentered(
            "›",
            in: layout.nextPageFrame,
            attributes: controlAttributes(!model.isLastPage ? enabledColor : disabledColor)
        )
    }

    private func drawCentered(
        _ string: String,
        in rect: NSRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let size = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

private extension NSRect {
    var isUsableCandidateAnchor: Bool {
        guard !isNull, !isInfinite, height > 0 else {
            return false
        }
        return [origin.x, origin.y, width, height].allSatisfy(\.isFinite)
    }
}

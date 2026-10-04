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
            glassView.style = .regular
            glassView.cornerRadius = 8
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
            glassView.style = .regular
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
        let borderInset = theme.panelBorderWidth / 2
        let border = NSBezierPath(
            roundedRect: bounds.insetBy(dx: borderInset, dy: borderInset),
            xRadius: max(theme.cornerRadius - borderInset, 0),
            yRadius: max(theme.cornerRadius - borderInset, 0)
        )
        border.lineWidth = theme.panelBorderWidth
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
            NSBezierPath(
                roundedRect: frame,
                xRadius: CandidateWindowTheme.highlightCornerRadius,
                yRadius: CandidateWindowTheme.highlightCornerRadius
            ).fill()
        }

        let primaryColor = isHighlighted ? FengYuPalette.highlightText : FengYuPalette.textPrimary
        let shortcutAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: theme.shortcutFontSize,
                weight: isHighlighted ? .semibold : .regular
            ),
            .foregroundColor: isHighlighted ? FengYuPalette.accent : FengYuPalette.textTertiary,
        ]
        let shortcutRect = NSRect(
            x: frame.minX + theme.candidateHorizontalPadding,
            y: frame.minY,
            width: CandidateWindowTheme.shortcutWidth,
            height: frame.height
        )
        drawCentered(entry.shortcut, in: shortcutRect, attributes: shortcutAttributes)

        let contentX = shortcutRect.maxX + CandidateWindowTheme.shortcutGap
        let contentWidth = max(frame.maxX - theme.candidateHorizontalPadding - contentX, 0)
        guard contentWidth > 0 else {
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: theme.primaryFontSize),
            .foregroundColor: primaryColor,
            .paragraphStyle: paragraph,
        ]
        let commentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: theme.commentFontSize),
            .foregroundColor: FengYuPalette.textSecondary,
            .paragraphStyle: paragraph,
        ]
        let textNaturalWidth = (entry.text as NSString).size(withAttributes: textAttributes).width
        let comment = entry.comment ?? ""
        let commentNaturalWidth = (comment as NSString).size(withAttributes: commentAttributes).width
        let commentGap: CGFloat = comment.isEmpty ? 0 : CandidateWindowTheme.commentGap

        // The candidate text keeps priority; the comment follows it directly and
        // takes whatever width is left, truncating first.
        var commentWidth: CGFloat = 0
        if !comment.isEmpty, textNaturalWidth + commentGap + commentNaturalWidth > contentWidth {
            commentWidth = min(commentNaturalWidth, max(contentWidth * 0.36, 24))
        } else if !comment.isEmpty {
            commentWidth = commentNaturalWidth
        }
        let textWidth = min(ceil(textNaturalWidth), max(contentWidth - commentGap - commentWidth, 0))
        if commentWidth > 0 {
            commentWidth = min(commentNaturalWidth, max(contentWidth - textWidth - commentGap, 0))
        }
        let textHeight = ceil((entry.text as NSString).size(withAttributes: textAttributes).height)
        let textRect = NSRect(
            x: contentX,
            y: round(frame.midY - textHeight / 2),
            width: textWidth,
            height: textHeight
        )
        (entry.text as NSString).draw(
            with: textRect,
            options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin],
            attributes: textAttributes
        )

        if commentWidth > 0 {
            // Align the comment's baseline with the candidate text so the two sizes read as one line.
            let primaryFont = NSFont.systemFont(ofSize: theme.primaryFontSize)
            let commentFont = NSFont.systemFont(ofSize: theme.commentFontSize)
            let commentHeight = ceil((comment as NSString).size(withAttributes: commentAttributes).height)
            let baseline = textRect.maxY + primaryFont.descender
            let commentRect = NSRect(
                x: textRect.maxX + commentGap,
                y: round(baseline - commentHeight - commentFont.descender),
                width: commentWidth,
                height: commentHeight
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
        theme.panelBorderColor.setFill()
        let dividerRect: NSRect
        switch layout.orientation {
        case .horizontal:
            dividerRect = NSRect(
                x: layout.pageFrame.minX - theme.candidateSpacing / 2 - 0.5,
                y: layout.pageFrame.minY + 7,
                width: 1,
                height: max(layout.pageFrame.height - 14, 0)
            )
        case .vertical:
            dividerRect = NSRect(
                x: theme.horizontalPadding + theme.candidateHorizontalPadding,
                y: layout.pageFrame.minY - theme.candidateSpacing / 2 - 0.5,
                width: max(bounds.width - (theme.horizontalPadding + theme.candidateHorizontalPadding) * 2, 0),
                height: 1
            )
        }
        dividerRect.fill()

        let enabledColor = FengYuPalette.textSecondary
        let disabledColor = FengYuPalette.textTertiary.withAlphaComponent(0.5)
        let controlAttributes: (NSColor) -> [NSAttributedString.Key: Any] = { color in
            [
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
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
                .font: NSFont.monospacedDigitSystemFont(ofSize: theme.commentFontSize, weight: .regular),
                .foregroundColor: FengYuPalette.textSecondary,
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

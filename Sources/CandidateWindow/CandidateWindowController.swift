import AppKit

enum CandidateWindowAction: Equatable, Sendable {
    case selectCandidate(index: Int)
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

    init(menu: RimeMenuSnapshot) {
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
        "第 \(pageNumber + 1) 页"
    }
}

enum CandidateWindowHitTester {
    static func candidateIndex(
        at point: NSPoint,
        topInset: CGFloat,
        rowHeight: CGFloat,
        candidateCount: Int
    ) -> Int? {
        let contentY = point.y - topInset
        guard contentY >= 0, rowHeight > 0 else {
            return nil
        }
        let row = Int(contentY / rowHeight)
        return (0..<candidateCount).contains(row) ? row : nil
    }
}

enum CandidatePanelConfiguration {
    static let styleMask: NSWindow.StyleMask = .nonactivatingPanel
}

final class CandidatePanel: NSPanel {}

final class CandidateWindowCoordinator {
    private let panel: CandidatePanel
    private let candidateView: CandidateListView
    private let onAction: (CandidateWindowAction) -> Void

    init(onAction: @escaping (CandidateWindowAction) -> Void) {
        self.onAction = onAction
        panel = CandidatePanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: CandidatePanelConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )
        candidateView = CandidateListView(frame: panel.contentView?.bounds ?? .zero)

        panel.contentView = candidateView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        candidateView.onSelection = { [weak self] index in
            self?.onAction(.selectCandidate(index: index))
        }
    }

    func update(menu: RimeMenuSnapshot, anchorRect: NSRect, clientWindowLevel: CGWindowLevel) {
        let model = CandidateWindowModel(menu: menu)
        guard !model.entries.isEmpty, anchorRect.isUsableCandidateAnchor else {
            hide()
            return
        }

        candidateView.model = model
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
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
        }
        panel.orderFront(nil)
        if !panel.isVisible {
            // Input methods run behind the client application. If AppKit declines
            // the ordinary ordering request, publish this nonactivating panel
            // without activating the input-method process or stealing focus.
            panel.orderFrontRegardless()
        }
        panel.displayIfNeeded()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class CandidateListView: NSView {
    static let rowHeight: CGFloat = 32
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    static let headerHeight: CGFloat = 22
    static let maximumWidth: CGFloat = 520
    static let minimumWidth: CGFloat = 176

    var model = CandidateWindowModel(
        menu: RimeMenuSnapshot(
            pageSize: 0,
            pageNumber: 0,
            isLastPage: true,
            highlightedIndex: 0,
            candidates: []
        )
    ) {
        didSet { needsDisplay = true }
    }
    var onSelection: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    var preferredSize: NSSize {
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
        ]
        let commentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
        ]
        var contentWidth: CGFloat = 0
        for entry in model.entries {
            let textWidth = (entry.text as NSString).size(withAttributes: textAttributes).width
            let commentWidth = ((entry.comment ?? "") as NSString)
                .size(withAttributes: commentAttributes).width
            contentWidth = max(contentWidth, 30 + textWidth + (commentWidth > 0 ? 12 + commentWidth : 0))
        }
        let width = min(
            max(contentWidth + Self.horizontalPadding * 2, Self.minimumWidth),
            Self.maximumWidth
        )
        let height = Self.verticalPadding * 2 + Self.headerHeight
            + CGFloat(model.entries.count) * Self.rowHeight
        return NSSize(width: ceil(width), height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9)
        NSColor.windowBackgroundColor.withAlphaComponent(0.98).setFill()
        backgroundPath.fill()

        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (model.pageLabel as NSString).draw(
            at: NSPoint(x: Self.horizontalPadding, y: Self.verticalPadding + 3),
            withAttributes: headerAttributes
        )

        for (row, entry) in model.entries.enumerated() {
            draw(entry: entry, row: row)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard
            let row = CandidateWindowHitTester.candidateIndex(
                at: point,
                topInset: Self.verticalPadding + Self.headerHeight,
                rowHeight: Self.rowHeight,
                candidateCount: model.entries.count
            )
        else {
            return
        }
        onSelection?(model.entries[row].index)
    }

    private func draw(entry: CandidateWindowEntry, row: Int) {
        let rowRect = NSRect(
            x: 5,
            y: Self.verticalPadding + Self.headerHeight + CGFloat(row) * Self.rowHeight,
            width: bounds.width - 10,
            height: Self.rowHeight
        )
        if row == model.highlightedIndex {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: 6, yRadius: 6).fill()
        }

        let isHighlighted = row == model.highlightedIndex
        let primaryColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        let secondaryColor: NSColor = isHighlighted
            ? .selectedMenuItemTextColor.withAlphaComponent(0.72)
            : .secondaryLabelColor
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: secondaryColor,
        ]
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: primaryColor,
        ]
        let commentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: secondaryColor,
        ]

        let baselineY = rowRect.minY + 6
        (entry.shortcut as NSString).draw(
            at: NSPoint(x: Self.horizontalPadding, y: baselineY + 2),
            withAttributes: numberAttributes
        )
        let textOrigin = NSPoint(x: Self.horizontalPadding + 30, y: baselineY)
        (entry.text as NSString).draw(at: textOrigin, withAttributes: textAttributes)

        guard let comment = entry.comment, !comment.isEmpty else {
            return
        }
        let textWidth = (entry.text as NSString).size(withAttributes: textAttributes).width
        let commentRect = NSRect(
            x: textOrigin.x + textWidth + 12,
            y: baselineY + 3,
            width: max(bounds.width - textOrigin.x - textWidth - 22, 0),
            height: Self.rowHeight - 8
        )
        (comment as NSString).draw(
            with: commentRect,
            options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin],
            attributes: commentAttributes
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

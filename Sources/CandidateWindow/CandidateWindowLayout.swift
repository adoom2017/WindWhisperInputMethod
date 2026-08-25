import AppKit

struct CandidateWindowLayout: Equatable {
    let size: NSSize
    let candidateFrames: [NSRect]
    let pageFrame: NSRect
    let previousPageFrame: NSRect
    let nextPageFrame: NSRect
}

enum CandidateWidthDistributor {
    static func distribute(
        desiredWidths: [CGFloat],
        availableWidth: CGFloat,
        minimumWidth: CGFloat
    ) -> [CGFloat] {
        distribute(
            desiredWidths: desiredWidths,
            minimumWidths: Array(repeating: minimumWidth, count: desiredWidths.count),
            availableWidth: availableWidth
        )
    }

    static func distribute(
        desiredWidths: [CGFloat],
        minimumWidths: [CGFloat],
        availableWidth: CGFloat
    ) -> [CGFloat] {
        guard !desiredWidths.isEmpty else {
            return []
        }
        precondition(desiredWidths.count == minimumWidths.count)

        let minimums = minimumWidths.map { max($0, 0) }
        let desired = zip(desiredWidths, minimums).map { max($0, $1) }
        let desiredTotal = desired.reduce(0, +)
        guard desiredTotal > availableWidth else {
            return desired
        }

        let baseTotal = minimums.reduce(0, +)
        guard availableWidth > baseTotal else {
            let scale = baseTotal > 0 ? max(availableWidth, 0) / baseTotal : 0
            return minimums.map { $0 * scale }
        }

        let distributable = availableWidth - baseTotal
        let growth = zip(desired, minimums).map { $0 - $1 }
        let growthTotal = growth.reduce(0, +)
        guard growthTotal > 0 else {
            return Array(repeating: availableWidth / CGFloat(desired.count), count: desired.count)
        }

        return zip(minimums, growth).map { minimum, itemGrowth in
            minimum + distributable * (itemGrowth / growthTotal)
        }
    }
}

enum CandidateHorizontalLayout {
    static func make(
        model: CandidateWindowModel,
        theme: CandidateWindowTheme
    ) -> CandidateWindowLayout {
        let primaryFont = NSFont.systemFont(ofSize: theme.primaryFontSize)
        let commentFont = NSFont.systemFont(ofSize: theme.commentFontSize)
        let contentChromeWidth = theme.candidateHorizontalPadding * 2 + 20 + 6
        var minimumWidths = [CGFloat]()
        let desiredWidths = model.entries.map { entry in
            let textWidth = (entry.text as NSString).size(withAttributes: [.font: primaryFont]).width
            let commentWidth = ((entry.comment ?? "") as NSString)
                .size(withAttributes: [.font: commentFont]).width
            let commentGap: CGFloat = commentWidth > 0 ? 7 : 0
            minimumWidths.append(
                min(
                    max(contentChromeWidth + min(textWidth + 2, 88), theme.minimumCandidateWidth),
                    theme.maximumCandidateWidth
                )
            )
            return min(
                max(
                    contentChromeWidth + textWidth
                        + commentGap + commentWidth,
                    theme.minimumCandidateWidth
                ),
                theme.maximumCandidateWidth
            )
        }

        let itemGapTotal = theme.candidateSpacing * CGFloat(max(model.entries.count - 1, 0))
        let fixedWidth = theme.horizontalPadding * 2 + theme.pageIndicatorWidth + itemGapTotal
        let maximumItemsWidth = max(theme.maximumPanelWidth - fixedWidth, 0)
        let itemWidths = CandidateWidthDistributor.distribute(
            desiredWidths: desiredWidths,
            minimumWidths: minimumWidths,
            availableWidth: maximumItemsWidth
        )
        let itemsWidth = itemWidths.reduce(0, +)
        let naturalPanelWidth = fixedWidth + itemsWidth
        let panelWidth = min(
            max(naturalPanelWidth, theme.minimumPanelWidth),
            theme.maximumPanelWidth
        )
        let panelHeight = theme.verticalPadding * 2 + theme.candidateHeight

        var candidateFrames = [NSRect]()
        var x = theme.horizontalPadding
        for width in itemWidths {
            candidateFrames.append(
                NSRect(
                    x: x,
                    y: theme.verticalPadding,
                    width: width,
                    height: theme.candidateHeight
                )
            )
            x += width + theme.candidateSpacing
        }

        let pageFrame = NSRect(
            x: panelWidth - theme.horizontalPadding - theme.pageIndicatorWidth,
            y: theme.verticalPadding,
            width: theme.pageIndicatorWidth,
            height: theme.candidateHeight
        )
        let controlWidth = floor(pageFrame.width / 3)
        let previousPageFrame = NSRect(
            x: pageFrame.minX,
            y: pageFrame.minY,
            width: controlWidth,
            height: pageFrame.height
        )
        let nextPageFrame = NSRect(
            x: pageFrame.maxX - controlWidth,
            y: pageFrame.minY,
            width: controlWidth,
            height: pageFrame.height
        )

        return CandidateWindowLayout(
            size: NSSize(width: ceil(panelWidth), height: ceil(panelHeight)),
            candidateFrames: candidateFrames,
            pageFrame: pageFrame,
            previousPageFrame: previousPageFrame,
            nextPageFrame: nextPageFrame
        )
    }
}

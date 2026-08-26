import AppKit

struct CandidateWindowLayout: Equatable {
    let orientation: CandidateOrientation
    let showsPagination: Bool
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
        let paginationWidth = model.showsPagination ? theme.pageIndicatorWidth : 0
        let fixedWidth = theme.horizontalPadding * 2 + paginationWidth + itemGapTotal
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

        let pageFrame: NSRect
        let previousPageFrame: NSRect
        let nextPageFrame: NSRect
        if model.showsPagination {
            pageFrame = NSRect(
                x: panelWidth - theme.horizontalPadding - theme.pageIndicatorWidth,
                y: theme.verticalPadding,
                width: theme.pageIndicatorWidth,
                height: theme.candidateHeight
            )
            let controlWidth = floor(pageFrame.width / 3)
            previousPageFrame = NSRect(
                x: pageFrame.minX,
                y: pageFrame.minY,
                width: controlWidth,
                height: pageFrame.height
            )
            nextPageFrame = NSRect(
                x: pageFrame.maxX - controlWidth,
                y: pageFrame.minY,
                width: controlWidth,
                height: pageFrame.height
            )
        } else {
            pageFrame = NSRect(
                x: panelWidth - theme.horizontalPadding,
                y: theme.verticalPadding,
                width: 0,
                height: theme.candidateHeight
            )
            previousPageFrame = .zero
            nextPageFrame = .zero
        }

        return CandidateWindowLayout(
            orientation: .horizontal,
            showsPagination: model.showsPagination,
            size: NSSize(width: ceil(panelWidth), height: ceil(panelHeight)),
            candidateFrames: candidateFrames,
            pageFrame: pageFrame,
            previousPageFrame: previousPageFrame,
            nextPageFrame: nextPageFrame
        )
    }
}

enum CandidateVerticalLayout {
    static func make(
        model: CandidateWindowModel,
        theme: CandidateWindowTheme
    ) -> CandidateWindowLayout {
        let primaryFont = NSFont.systemFont(ofSize: theme.primaryFontSize)
        let commentFont = NSFont.systemFont(ofSize: theme.commentFontSize)
        let contentChromeWidth = theme.candidateHorizontalPadding * 2 + 20 + 6
        let desiredContentWidth = model.entries.map { entry in
            let textWidth = (entry.text as NSString).size(withAttributes: [.font: primaryFont]).width
            let commentWidth = ((entry.comment ?? "") as NSString)
                .size(withAttributes: [.font: commentFont]).width
            return contentChromeWidth + textWidth + (commentWidth > 0 ? 7 : 0) + commentWidth
        }.max() ?? 0
        let panelWidth = min(
            max(desiredContentWidth + theme.horizontalPadding * 2, theme.minimumPanelWidth),
            420
        )
        let rowCount = CGFloat(model.entries.count)
        let rowGaps = theme.candidateSpacing * CGFloat(max(model.entries.count - 1, 0))
        let rowsHeight = rowCount * theme.candidateHeight + rowGaps
        let pageTop = theme.verticalPadding + rowsHeight + theme.candidateSpacing
        let paginationHeight = model.showsPagination
            ? theme.candidateSpacing + theme.candidateHeight
            : 0
        let panelHeight = theme.verticalPadding + rowsHeight
            + paginationHeight + theme.verticalPadding
        let rowWidth = panelWidth - theme.horizontalPadding * 2

        let candidateFrames = model.entries.indices.map { index in
            NSRect(
                x: theme.horizontalPadding,
                y: theme.verticalPadding
                    + CGFloat(index) * (theme.candidateHeight + theme.candidateSpacing),
                width: rowWidth,
                height: theme.candidateHeight
            )
        }
        let pageFrame: NSRect
        let previousPageFrame: NSRect
        let nextPageFrame: NSRect
        if model.showsPagination {
            let verticalPageWidth = min(theme.pageIndicatorWidth, rowWidth)
            pageFrame = NSRect(
                x: floor((panelWidth - verticalPageWidth) / 2),
                y: pageTop,
                width: verticalPageWidth,
                height: theme.candidateHeight
            )
            let controlWidth = floor(pageFrame.width / 3)
            previousPageFrame = NSRect(
                x: pageFrame.minX,
                y: pageFrame.minY,
                width: controlWidth,
                height: pageFrame.height
            )
            nextPageFrame = NSRect(
                x: pageFrame.maxX - controlWidth,
                y: pageFrame.minY,
                width: controlWidth,
                height: pageFrame.height
            )
        } else {
            pageFrame = .zero
            previousPageFrame = .zero
            nextPageFrame = .zero
        }

        return CandidateWindowLayout(
            orientation: .vertical,
            showsPagination: model.showsPagination,
            size: NSSize(width: ceil(panelWidth), height: ceil(panelHeight)),
            candidateFrames: candidateFrames,
            pageFrame: pageFrame,
            previousPageFrame: previousPageFrame,
            nextPageFrame: nextPageFrame
        )
    }
}

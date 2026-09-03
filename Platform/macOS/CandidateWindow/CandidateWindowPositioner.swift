import AppKit

enum CandidateWindowPositioner {
    static let defaultGap: CGFloat = 6

    static func frame(
        anchor: NSRect,
        panelSize: NSSize,
        visibleFrame: NSRect,
        gap: CGFloat = defaultGap
    ) -> NSRect {
        let width = min(max(panelSize.width, 1), max(visibleFrame.width, 1))
        let height = min(max(panelSize.height, 1), max(visibleFrame.height, 1))
        let maximumX = visibleFrame.maxX - width
        let maximumY = visibleFrame.maxY - height

        let x = min(max(anchor.minX, visibleFrame.minX), maximumX)
        let belowY = anchor.minY - gap - height
        let aboveY = anchor.maxY + gap
        let preferredY = belowY >= visibleFrame.minY ? belowY : aboveY
        let y = min(max(preferredY, visibleFrame.minY), maximumY)

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

enum CandidateWindowScreenResolver {
    static func visibleFrame(containing anchor: NSRect, candidates: [NSRect]) -> NSRect? {
        guard !candidates.isEmpty else {
            return nil
        }

        let intersecting = candidates.max { lhs, rhs in
            intersectionArea(anchor, lhs) < intersectionArea(anchor, rhs)
        }
        if let intersecting, intersectionArea(anchor, intersecting) > 0 {
            return intersecting
        }

        let point = NSPoint(x: anchor.midX, y: anchor.midY)
        if let containing = candidates.first(where: { $0.contains(point) }) {
            return containing
        }

        return candidates.min { lhs, rhs in
            squaredDistance(from: point, to: lhs) < squaredDistance(from: point, to: rhs)
        }
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }

    private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        let deltaX = point.x - x
        let deltaY = point.y - y
        return deltaX * deltaX + deltaY * deltaY
    }
}

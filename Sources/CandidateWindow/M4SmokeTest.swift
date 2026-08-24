import AppKit
import Foundation

enum M4SmokeTest {
    static func run() -> Int32 {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RimeInputMethod-M4-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        do {
            try verifyCandidateModel()
            print("candidateModel=passed")
            try verifyHitTesting()
            print("mouseHitTesting=passed")
            try verifyPositioning()
            print("candidatePositioning=passed")
            try verifyMultipleScreens()
            print("multipleScreens=passed")
            try verifyCandidateAnchorResolution()
            print("candidateAnchorResolution=passed")
            try verifyNonactivatingPanel()
            print("nonactivatingPanel=passed")
            try verifyEngineCandidateInteraction(root: temporaryRoot)
            print("candidateInteraction=passed")
            return EXIT_SUCCESS
        } catch {
            fputs("M4 smoke test failed: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private static func verifyCandidateModel() throws {
        let model = CandidateWindowModel(
            menu: RimeMenuSnapshot(
                pageSize: 5,
                pageNumber: 2,
                isLastPage: false,
                highlightedIndex: 1,
                candidates: [
                    RimeCandidateSnapshot(text: "风", comment: "feng"),
                    RimeCandidateSnapshot(text: "语", comment: nil),
                ]
            )
        )
        guard
            model.pageLabel == "第 3 页",
            model.highlightedIndex == 1,
            model.entries.map(\.shortcut) == ["1", "2"],
            model.entries.map(\.text) == ["风", "语"]
        else {
            throw RimeBridgeError.smokeAssertion("candidate presentation model is incorrect.")
        }
    }

    private static func verifyHitTesting() throws {
        let topInset: CGFloat = 30
        guard
            CandidateWindowHitTester.candidateIndex(
                at: NSPoint(x: 20, y: 31),
                topInset: topInset,
                rowHeight: 32,
                candidateCount: 3
            ) == 0,
            CandidateWindowHitTester.candidateIndex(
                at: NSPoint(x: 20, y: 94),
                topInset: topInset,
                rowHeight: 32,
                candidateCount: 3
            ) == 2,
            CandidateWindowHitTester.candidateIndex(
                at: NSPoint(x: 20, y: 126),
                topInset: topInset,
                rowHeight: 32,
                candidateCount: 3
            ) == nil
        else {
            throw RimeBridgeError.smokeAssertion("candidate mouse hit testing is incorrect.")
        }
    }

    private static func verifyPositioning() throws {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 300, height: 200)

        let below = CandidateWindowPositioner.frame(
            anchor: NSRect(x: 400, y: 500, width: 1, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        guard below.origin == NSPoint(x: 400, y: 294) else {
            throw RimeBridgeError.smokeAssertion("candidate panel did not prefer the space below.")
        }

        let flipped = CandidateWindowPositioner.frame(
            anchor: NSRect(x: 400, y: 20, width: 1, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        guard flipped.origin == NSPoint(x: 400, y: 46) else {
            throw RimeBridgeError.smokeAssertion("candidate panel did not flip above the insertion point.")
        }

        let constrained = CandidateWindowPositioner.frame(
            anchor: NSRect(x: 1380, y: 500, width: 1, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        guard constrained.maxX == visibleFrame.maxX else {
            throw RimeBridgeError.smokeAssertion("candidate panel exceeded the visible frame.")
        }
    }

    private static func verifyMultipleScreens() throws {
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let right = NSRect(x: 0, y: 0, width: 1512, height: 982)
        guard
            CandidateWindowScreenResolver.visibleFrame(
                containing: NSRect(x: -400, y: 300, width: 1, height: 20),
                candidates: [right, left]
            ) == left,
            CandidateWindowScreenResolver.visibleFrame(
                containing: NSRect(x: 400, y: 300, width: 1, height: 20),
                candidates: [right, left]
            ) == right
        else {
            throw RimeBridgeError.smokeAssertion("candidate panel selected the wrong display.")
        }
    }

    private static func verifyNonactivatingPanel() throws {
        guard CandidatePanelConfiguration.styleMask.contains(.nonactivatingPanel) else {
            throw RimeBridgeError.smokeAssertion("candidate panel can steal application focus.")
        }
    }

    private static func verifyCandidateAnchorResolution() throws {
        let client = M3InputClientDouble()
        let lineRect = NSRect(x: 120, y: 300, width: 2, height: 24)
        let fallbackRect = NSRect(x: 500, y: 600, width: 1, height: 20)
        client.lineHeightRectangle = lineRect
        client.firstRectResult = fallbackRect
        guard CandidateAnchorResolver.anchorRect(in: client) == lineRect else {
            throw RimeBridgeError.smokeAssertion("input line rectangle was not preferred for positioning.")
        }

        client.lineHeightRectangle = .zero
        guard CandidateAnchorResolver.anchorRect(in: client) == fallbackRect else {
            throw RimeBridgeError.smokeAssertion("firstRect positioning fallback failed.")
        }

        client.firstRectResult = .zero
        guard CandidateAnchorResolver.anchorRect(in: client) == nil else {
            throw RimeBridgeError.smokeAssertion("an invalid candidate anchor was accepted.")
        }
    }

    private static func verifyEngineCandidateInteraction(root: URL) throws {
        let paths = try RimeServicePaths.applicationDefaults()
        let service = try RimeService(paths: .temporary(root: root, sharedData: paths.sharedData))
        try service.deploy(fullCheck: true)
        let session = try service.makeSession()

        guard session.simulate(sequence: "shi") else {
            throw RimeBridgeError.smokeAssertion("candidate test sequence was rejected.")
        }
        let initial = try session.readSnapshot()
        guard initial.menu.candidates.count > 1 else {
            throw RimeBridgeError.smokeAssertion("candidate test did not produce multiple candidates.")
        }

        guard session.process(keyCode: 0xFF54) else {
            throw RimeBridgeError.smokeAssertion("Down was not consumed while candidates were visible.")
        }
        let highlighted = try session.readSnapshot()
        guard
            highlighted.menu.highlightedIndex != initial.menu.highlightedIndex,
            highlighted.menu.candidates == initial.menu.candidates
        else {
            throw RimeBridgeError.smokeAssertion("keyboard highlight did not stay synchronized with Rime.")
        }

        guard !highlighted.menu.isLastPage else {
            throw RimeBridgeError.smokeAssertion("candidate test sequence did not produce multiple pages.")
        }
        guard session.process(keyCode: 0xFF56) else {
            throw RimeBridgeError.smokeAssertion("PageDown was not consumed.")
        }
        let nextPage = try session.readSnapshot()
        guard nextPage.menu.pageNumber == highlighted.menu.pageNumber + 1 else {
            throw RimeBridgeError.smokeAssertion("candidate page did not stay synchronized with Rime.")
        }

        let selectionSnapshot = try session.readSnapshot()
        let selectionIndex = min(1, selectionSnapshot.menu.candidates.count - 1)
        let expectedCommit = selectionSnapshot.menu.candidates[selectionIndex].text
        guard session.selectCandidate(at: selectionIndex) else {
            throw RimeBridgeError.smokeAssertion("semantic candidate selection was rejected.")
        }
        guard try session.readSnapshot().commitText == expectedCommit else {
            throw RimeBridgeError.smokeAssertion("candidate selection committed a different item.")
        }
    }
}

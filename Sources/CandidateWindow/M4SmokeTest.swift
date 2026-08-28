import AppKit
import Foundation

enum M4SmokeTest {
    static func run() -> Int32 {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("windwhisper-M4-\(UUID().uuidString)", isDirectory: true)
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
            menu: MenuSnapshot(
                pageSize: 5,
                pageNumber: 2,
                isLastPage: false,
                highlightedIndex: 1,
                candidates: [
                    CandidateSnapshot(text: "风", comment: "feng"),
                    CandidateSnapshot(text: "语", comment: nil),
                ]
            )
        )
        guard
            model.pageLabel == "3",
            model.highlightedIndex == 1,
            model.entries.map(\.shortcut) == ["1", "2"],
            model.entries.map(\.text) == ["风", "语"]
        else {
            throw InputEngineError.smokeAssertion("candidate presentation model is incorrect.")
        }
    }

    private static func verifyHitTesting() throws {
        let frames = [
            NSRect(x: 10, y: 8, width: 60, height: 38),
            NSRect(x: 74, y: 8, width: 80, height: 38),
            NSRect(x: 158, y: 8, width: 70, height: 38),
        ]
        guard
            CandidateWindowHitTester.candidateIndex(
                at: NSPoint(x: 20, y: 20),
                candidateFrames: frames
            ) == 0,
            CandidateWindowHitTester.candidateIndex(
                at: NSPoint(x: 100, y: 20),
                candidateFrames: frames
            ) == 1,
            CandidateWindowHitTester.candidateIndex(
                at: NSPoint(x: 240, y: 20),
                candidateFrames: frames
            ) == nil
        else {
            throw InputEngineError.smokeAssertion("candidate mouse hit testing is incorrect.")
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
            throw InputEngineError.smokeAssertion("candidate panel did not prefer the space below.")
        }

        let flipped = CandidateWindowPositioner.frame(
            anchor: NSRect(x: 400, y: 20, width: 1, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        guard flipped.origin == NSPoint(x: 400, y: 46) else {
            throw InputEngineError.smokeAssertion("candidate panel did not flip above the insertion point.")
        }

        let constrained = CandidateWindowPositioner.frame(
            anchor: NSRect(x: 1380, y: 500, width: 1, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        guard constrained.maxX == visibleFrame.maxX else {
            throw InputEngineError.smokeAssertion("candidate panel exceeded the visible frame.")
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
            throw InputEngineError.smokeAssertion("candidate panel selected the wrong display.")
        }
    }

    private static func verifyNonactivatingPanel() throws {
        guard CandidatePanelConfiguration.styleMask.contains(.nonactivatingPanel) else {
            throw InputEngineError.smokeAssertion("candidate panel can steal application focus.")
        }
    }

    private static func verifyCandidateAnchorResolution() throws {
        let client = M3InputClientDouble()
        let lineRect = NSRect(x: 120, y: 300, width: 2, height: 24)
        let fallbackRect = NSRect(x: 500, y: 600, width: 1, height: 20)
        client.lineHeightRectangle = lineRect
        client.firstRectResult = fallbackRect
        guard CandidateAnchorResolver.anchorRect(in: client) == lineRect else {
            throw InputEngineError.smokeAssertion("input line rectangle was not preferred for positioning.")
        }

        client.lineHeightRectangle = .zero
        guard CandidateAnchorResolver.anchorRect(in: client) == fallbackRect else {
            throw InputEngineError.smokeAssertion("firstRect positioning fallback failed.")
        }

        client.firstRectResult = .zero
        guard CandidateAnchorResolver.anchorRect(in: client) == nil else {
            throw InputEngineError.smokeAssertion("an invalid candidate anchor was accepted.")
        }
    }

    private static func verifyEngineCandidateInteraction(root: URL) throws {
        let paths = try InputServicePaths.applicationDefaults()
        let service = try InputService(paths: .temporary(root: root, sharedData: paths.sharedData))
        try service.deploy(fullCheck: true)
        let session = try service.makeSession()
        guard session.selectSchema(identifier: FengYuSchema.fullPinyin.rawValue) else {
            throw InputEngineError.smokeAssertion("M4 could not select its full pinyin fixture")
        }

        guard session.simulate(sequence: "shi") else {
            throw InputEngineError.smokeAssertion("candidate test sequence was rejected.")
        }
        let initial = try session.readSnapshot()
        guard initial.menu.candidates.count > 1 else {
            throw InputEngineError.smokeAssertion("candidate test did not produce multiple candidates.")
        }

        guard session.process(keyCode: 0xFF54) else {
            throw InputEngineError.smokeAssertion("Down was not consumed while candidates were visible.")
        }
        let highlighted = try session.readSnapshot()
        guard
            highlighted.menu.highlightedIndex != initial.menu.highlightedIndex,
            highlighted.menu.candidates == initial.menu.candidates
        else {
            throw InputEngineError.smokeAssertion("keyboard highlight did not stay synchronized with the input engine.")
        }

        guard !highlighted.menu.isLastPage else {
            throw InputEngineError.smokeAssertion("candidate test sequence did not produce multiple pages.")
        }
        guard session.process(keyCode: 0xFF56) else {
            throw InputEngineError.smokeAssertion("PageDown was not consumed.")
        }
        let nextPage = try session.readSnapshot()
        guard nextPage.menu.pageNumber == highlighted.menu.pageNumber + 1 else {
            throw InputEngineError.smokeAssertion("candidate page did not stay synchronized with the input engine.")
        }

        let selectionSnapshot = try session.readSnapshot()
        let selectionIndex = min(1, selectionSnapshot.menu.candidates.count - 1)
        let expectedCommit = selectionSnapshot.menu.candidates[selectionIndex].text
        guard session.selectCandidate(at: selectionIndex) else {
            throw InputEngineError.smokeAssertion("semantic candidate selection was rejected.")
        }
        guard try session.readSnapshot().commitText == expectedCommit else {
            throw InputEngineError.smokeAssertion("candidate selection committed a different item.")
        }
    }
}

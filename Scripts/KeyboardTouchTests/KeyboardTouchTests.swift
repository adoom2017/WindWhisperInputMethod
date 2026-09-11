import XCTest
import UIKit

final class KeyboardTouchTests: XCTestCase {
    @MainActor
    func testInstalledExtensionBackspaceRepeats() {
        verifyInstalledExtensionBackspaceRepeats(dark: false)
    }

    @MainActor
    func testInstalledExtensionDarkBackspaceRepeats() {
        verifyInstalledExtensionBackspaceRepeats(dark: true)
    }

    @MainActor
    private func verifyInstalledExtensionBackspaceRepeats(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--keyboard-extension-test", "--backspace-test"]
        if dark { app.launchArguments.append("--dark-keyboard") }
        app.launch()
        let field = app.textFields["extensionText"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        func textCount() -> Int { (field.value as? String)?.count ?? 0 }
        func assertStopped() {
            let value = field.value as? String ?? ""
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", value), object: field)
            changed.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 0.35), .completed,
                           "Deletion must stop when the finger leaves the key")
        }
        XCTAssertEqual(textCount(), 64)
        delete.tap()
        XCTAssertEqual(textCount(), 63, "A quick tap deletes exactly one character")
        delete.press(forDuration: 0.8)
        let afterHold = textCount()
        XCTAssertLessThanOrEqual(afterHold, 59, "A held key must delete repeatedly")
        XCTAssertGreaterThan(afterHold, 0)
        assertStopped()

        let frame = delete.frame
        let gap = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX - 2, dy: frame.midY))
        gap.press(forDuration: 0.8)
        XCTAssertLessThanOrEqual(textCount(), afterHold - 4, "Repeat also works from the enlarged touch region")
        assertStopped()
        let beforeDrag = textCount()
        gap.press(forDuration: 0.05,
                  thenDragTo: app.buttons["t"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                  withVelocity: .fast, thenHoldForDuration: 2)
        XCTAssertGreaterThanOrEqual(textCount(), beforeDrag - 6,
                                    "Deletion must stop while the finger is held outside the key")
        assertStopped()

        for mode in ["数字键盘", "切换符号"] {
            app.buttons[mode].firstMatch.tap()
            let beforeHold = textCount()
            delete.press(forDuration: 0.8)
            XCTAssertLessThanOrEqual(textCount(), beforeHold - 4,
                                     "Repeat must survive rebuilding the \(mode) layout")
            XCTAssertGreaterThan(textCount(), 0)
            assertStopped()
        }
    }

    @MainActor
    func testInstalledExtensionGapTaps() {
        verifyInstalledExtensionGapTaps(dark: false)
    }

    @MainActor
    func testInstalledExtensionDarkGapTaps() {
        verifyInstalledExtensionGapTaps(dark: true)
    }

    @MainActor
    private func verifyInstalledExtensionGapTaps(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--keyboard-extension-test"]
        if dark { app.launchArguments.append("--dark-keyboard") }
        app.launch()
        let field = app.textFields["extensionText"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.buttons["数字键盘"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        // This test requires the signed extension installed and enabled with
        // Full Access. Wait for the real engine, rather than testing its fallback.
        let mode = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["中", "英"])).firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 10), "The keyboard engine must be ready")
        let space = app.buttons["空格"].frame
        if mode.label == "中" {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: space.maxX - 25, dy: space.maxY - 18)).tap()
        }
        let q = app.buttons["q"].frame
        let w = app.buttons["w"].frame
        let a = app.buttons["a"].frame
        func tap(_ point: CGPoint) {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        }
        // Check actual text committed by the out-of-process extension.
        tap(CGPoint(x: q.maxX + (w.minX - q.maxX) * 0.4, y: q.midY))
        XCTAssertEqual(field.value as? String, "q")
        tap(CGPoint(x: w.midX, y: w.maxY + (a.minY - w.maxY) * 0.4))
        XCTAssertEqual(field.value as? String, "qw")
        tap(CGPoint(x: 1, y: a.midY))
        XCTAssertEqual(field.value as? String, "qwa")
        tap(CGPoint(x: 1, y: q.midY))
        XCTAssertEqual(field.value as? String, "qwaq")
        tap(CGPoint(x: (q.maxX + w.minX) / 2, y: q.midY))
        XCTAssertEqual((field.value as? String)?.count, 5, "Exact midpoint must insert one character")
        let delete = app.buttons["删除"].frame
        tap(CGPoint(x: delete.minX - 2, y: delete.midY))
        XCTAssertEqual(field.value as? String, "qwaq")
        tap(CGPoint(x: space.midX, y: space.maxY + 2))
        XCTAssertEqual(field.value as? String, "qwaq ")
        app.buttons["数字键盘"].firstMatch.tap()
        let one = app.buttons["1"].frame
        let two = app.buttons["2"].frame
        tap(CGPoint(x: one.maxX + (two.minX - one.maxX) * 0.4, y: one.midY))
        XCTAssertEqual(field.value as? String, "qwaq 1")
        app.buttons["字母键盘"].firstMatch.tap()
        tap(CGPoint(x: space.maxX - 25, y: space.maxY - 18))
        let n = app.buttons["n"].frame
        let m = app.buttons["m"].frame
        tap(CGPoint(x: n.maxX + (m.minX - n.maxX) * 0.4, y: n.midY))
        let candidates = app.collectionViews.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "候选词 "))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 5))
        candidates.firstMatch.tap()
        XCTAssertGreaterThan((field.value as? String)?.count ?? 0, 6, "Chinese candidate must commit")
        let captured = app.screenshot()
        assertBackgroundIsContinuous(captured, app: app)
        let screenshot = XCTAttachment(screenshot: captured)
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertBackgroundIsContinuous(_ screenshot: XCUIScreenshot, app: XCUIApplication) {
        guard let image = screenshot.image.cgImage else {
            XCTFail("Screenshot has no pixel data")
            return
        }
        let scale = CGFloat(image.width) / app.frame.width
        let boundaryY = app.collectionViews.firstMatch.frame.minY
        let x = Int(app.frame.midX * scale)
        let above = Int((boundaryY - 3) * scale)
        let below = Int((boundaryY + 3) * scale)
        XCTAssertTrue(above >= 0 && below < image.height)
        guard above >= 0, below < image.height else { return }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        for channel in 0..<3 {
            let difference = abs(Int(pixels[(above * image.width + x) * 4 + channel])
                - Int(pixels[(below * image.width + x) * 4 + channel]))
            XCTAssertLessThanOrEqual(difference, 4, "Visible background seam above the candidate strip")
        }
    }

    @MainActor
    func testGapTapsInsertText() {
        let app = XCUIApplication()
        app.launchArguments = ["--keyboard-touch-test"]
        app.launch()
        let q = app.buttons["q"]
        XCTAssertTrue(q.waitForExistence(timeout: 10))
        let w = app.buttons["w"]
        let a = app.buttons["a"]
        let output = app.staticTexts["typedText"]
        func tap(_ point: CGPoint) {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        }
        func expect(_ value: String) {
            XCTAssertTrue(NSPredicate(format: "label == %@", value)
                .evaluate(with: output), "Expected \(value), got \(output.label)")
        }

        // Horizontal gap, closer to Q; exercise both down and up outside its bounds.
        tap(CGPoint(x: q.frame.maxX + (w.frame.minX - q.frame.maxX) * 0.4, y: q.frame.midY))
        expect("q")
        // Vertical gap under W, closer to the first row.
        tap(CGPoint(x: w.frame.midX, y: w.frame.maxY + (a.frame.minY - w.frame.maxY) * 0.4))
        expect("qw")
        // The staggered second row has a much larger leading blank region.
        tap(CGPoint(x: 1, y: a.frame.midY))
        expect("qwa")
        // Outer padding beside the first row must also accept a touch.
        tap(CGPoint(x: 1, y: q.frame.midY))
        expect("qwaq")
        q.tap()
        expect("qwaqq")

        let delete = app.buttons["删除"]
        delete.tap()
        expect("qwaq")
        let space = app.buttons["空格"]
        tap(CGPoint(x: space.frame.midX, y: space.frame.maxY + 2))
        expect("qwaq ")
        app.buttons["数字键盘"].firstMatch.tap()
        let one = app.buttons["1"]
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        let two = app.buttons["2"]
        tap(CGPoint(x: one.frame.maxX + (two.frame.minX - one.frame.maxX) * 0.4, y: one.frame.midY))
        expect("qwaq 1")
        app.buttons["切换符号"].firstMatch.tap()
        let bracket = app.buttons["【"]
        XCTAssertTrue(bracket.waitForExistence(timeout: 5))
        let nextBracket = app.buttons["】"]
        tap(CGPoint(x: bracket.frame.maxX + (nextBracket.frame.minX - bracket.frame.maxX) * 0.4,
                    y: bracket.frame.midY))
        expect("qwaq 1【")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testFunctionKeysAndDragCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["--keyboard-touch-test"]
        app.launch()
        XCTAssertTrue(app.buttons["q"].waitForExistence(timeout: 10))
        let output = app.staticTexts["typedText"]
        func coordinate(_ point: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y))
        }

        let shift = app.buttons["大写"].firstMatch
        coordinate(CGPoint(x: 1, y: shift.frame.midY)).tap()
        XCTAssertTrue(app.buttons["Q"].waitForExistence(timeout: 5))
        app.buttons["Q"].tap()
        XCTAssertEqual(output.label, "Q")

        let q = app.buttons["q"].frame
        let w = app.buttons["w"].frame
        let gap = coordinate(CGPoint(x: q.maxX + (w.minX - q.maxX) * 0.4, y: q.midY))
        gap.tap()
        XCTAssertEqual(output.label, "Qq")
        gap.press(forDuration: 0.05, thenDragTo: app.buttons["t"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertEqual(output.label, "Qq", "Dragging away must cancel the original key")

        let delete = app.buttons["删除"].frame
        let deleteGap = coordinate(CGPoint(x: delete.minX - 2, y: delete.midY))
        deleteGap.tap()
        XCTAssertEqual(output.label, "Q", "A delete tap must delete exactly once")
        deleteGap.press(forDuration: 0.4)
        XCTAssertEqual(output.label, "empty")

        let space = app.buttons["空格"].frame
        // The nested language button must not become a Space tap.
        coordinate(CGPoint(x: space.maxX - 25, y: space.maxY - 18)).tap()
        XCTAssertEqual(output.label, "empty")
        coordinate(CGPoint(x: space.midX, y: space.maxY + 2)).tap()
        XCTAssertEqual(output.label, " ")
        let enter = app.buttons["换行"].frame
        coordinate(CGPoint(x: enter.maxX + 2, y: enter.midY)).tap()
        XCTAssertEqual(output.label, " \n")
        app.collectionViews.cells.firstMatch.tap()
        XCTAssertEqual(output.label, " \n，", "The candidate strip must keep its own touch handling")
    }
}

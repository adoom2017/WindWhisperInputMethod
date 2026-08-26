import AppKit
import Foundation

enum M5SmokeTest {
    static func run() -> Int32 {
        do {
            try verifyThemeFallbacks()
            print("themeFallbacks=passed")
            try verifyHorizontalLayout()
            print("horizontalLayout=passed")
            try verifyWidthDistribution()
            print("longTextTruncation=passed")
            try verifyNativeMaterialConfiguration()
            print("nativeMaterialConfiguration=passed")
            try MainActor.assumeIsolated {
                try verifyVisualSnapshots()
                try verifyInputModeIndicatorSnapshots()
            }
            print("visualSnapshots=passed")
            return EXIT_SUCCESS
        } catch {
            fputs("M5 smoke test failed: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    @MainActor
    static func preview() -> Int32 {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            fputs("M5 preview failed: no visible screen.\n", stderr)
            return EXIT_FAILURE
        }

        let coordinator = CandidateWindowCoordinator { _ in }
        let anchorRect = NSRect(
            x: visibleFrame.midX - 300,
            y: visibleFrame.midY + 80,
            width: 2,
            height: 24
        )
        coordinator.update(
            menu: previewMenu,
            anchorRect: anchorRect,
            clientWindowLevel: CGWindowLevel(kCGNormalWindowLevel)
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        coordinator.update(
            menu: previewMenu,
            anchorRect: anchorRect,
            clientWindowLevel: CGWindowLevel(kCGNormalWindowLevel)
        )
        RunLoop.main.run(until: Date().addingTimeInterval(20))
        coordinator.hide()
        return EXIT_SUCCESS
    }

    @MainActor
    static func previewInputModeIndicator() -> Int32 {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            fputs("Input mode indicator preview failed: no visible screen.\n", stderr)
            return EXIT_FAILURE
        }

        let coordinator = InputModeIndicatorCoordinator()
        let anchorRect = NSRect(
            x: visibleFrame.midX,
            y: visibleFrame.midY + 40,
            width: 2,
            height: 24
        )
        coordinator.show(
            state: .english,
            anchorRect: anchorRect,
            clientWindowLevel: CGWindowLevel(kCGNormalWindowLevel),
            autoHide: false
        )
        RunLoop.main.run(until: Date().addingTimeInterval(20))
        coordinator.hide()
        return EXIT_SUCCESS
    }

    private static func verifyThemeFallbacks() throws {
        let normal = CandidateWindowTheme.system(
            environment: CandidateAccessibilityEnvironment(
                reduceTransparency: false,
                increaseContrast: false,
                reduceMotion: false
            )
        )
        let accessible = CandidateWindowTheme.system(
            environment: CandidateAccessibilityEnvironment(
                reduceTransparency: true,
                increaseContrast: true,
                reduceMotion: true
            )
        )
        guard
            !normal.reduceTransparency,
            normal.animationDuration > 0,
            accessible.reduceTransparency,
            accessible.increaseContrast,
            accessible.animationDuration == 0,
            accessible.cornerRadius < normal.cornerRadius
        else {
            throw RimeBridgeError.smokeAssertion("candidate accessibility theme fallback is incorrect.")
        }
    }

    private static func verifyHorizontalLayout() throws {
        let theme = CandidateWindowTheme.system(
            environment: CandidateAccessibilityEnvironment(
                reduceTransparency: false,
                increaseContrast: false,
                reduceMotion: false
            )
        )
        let layout = CandidateHorizontalLayout.make(model: longTextModel, theme: theme)
        guard
            layout.candidateFrames.count == longTextModel.entries.count,
            layout.size.width <= theme.maximumPanelWidth + 0.001,
            layout.size.height == theme.verticalPadding * 2 + theme.candidateHeight,
            layout.candidateFrames.allSatisfy({ $0.minY == theme.verticalPadding }),
            layout.candidateFrames.allSatisfy({ $0.maxX <= layout.pageFrame.minX + 0.001 }),
            layout.candidateFrames[3].width >= 78,
            layout.pageFrame.maxX <= layout.size.width + 0.001
        else {
            throw RimeBridgeError.smokeAssertion("horizontal candidate layout exceeded its bounds.")
        }
        for pair in zip(layout.candidateFrames, layout.candidateFrames.dropFirst()) {
            guard pair.0.maxX <= pair.1.minX + 0.001 else {
                throw RimeBridgeError.smokeAssertion("horizontal candidate cells overlap.")
            }
        }
    }

    private static func verifyWidthDistribution() throws {
        let widths = CandidateWidthDistributor.distribute(
            desiredWidths: [220, 180, 120],
            availableWidth: 360,
            minimumWidth: 68
        )
        guard
            widths.count == 3,
            abs(widths.reduce(0, +) - 360) < 0.001,
            widths.allSatisfy({ $0 >= 68 }),
            widths[0] > widths[1],
            widths[1] > widths[2]
        else {
            throw RimeBridgeError.smokeAssertion("long candidate widths were not constrained fairly.")
        }
    }

    private static func verifyNativeMaterialConfiguration() throws {
        guard
            CandidatePanelConfiguration.styleMask.contains(.nonactivatingPanel),
            CandidatePanelConfiguration.material == .popover,
            CandidatePanelConfiguration.blendingMode == .behindWindow
        else {
            throw RimeBridgeError.smokeAssertion("native material configuration is incorrect.")
        }
        if #available(macOS 26.0, *) {
            guard CandidatePanelConfiguration.renderingMode == .nativeGlass else {
                throw RimeBridgeError.smokeAssertion("native glass was not selected on macOS 26.")
            }
        }
    }

    @MainActor
    private static func verifyVisualSnapshots() throws {
        _ = NSApplication.shared
        let environments = [
            CandidateAccessibilityEnvironment(
                reduceTransparency: false,
                increaseContrast: false,
                reduceMotion: false
            ),
            CandidateAccessibilityEnvironment(
                reduceTransparency: true,
                increaseContrast: true,
                reduceMotion: true
            ),
        ]
        let appearances = [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua]

        for environment in environments {
            for appearanceName in appearances {
                let theme = CandidateWindowTheme.system(environment: environment)
                let view = CandidateListView(frame: .zero)
                view.appearance = NSAppearance(named: appearanceName)
                view.update(model: longTextModel, theme: theme)
                view.frame = NSRect(origin: .zero, size: view.preferredSize)
                guard
                    let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else {
                    throw RimeBridgeError.smokeAssertion("candidate snapshot bitmap could not be created.")
                }
                view.cacheDisplay(in: view.bounds, to: representation)
                guard
                    let png = representation.representation(using: .png, properties: [:]),
                    png.count > 1_000
                else {
                    throw RimeBridgeError.smokeAssertion("candidate visual snapshot was empty.")
                }
            }
        }
    }

    @MainActor
    private static func verifyInputModeIndicatorSnapshots() throws {
        let appearances = [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua]
        for appearanceName in appearances {
            for state in [InputModeIndicatorState.chinese, .english] {
                let view = InputModeIndicatorView(
                    frame: NSRect(origin: .zero, size: InputModeIndicatorCoordinator.panelSize)
                )
                view.appearance = NSAppearance(named: appearanceName)
                view.updateAccessibilityEnvironment(
                    reduceTransparency: false,
                    increaseContrast: false
                )
                view.update(state: state)
                guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw RimeBridgeError.smokeAssertion(
                        "input mode indicator bitmap could not be created."
                    )
                }
                view.cacheDisplay(in: view.bounds, to: representation)
                guard
                    let png = representation.representation(using: .png, properties: [:]),
                    png.count > 500
                else {
                    throw RimeBridgeError.smokeAssertion(
                        "input mode indicator snapshot was empty."
                    )
                }
            }
        }
    }

    private static var longTextModel: CandidateWindowModel {
        CandidateWindowModel(menu: previewMenu)
    }

    private static var previewMenu: RimeMenuSnapshot {
        RimeMenuSnapshot(
            pageSize: 5,
            pageNumber: 1,
            isLastPage: false,
            highlightedIndex: 1,
            candidates: [
                RimeCandidateSnapshot(text: "风语", comment: "feng yu"),
                RimeCandidateSnapshot(text: "这是一个需要截断的很长候选词", comment: "辅助编码 abcdef"),
                RimeCandidateSnapshot(text: "输入法", comment: "shu ru fa"),
                RimeCandidateSnapshot(text: "候选", comment: nil),
                RimeCandidateSnapshot(text: "毛玻璃", comment: "native material"),
            ]
        )
    }
}

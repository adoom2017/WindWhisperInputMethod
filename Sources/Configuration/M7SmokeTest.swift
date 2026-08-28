import AppKit
import Foundation

enum M7SmokeTest {
    private final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func increment() {
            lock.lock()
            storage += 1
            lock.unlock()
        }
    }

    @MainActor
    static func run(arguments: [String]) -> Int32 {
        do {
            let result = try execute(arguments: arguments)
            print("settingsPersistence=passed")
            print("legacyPreferenceMigration=passed")
            print("invalidPreferenceFallback=passed")
            print("multiSessionSynchronization=\(result.sessionCount)")
            print("compositionPreservation=passed")
            print("simplifiedTraditionalConversion=passed")
            print("horizontalVerticalLayout=passed")
            print("settingsMenu=passed")
            print("settingsMenuCommandRouting=passed")
            print("sanitizedDiagnostics=passed")
            print("restoreDefaults=passed")
            return EXIT_SUCCESS
        } catch {
            fputs("windwhisper M7: \(error.localizedDescription)\n", stderr)
            return EXIT_FAILURE
        }
    }

    private struct Result {
        let sessionCount: Int
    }

    @MainActor
    private static func execute(arguments: [String]) throws -> Result {
        let suiteName = "com.shendongchun.inputmethod.windwhisper.m7-smoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw InputEngineError.smokeAssertion("could not create isolated M7 preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try verifyLegacyPreferenceMigration()

        let store = FengYuSettingsStore(defaults: defaults)
        guard store.snapshot == .defaults else {
            throw InputEngineError.smokeAssertion("new settings did not use product defaults")
        }
        defaults.set(FengYuSchema.flypyPhonetic.rawValue, forKey: "settings.schema.v1")
        guard store.snapshot.schema == .flypy else {
            throw InputEngineError.smokeAssertion("legacy pure-phonetic default was not migrated")
        }

        let changeCount = LockedCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .fengYuSettingsDidChange,
            object: store,
            queue: nil
        ) { _ in
            changeCount.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.update {
            $0.schema = .fullPinyin
            $0.usesFullWidth = true
            $0.usesSimplifiedChinese = false
            $0.candidateOrientation = .vertical
            $0.colorScheme = .dark
        }
        let expected = FengYuSettingsSnapshot(
            schema: .fullPinyin,
            usesFullWidth: true,
            usesSimplifiedChinese: false,
            candidateOrientation: .vertical,
            colorScheme: .dark
        )
        guard FengYuSettingsStore(defaults: defaults).snapshot == expected,
            changeCount.value == 1
        else {
            throw InputEngineError.smokeAssertion("settings were not persisted or notified")
        }

        defaults.set("removed_schema", forKey: "settings.schema.v2")
        defaults.set("diagonal", forKey: "settings.candidateOrientation.v1")
        defaults.set("neon", forKey: "settings.colorScheme.v1")
        let repaired = FengYuSettingsStore(defaults: defaults).snapshot
        guard
            repaired.schema == FengYuSettingsSnapshot.defaults.schema,
            repaired.candidateOrientation == FengYuSettingsSnapshot.defaults.candidateOrientation,
            repaired.colorScheme == FengYuSettingsSnapshot.defaults.colorScheme
        else {
            throw InputEngineError.smokeAssertion("invalid preferences did not fall back safely")
        }
        store.update {
            $0.schema = expected.schema
            $0.candidateOrientation = expected.candidateOrientation
            $0.colorScheme = expected.colorScheme
        }

        try verifyLayouts()
        try verifyMenu(store: store)
        try verifyDiagnostics(settings: store.snapshot)
        try verifyUserFacingEngineError()

        guard let resources = Bundle.main.resourceURL else {
            throw InputEngineError.missingBundledData
        }
        let sharedData = resources
        let explicitRoot = argumentValue(after: "--user-data-root", in: arguments)
        let root = explicitRoot.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("windwhisper-M7-\(UUID().uuidString)", isDirectory: true)
        let shouldRemoveRoot = explicitRoot == nil
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if shouldRemoveRoot {
                try? FileManager.default.removeItem(at: root)
            }
        }

        let service = try InputService(
            paths: .temporary(root: root, sharedData: sharedData),
            minLogLevel: 2
        )
        try service.deploy(fullCheck: true)
        let sessionOne = try service.makeSession()
        let sessionTwo = try service.makeSession()
        try expected.apply(to: sessionOne)
        try expected.apply(to: sessionTwo)
        for session in [sessionOne, sessionTwo] {
            let snapshot = try session.readSnapshot()
            guard
                snapshot.status.schemaIdentifier == expected.schema.rawValue,
                session.option("full_shape") == true,
                session.option("simplification") == false,
                session.option("zh_simp") == false,
                session.option("zh_trad") == true
            else {
                throw InputEngineError.smokeAssertion("settings diverged between input engine sessions")
            }
        }

        let composingSession = try service.makeSession()
        let composingSettings = FengYuSettingsSnapshot.defaults
        try composingSettings.apply(to: composingSession)
        guard composingSession.simulate(sequence: "ni") else {
            throw InputEngineError.smokeAssertion("composition fixture was not consumed")
        }
        let beforeCommit = try composingSession.readSnapshot()
        guard beforeCommit.composition != nil, composingSession.commitComposition() else {
            throw InputEngineError.smokeAssertion("composition could not be preserved before settings")
        }
        let committed = try composingSession.readSnapshot()
        guard let text = committed.commitText, !text.isEmpty else {
            throw InputEngineError.smokeAssertion("settings preservation produced no committed text")
        }
        try expected.apply(to: composingSession)

        try verifySimplifiedTraditionalConversion(service: service)

        store.reset()
        guard store.snapshot == .defaults, changeCount.value == 3 else {
            throw InputEngineError.smokeAssertion("restore defaults did not clear persisted settings")
        }
        return Result(sessionCount: 2)
    }

    private static func verifySimplifiedTraditionalConversion(service: InputService) throws {
        let session = try service.makeSession()
        var traditional = FengYuSettingsSnapshot.defaults
        traditional.schema = .fullPinyin
        traditional.usesSimplifiedChinese = false
        try traditional.apply(to: session)
        guard session.simulate(sequence: "hanzi") else {
            throw InputEngineError.smokeAssertion("traditional conversion fixture was not consumed")
        }
        let traditionalSnapshot = try session.readSnapshot()
        guard traditionalSnapshot.menu.candidates.contains(where: { $0.text == "漢字" }) else {
            throw InputEngineError.smokeAssertion("traditional candidate fixture was missing")
        }

        session.clearComposition()
        var simplified = traditional
        simplified.usesSimplifiedChinese = true
        try simplified.apply(to: session)
        guard session.simulate(sequence: "hanzi") else {
            throw InputEngineError.smokeAssertion("simplified conversion fixture was not consumed")
        }
        let simplifiedSnapshot = try session.readSnapshot()
        guard simplifiedSnapshot.menu.candidates.contains(where: { $0.text == "汉字" }) else {
            throw InputEngineError.smokeAssertion("simplified conversion did not produce the expected candidate")
        }
    }

    private static func verifyLegacyPreferenceMigration() throws {
        let suffix = UUID().uuidString
        let currentSuiteName = "com.shendongchun.inputmethod.windwhisper.m7-current.\(suffix)"
        let legacySuiteName = "com.shendongchun.inputmethod.windwhisper.m7-legacy.\(suffix)"
        guard
            let currentDefaults = UserDefaults(suiteName: currentSuiteName),
            let legacyDefaults = UserDefaults(suiteName: legacySuiteName)
        else {
            throw InputEngineError.smokeAssertion("could not create migration preference suites")
        }
        defer {
            currentDefaults.removePersistentDomain(forName: currentSuiteName)
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        }

        currentDefaults.set(FengYuSchema.flypy.rawValue, forKey: "settings.schema.v2")
        legacyDefaults.set(FengYuSchema.fullPinyin.rawValue, forKey: "settings.schema.v2")
        legacyDefaults.set(true, forKey: "settings.fullWidth.v1")
        legacyDefaults.set(false, forKey: "settings.simplified.v1")
        legacyDefaults.set("vertical", forKey: "settings.candidateOrientation.v1")
        legacyDefaults.set("dark", forKey: "settings.colorScheme.v1")

        let snapshot = FengYuSettingsStore(
            defaults: currentDefaults,
            legacyDefaults: [legacyDefaults]
        ).snapshot
        guard
            snapshot.schema == .flypy,
            snapshot.usesFullWidth,
            !snapshot.usesSimplifiedChinese,
            snapshot.candidateOrientation == .vertical,
            snapshot.colorScheme == .dark,
            legacyDefaults.string(forKey: "settings.schema.v2") == FengYuSchema.fullPinyin.rawValue
        else {
            throw InputEngineError.smokeAssertion(
                "legacy preferences were not migrated without overwriting current values"
            )
        }
    }

    private static func verifyLayouts() throws {
        let model = CandidateWindowModel(
            menu: MenuSnapshot(
                pageSize: 3,
                pageNumber: 0,
                isLastPage: false,
                highlightedIndex: 1,
                candidates: [
                    CandidateSnapshot(text: "风语", comment: "feng yu"),
                    CandidateSnapshot(text: "输入法", comment: "shu ru fa"),
                    CandidateSnapshot(text: "候选窗口", comment: nil),
                ]
            )
        )
        let theme = CandidateWindowTheme.system(
            environment: CandidateAccessibilityEnvironment(
                reduceTransparency: false,
                increaseContrast: false,
                reduceMotion: true
            )
        )
        let horizontal = CandidateHorizontalLayout.make(model: model, theme: theme)
        let vertical = CandidateVerticalLayout.make(model: model, theme: theme)
        guard
            horizontal.orientation == .horizontal,
            vertical.orientation == .vertical,
            vertical.candidateFrames.count == model.entries.count,
            vertical.size.height > horizontal.size.height,
            vertical.candidateFrames.allSatisfy({ $0.width == vertical.candidateFrames[0].width }),
            zip(vertical.candidateFrames, vertical.candidateFrames.dropFirst())
                .allSatisfy({ $0.maxY <= $1.minY + 0.001 }),
            vertical.pageFrame.minY >= (vertical.candidateFrames.last?.maxY ?? 0)
        else {
            throw InputEngineError.smokeAssertion("candidate orientation layouts are inconsistent")
        }
    }

    @MainActor
    private static func verifyMenu(store: FengYuSettingsStore) throws {
        _ = NSApplication.shared
        let controller = FengYuSettingsMenuController(store: store)
        controller.menuNeedsUpdate(controller.menu)
        let titles = controller.menu.items.map(\.title)
        let commandItems = controller.menu.items.filter { $0.action != nil }
        let schemaCommands = menuItems(
            in: controller.menu,
            titles: FengYuSchema.allCases.map(\.displayName)
        )
        let orientationCommands = menuItems(
            in: controller.menu,
            titles: CandidateOrientation.allCases.map(\.displayName)
        )
        let colorSchemeCommands = menuItems(
            in: controller.menu,
            titles: CandidateColorScheme.allCases.map(\.displayName)
        )
        let schemaSelectors = Set(schemaCommands.compactMap(\.action).map(NSStringFromSelector))
        let orientationSelectors = Set(orientationCommands.compactMap(\.action).map(NSStringFromSelector))
        let colorSchemeSelectors = Set(colorSchemeCommands.compactMap(\.action).map(NSStringFromSelector))
        let groupHeadings = menuItems(
            in: controller.menu,
            titles: ["输入方案", "候选排列", "候选主题"]
        )
        let settings = store.snapshot
        let unroutableCommands = commandItems.filter { item in
            guard let action = item.action else {
                return true
            }
            return item.target != nil || !WindWhisperInputController.instancesRespond(to: action)
        }
        guard
            titles.contains("输入方案"),
            titles.contains("全角字符"),
            titles.contains("简体中文"),
            titles.contains("候选排列"),
            titles.contains("候选主题"),
            titles.contains("重新部署输入引擎"),
            titles.contains("打开用户目录"),
            titles.contains("查看脱敏诊断…"),
            titles.contains("恢复默认设置…"),
            controller.menu.items.allSatisfy({ $0.submenu == nil }),
            !commandItems.isEmpty,
            commandItems.allSatisfy(\.isEnabled),
            schemaCommands.count == FengYuSchema.allCases.count,
            schemaSelectors.count == FengYuSchema.allCases.count,
            orientationCommands.count == CandidateOrientation.allCases.count,
            orientationSelectors.count == CandidateOrientation.allCases.count,
            colorSchemeCommands.count == CandidateColorScheme.allCases.count,
            colorSchemeSelectors.count == CandidateColorScheme.allCases.count,
            groupHeadings.count == 3,
            groupHeadings.allSatisfy({ !$0.isEnabled && $0.action == nil }),
            schemaCommands.filter({ $0.state == .on }).map(\.title) == [settings.schema.displayName],
            orientationCommands.filter({ $0.state == .on }).map(\.title)
                == [settings.candidateOrientation.displayName],
            colorSchemeCommands.filter({ $0.state == .on }).map(\.title)
                == [settings.colorScheme.displayName],
            schemaCommands.allSatisfy({ $0.indentationLevel == 1 }),
            orientationCommands.allSatisfy({ $0.indentationLevel == 1 }),
            colorSchemeCommands.allSatisfy({ $0.indentationLevel == 1 }),
            unroutableCommands.isEmpty
        else {
            let details = unroutableCommands.map { item in
                let action = item.action.map(NSStringFromSelector) ?? "nil"
                return "\(item.title):action=\(action),target=\(item.target.map(String.init(describing:)) ?? "nil")"
            }.joined(separator: "; ")
            throw InputEngineError.smokeAssertion(
                "M7 settings menu is incomplete or has an unroutable InputMethodKit command: \(details)"
            )
        }

        let visibleText = ([controller.menu.title] + titles).joined(separator: "\n")
        guard visibleText.contains("风语"), !visibleText.localizedCaseInsensitiveContains("input engine") else {
            throw InputEngineError.smokeAssertion("settings menu contains a legacy product name")
        }
    }

    @MainActor
    private static func menuItems(in menu: NSMenu, titles: [String]) -> [NSMenuItem] {
        menu.items.filter { titles.contains($0.title) }
    }

    private static func verifyDiagnostics(settings: FengYuSettingsSnapshot) throws {
        let runtime = NativeRuntimeDiagnosticStatus(
            isReady: true,
            version: "test",
            lastError: "SENSITIVE_PREEDIT_SENTINEL",
            userDataDirectoryExists: true,
            logDirectoryExists: true
        )
        let diagnostics = FengYuDiagnostics.render(settings: settings, runtime: runtime)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard
            !diagnostics.contains("SENSITIVE_PREEDIT_SENTINEL"),
            !diagnostics.contains(homePath),
            diagnostics.contains("inputContentIncluded=false"),
            diagnostics.contains("startupErrorPresent=true")
        else {
            throw InputEngineError.smokeAssertion("diagnostics exposed sensitive content or paths")
        }
        guard
            diagnostics.contains("风语脱敏诊断"),
            !diagnostics.localizedCaseInsensitiveContains("input engine")
        else {
            throw InputEngineError.smokeAssertion("diagnostics contain a legacy product name")
        }
    }

    private static func verifyUserFacingEngineError() throws {
        let error = InputEngineError.runtime(code: -1, message: "input engine internal sentinel")
        let message = error.localizedDescription
        guard message.contains("Input engine"), !message.localizedCaseInsensitiveContains("input engine") else {
            throw InputEngineError.smokeAssertion("user-facing engine errors expose an internal name")
        }
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        return valueIndex < arguments.endIndex ? arguments[valueIndex] : nil
    }
}

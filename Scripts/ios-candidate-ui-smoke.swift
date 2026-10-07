import UIKit

@main
final class CandidateTestApp: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CandidateTestSceneDelegate.self
        return configuration
    }
}

/// iOS 27 terminates apps that create windows outside the scene lifecycle.
final class CandidateTestSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let host = UIViewController()
        host.view.backgroundColor = .systemGray5
        if ProcessInfo.processInfo.arguments.contains("--keyboard-extension-test"),
           ProcessInfo.processInfo.arguments.contains("--text-view") {
            // Multi-line hosts (SwiftUI TextField(axis: .vertical), notes) use UITextView.
            let textView = UITextView(frame: CGRect(x: 20, y: 100, width: 300, height: 120))
            textView.font = .systemFont(ofSize: 17)
            textView.accessibilityIdentifier = "extensionText"
            textView.autocorrectionType = .no
            textView.autocapitalizationType = .none
            host.view.addSubview(textView)
            window.rootViewController = host
            window.makeKeyAndVisible()
            self.window = window
            textView.becomeFirstResponder()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--keyboard-extension-test") {
            let field = UITextField(frame: CGRect(x: 20, y: 100, width: 300, height: 60))
            if ProcessInfo.processInfo.arguments.contains("--dark-keyboard") {
                window.overrideUserInterfaceStyle = .dark
                field.keyboardAppearance = .dark
            }
            field.borderStyle = .roundedRect
            field.accessibilityIdentifier = "extensionText"
            if ProcessInfo.processInfo.arguments.contains("--backspace-test") {
                field.text = String(repeating: "abcdefgh", count: 8)
            }
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            host.view.addSubview(field)
            window.rootViewController = host
            window.makeKeyAndVisible()
            self.window = window
            field.becomeFirstResponder()
            return
        }
        let controller = KeyboardViewController()
        let isTouchTest = ProcessInfo.processInfo.arguments.contains("--keyboard-touch-test")
        if isTouchTest {
            let output = UILabel()
            output.accessibilityIdentifier = "typedText"
            output.text = "empty"
            output.frame = CGRect(x: 20, y: 100, width: 300, height: 60)
            host.view.addSubview(output)
            let proxy = TouchTestDocumentProxy()
            proxy.onChange = { output.text = $0.isEmpty ? "empty" : $0 }
            controller.testDocumentProxy = proxy
        }
        window.rootViewController = host
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor),
            controller.view.heightAnchor.constraint(equalToConstant: controller.preferredContentSize.height)
        ])
        controller.didMove(toParent: host)
        window.makeKeyAndVisible()
        self.window = window
        if isTouchTest { return }
        Task { @MainActor in
            do {
                try "RUNNING".write(to: FileManager.default.temporaryDirectory.appendingPathComponent("candidate-ui-result.txt"), atomically: true, encoding: .utf8)
                try await Task.sleep(for: .milliseconds(100))
                let result = try await controller.verifyCandidateCollection(
                    dictionary: Bundle.main.url(forResource: "fy.dict", withExtension: "yaml")!
                )
                print(result)
                try result.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("candidate-ui-result.txt"), atomically: true, encoding: .utf8)
                exit(0)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
    }
}

final class TouchTestDocumentProxy: NSObject, UITextDocumentProxy {
    enum Host {
        /// UITextField: inserting replaces the marked range.
        case uikit
        /// Flutter before flutter#191062 (闲鱼): inserting goes in at the caret
        /// and the marked code stays behind as plain text.
        case legacyFlutter
    }

    private enum Call {
        case insert(String)
        case mark(String, NSRange)
        case unmark
    }

    var onChange: ((String) -> Void)?
    private(set) var text: String
    private var cursor: Int
    /// Character range of the marked (uncommitted) text, like a UITextField.
    private(set) var markedRange: Range<Int>?
    private(set) var markedTextCalls = 0
    private(set) var cursorAdjustmentCalls = 0
    private let host: Host
    /// iOS merges a keyboard's calls until the host applies them (modelled as
    /// a 60 ms delivery delay): inserts first, then the last setMarkedText,
    /// then unmarkText.
    private let mergesCallsPerTurn: Bool
    private var queuedCalls: [Call] = []
    var hasQueuedCalls: Bool { !queuedCalls.isEmpty || isEchoPending }
    /// UIKit hosts report a commit (unmarkText) back to the keyboard ~60 ms
    /// later through textDidChange.
    var onHostEcho: (() -> Void)?
    private var isEchoPending = false

    init(text: String = "", cursor: Int = 0, host: Host = .uikit, mergesCallsPerTurn: Bool = false) {
        self.text = text
        self.cursor = cursor
        self.host = host
        self.mergesCallsPerTurn = mergesCallsPerTurn
        super.init()
    }
    var markedText: String? {
        markedRange.map { String(Array(text)[$0]) }
    }
    /// Like iOS, the document context excludes marked text.
    var documentContextBeforeInput: String? { String(text.prefix(markedRange?.lowerBound ?? cursor)) }
    /// Everything before the caret, marked text included (test assertions).
    var textBeforeCaret: String { String(text.prefix(cursor)) }
    var documentContextAfterInput: String? { String(text.dropFirst(cursor)) }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    let documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty }

    func insertText(_ value: String) { perform(.insert(value)) }
    func setMarkedText(_ value: String, selectedRange: NSRange) {
        markedTextCalls += 1
        perform(.mark(value, selectedRange))
    }
    func unmarkText() {
        markedTextCalls += 1
        perform(.unmark)
    }
    func deleteBackward() {
        markedRange = nil
        guard cursor > 0 else { return }
        text.remove(at: text.index(text.startIndex, offsetBy: cursor - 1))
        cursor -= 1
        onChange?(text)
    }
    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursorAdjustmentCalls += 1
        cursor = min(max(0, cursor + offset), text.count)
    }
    /// The user taps elsewhere: like UIKit, the host keeps the code as plain
    /// text and moves the caret.
    func userMovesCaret(to offset: Int) {
        markedRange = nil
        cursor = min(max(0, offset), text.count)
    }

    private func perform(_ call: Call) {
        guard mergesCallsPerTurn else { return apply(call) }
        queuedCalls.append(call)
        guard queuedCalls.count == 1 else { return }
        Timer.scheduledTimer(withTimeInterval: 0.06, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyQueuedCalls() }
        }
    }

    private func applyQueuedCalls() {
        let calls = queuedCalls
        queuedCalls = []
        for case .insert(let value) in calls { apply(.insert(value)) }
        if let mark = calls.last(where: { if case .mark = $0 { true } else { false } }) { apply(mark) }
        if calls.contains(where: { if case .unmark = $0 { true } else { false } }) { apply(.unmark) }
    }

    private func apply(_ call: Call) {
        switch call {
        case .insert(let value):
            let range = host == .uikit ? (markedRange ?? cursor..<cursor) : cursor..<cursor
            replace(range, with: value)
            markedRange = nil
            cursor = range.lowerBound + value.count
        case .mark(let value, let selection):
            let range = markedRange ?? cursor..<cursor
            replace(range, with: value)
            markedRange = value.isEmpty ? nil : range.lowerBound..<(range.lowerBound + value.count)
            cursor = range.lowerBound + selection.location
        case .unmark:
            markedRange = nil
            if host == .uikit, onHostEcho != nil {
                isEchoPending = true
                Timer.scheduledTimer(withTimeInterval: 0.06, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.isEchoPending = false
                        self?.onHostEcho?()
                    }
                }
            }
        }
        onChange?(text)
    }

    private func replace(_ range: Range<Int>, with value: String) {
        var characters = Array(text)
        characters.replaceSubrange(range, with: Array(value))
        text = String(characters)
    }
}

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
    var onChange: ((String) -> Void)?
    private(set) var text: String
    private var cursor: Int
    private(set) var markedTextCalls = 0
    private(set) var cursorAdjustmentCalls = 0
    init(text: String = "", cursor: Int = 0) {
        self.text = text
        self.cursor = cursor
        super.init()
    }
    var documentContextBeforeInput: String? { String(text.prefix(cursor)) }
    var documentContextAfterInput: String? { String(text.dropFirst(cursor)) }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    let documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty }
    func insertText(_ text: String) {
        self.text.insert(contentsOf: text, at: self.text.index(self.text.startIndex, offsetBy: cursor))
        cursor += text.count
        onChange?(self.text)
    }
    func deleteBackward() {
        guard cursor > 0 else { return }
        text.remove(at: text.index(text.startIndex, offsetBy: cursor - 1))
        cursor -= 1
        onChange?(text)
    }
    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursorAdjustmentCalls += 1
        cursor = min(max(0, cursor + offset), text.count)
    }
    func setMarkedText(_ markedText: String, selectedRange: NSRange) { markedTextCalls += 1 }
    func unmarkText() { markedTextCalls += 1 }
}

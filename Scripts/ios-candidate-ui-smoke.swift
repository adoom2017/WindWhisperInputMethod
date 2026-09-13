import UIKit

@main
final class CandidateTestApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
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
            return true
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
        if isTouchTest { return true }
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
        return true
    }
}

private final class TouchTestDocumentProxy: NSObject, UITextDocumentProxy {
    var onChange: ((String) -> Void)?
    private var text = "" { didSet { onChange?(text) } }
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    let documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty }
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}

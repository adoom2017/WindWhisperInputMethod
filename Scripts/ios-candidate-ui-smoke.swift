import UIKit

@main
final class CandidateTestApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        host.view.backgroundColor = .systemGray5
        let controller = KeyboardViewController()
        window.rootViewController = host
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor),
            controller.view.heightAnchor.constraint(equalToConstant: 256)
        ])
        controller.didMove(toParent: host)
        window.makeKeyAndVisible()
        self.window = window
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

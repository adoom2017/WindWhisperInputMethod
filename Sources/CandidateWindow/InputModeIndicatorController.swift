import AppKit

enum InputModeIndicatorState: Equatable, Sendable {
    case chinese
    case english

    init(isASCIIMode: Bool) {
        self = isASCIIMode ? .english : .chinese
    }

    var displayText: String {
        switch self {
        case .chinese: "中"
        case .english: "英"
        }
    }

    var accessibilityText: String {
        switch self {
        case .chinese: "中文"
        case .english: "英文"
        }
    }
}

enum InputModeIndicatorTransition {
    static func state(before: Bool, after: Bool) -> InputModeIndicatorState? {
        guard before != after else {
            return nil
        }
        return InputModeIndicatorState(isASCIIMode: after)
    }
}

final class InputModeIndicatorCoordinator {
    static let panelSize = NSSize(width: 48, height: 48)
    static let displayDuration: TimeInterval = 0.8
    static let revealDuration: TimeInterval = 0.1
    static let fadeDuration: TimeInterval = 0.12

    private let panel: CandidatePanel
    private let materialView: NSView
    private let indicatorView: InputModeIndicatorView
    private var pendingHide: DispatchWorkItem?

    init() {
        panel = CandidatePanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: CandidatePanelConfiguration.styleMask,
            backing: .buffered,
            defer: false
        )

        let bounds = NSRect(origin: .zero, size: Self.panelSize)
        indicatorView = InputModeIndicatorView(frame: bounds)
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView(frame: bounds)
            glassView.style = .clear
            glassView.cornerRadius = 15
            glassView.contentView = indicatorView
            materialView = glassView
        } else {
            let effectView = NSVisualEffectView(frame: bounds)
            effectView.material = CandidatePanelConfiguration.material
            effectView.blendingMode = CandidatePanelConfiguration.blendingMode
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = 15
            effectView.layer?.cornerCurve = .continuous
            effectView.layer?.masksToBounds = true
            effectView.addSubview(indicatorView)
            materialView = effectView
        }

        indicatorView.autoresizingMask = [.width, .height]

        panel.contentView = materialView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = CandidatePanelConfiguration.renderingMode == .visualEffectFallback
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    deinit {
        pendingHide?.cancel()
    }

    func show(
        state: InputModeIndicatorState,
        anchorRect: NSRect,
        clientWindowLevel: CGWindowLevel,
        autoHide: Bool = true
    ) {
        guard anchorRect.isUsableIndicatorAnchor else {
            hide()
            return
        }
        guard
            let visibleFrame = CandidateWindowScreenResolver.visibleFrame(
                containing: anchorRect,
                candidates: NSScreen.screens.map(\.visibleFrame)
            )
        else {
            hide()
            return
        }

        pendingHide?.cancel()
        applyColorScheme()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        indicatorView.updateAccessibilityEnvironment(
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
        indicatorView.update(state: state)
        panel.level = NSWindow.Level(
            rawValue: max(Int(clientWindowLevel) + 1, NSWindow.Level.popUpMenu.rawValue)
        )
        panel.setFrame(
            CandidateWindowPositioner.frame(
                anchor: anchorRect,
                panelSize: Self.panelSize,
                visibleFrame: visibleFrame
            ),
            display: true
        )

        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
        }
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.revealDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        if autoHide {
            scheduleHide()
        }
    }

    func hide() {
        pendingHide?.cancel()
        pendingHide = nil
        panel.alphaValue = 1
        panel.orderOut(nil)
    }

    private func scheduleHide() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        pendingHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: workItem)
    }

    private func fadeOut() {
        pendingHide = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        }
    }

    private func applyColorScheme() {
        let appearance: NSAppearance?
        switch FengYuSettingsStore.shared.snapshot.colorScheme {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        panel.appearance = appearance
        materialView.appearance = appearance
        indicatorView.appearance = appearance
    }
}

final class InputModeIndicatorView: NSView {
    private(set) var state: InputModeIndicatorState = .chinese
    private var reduceTransparency = false
    private var increaseContrast = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        update(state: .chinese)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: InputModeIndicatorState) {
        self.state = state
        setAccessibilityLabel("当前输入模式：\(state.accessibilityText)")
        needsDisplay = true
    }

    func updateAccessibilityEnvironment(reduceTransparency: Bool, increaseContrast: Bool) {
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if reduceTransparency {
            let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 15, yRadius: 15)
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            backgroundPath.fill()
        }

        if increaseContrast {
            let borderRect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 14.5, yRadius: 14.5)
            borderPath.lineWidth = 1
            NSColor.separatorColor.setStroke()
            borderPath.stroke()
        }

        let badgeRect = bounds.insetBy(dx: 7, dy: 7)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 10, yRadius: 10)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        badgeColor.setFill()
        badgePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let highlightPath = NSBezierPath(
            roundedRect: badgeRect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 9.5,
            yRadius: 9.5
        )
        highlightPath.lineWidth = 1
        NSColor.white.withAlphaComponent(increaseContrast ? 0.42 : 0.24).setStroke()
        highlightPath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = state.displayText as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: floor((bounds.width - size.width) / 2),
                y: floor((bounds.height - size.height) / 2) + 0.5
            ),
            withAttributes: attributes
        )
    }

    private var badgeColor: NSColor {
        switch state {
        case .chinese:
            .systemBlue
        case .english:
            .systemIndigo
        }
    }
}

private extension NSRect {
    var isUsableIndicatorAnchor: Bool {
        guard !isNull, !isInfinite, height > 0 else {
            return false
        }
        return [origin.x, origin.y, width, height].allSatisfy(\.isFinite)
    }
}

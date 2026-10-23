import AppKit

private final class FadePaint: NSView {
    var color: NSColor = .black
    var intensity: Double = 0.65
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        color.withAlphaComponent(intensity).setFill()
        bounds.fill()
    }
}

final class OverlayFade {
    private var windows: [NSWindow] = []
    private var generation = 0
    private(set) var isFaded = false

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rebuild()
    }
    deinit { NotificationCenter.default.removeObserver(self); windows.forEach { $0.close() } }

    @objc private func rebuild() {
        generation += 1; isFaded = false
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear; window.isOpaque = false
            window.hasShadow = false; window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = FadePaint(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.alphaValue = 0
            return window
        }
    }

    func setVisible(_ visible: Bool, color: NSColor, intensity: Double, duration: Double) {
        for window in windows {
            if let view = window.contentView as? FadePaint {
                if view.color != color || view.intensity != intensity {
                    view.color = color; view.intensity = intensity; view.needsDisplay = true
                }
            }
        }
        guard visible != isFaded else { return }
        generation += 1; let current = generation; isFaded = visible
        if visible { windows.forEach { $0.orderFrontRegardless() } }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? duration : 0.07
            context.allowsImplicitAnimation = true
            windows.forEach { $0.animator().alphaValue = visible ? 1 : 0 }
        } completionHandler: { [weak self] in
            guard let self = self, current == self.generation, !visible else { return }
            self.windows.forEach { $0.orderOut(nil) }
        }
    }
}

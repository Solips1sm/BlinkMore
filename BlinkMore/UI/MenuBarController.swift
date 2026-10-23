import AppKit

final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var phase: TrackingPhase?
    var onOpen: (() -> Void)?
    var onPause: (() -> Void)?
    var onCalibrate: (() -> Void)?

    override init() {
        super.init()
        item.button?.image = Self.mark(size: 22)
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open BlinkMore", action: #selector(openDashboard), keyEquivalent: "")
        open.target = self; menu.addItem(open)
        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Pause for 5 minutes", action: #selector(pauseTracking), keyEquivalent: "")
        pause.target = self; menu.addItem(pause)
        let calibrate = NSMenuItem(title: "Recalibrate eyes", action: #selector(calibrateTracking), keyEquivalent: "")
        calibrate.target = self; menu.addItem(calibrate)
        item.menu = menu
    }
    deinit { NSStatusBar.system.removeStatusItem(item) }
    func update(_ phase: TrackingPhase) {
        guard self.phase != phase else { return }; self.phase = phase
        item.button?.toolTip = "BlinkMore: \(phase.title)"
        item.menu?.items.first(where: { $0.action == #selector(pauseTracking) })?.title = phase == .paused ? "Resume monitoring" : "Pause for 5 minutes"
    }
    @objc private func openDashboard() { onOpen?() }
    @objc private func pauseTracking() { onPause?() }
    @objc private func calibrateTracking() { onCalibrate?() }

    static func mark(size: CGFloat, color: NSColor = .labelColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.setFill()
        let centers: [(CGFloat, CGFloat)] = [(25.76, 14), (22.316, 22.316), (14, 25.76), (5.684, 22.316), (2.24, 14), (5.684, 5.684), (14, 2.24), (22.316, 5.684)]
        for (x, y) in centers {
            NSBezierPath(ovalIn: NSRect(x: (x - 1.96) * size / 28, y: (y - 1.96) * size / 28, width: 3.92 * size / 28, height: 3.92 * size / 28)).fill()
        }
        image.unlockFocus()
        return image
    }
}

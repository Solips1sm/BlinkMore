import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let contextMenu = NSMenu()
    private var phase: TrackingPhase?
    private var blinkUntil = Date.distantPast
    private lazy var openEye = eyeImage("OpenEye", symbol: "eye")
    private lazy var closedEye = eyeImage("ClosedEye", symbol: "eye.slash")
    private lazy var idleMark = Self.mark(size: 20)
    var onOpen: ((Int) -> Void)?
    var onCommand: (([String: Any]) -> Void)?
    var snapshot: (() -> [String: Any])?

    override init() {
        super.init()
        item.button?.image = Self.mark(size: 22)
        item.button?.image?.isTemplate = true
        item.button?.target = self; item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        contextMenu.delegate = self; contextMenu.autoenablesItems = false
        add("Open BlinkMore", "open")
        for key in ["status", "count", "rate", "relative"] { add("", key, enabled: false) }
        contextMenu.addItem(.separator())
        add("Start a reset", "startReset")
        add("Pause for 5 minutes", "pause")
        add("Screen reminders", "reminders")
        add("Preview fade", "preview")
        add("Recalibrate eyes", "calibrate")
        contextMenu.addItem(.separator())
        add("Settings…", "settings")
    }
    deinit { NSStatusBar.system.removeStatusItem(item) }
    func update(_ phase: TrackingPhase) {
        self.phase = phase
        item.button?.toolTip = "BlinkMore: \(phase.title)"
        let closed = phase == .eyesClosed || Date() < blinkUntil
        let image = [.tracking, .eyesClosed].contains(phase) ? (closed ? closedEye : openEye) : idleMark
        image.isTemplate = true
        if item.button?.image !== image { item.button?.image = image }
        item.button?.appearsDisabled = ![.tracking, .eyesClosed, .calibrating].contains(phase)
    }
    func blink() {
        blinkUntil = Date().addingTimeInterval(0.12)
        update(phase ?? .tracking)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self = self else { return }; self.update(self.phase ?? .starting)
        }
    }
    private func eyeImage(_ name: String, symbol: String) -> NSImage {
        let url = Bundle.main.resourceURL?.appendingPathComponent("Icons/\(name).png")
        let image = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
        image.size = NSSize(width: 20, height: 20); image.isTemplate = true
        return image
    }
    private func add(_ title: String, _ key: String, enabled: Bool = true) {
        let entry = NSMenuItem(title: title, action: #selector(selected(_:)), keyEquivalent: "")
        entry.target = self; entry.representedObject = key; entry.isEnabled = enabled
        contextMenu.addItem(entry)
    }
    @objc private func clicked() {
        guard let button = item.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = contextMenu
            button.performClick(nil)
            item.menu = nil
        } else { onOpen?(0) }
    }
    @objc private func selected(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "open": onOpen?(0)
        case "settings": onOpen?(3)
        case "reminders": onCommand?(["action": "set", "key": "remindersEnabled", "value": sender.state != .on])
        case .some(let action): onCommand?(["action": action])
        default: break
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        let state = snapshot?() ?? [:]
        let stats = state["statistics"] as? [String: Any] ?? [:]
        let today = stats["today"] as? [String: Any] ?? [:]
        let preferences = state["preferences"] as? [String: Any] ?? [:]
        for entry in menu.items {
            switch entry.representedObject as? String {
            case "status": entry.title = phase?.title ?? "Starting camera"
            case "count": entry.title = "\(today["blinks"] as? Int ?? 0) blinks today"
            case "rate": entry.title = (stats["recentRate"] as? Double).map { String(format: "Recent rate: %.1f/min", $0) } ?? "Recent rate: collecting"
            case "relative": entry.title = (stats["relativePercent"] as? Double).map { String(format: "%+.0f%% vs your baseline", $0) } ?? "Baseline: collecting prior days"
            case "pause": entry.title = phase == .paused ? "Resume monitoring" : "Pause for 5 minutes"
            case "reminders": entry.state = preferences["remindersEnabled"] as? Bool == false ? .off : .on
            case "calibrate": entry.isEnabled = ![.paused, .starting, .cameraDenied, .cameraMissing, .cameraError].contains(phase ?? .starting)
            default: break
            }
        }
    }

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

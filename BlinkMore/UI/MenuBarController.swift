import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let contextMenu = NSMenu()
    private let resources: URL?
    private var phase: TrackingPhase?
    private var stateMarks: [String: NSImage] = [:]
    private var displayedImage: NSImage?
    private var blinkUntil = Date.distantPast
    private var blinkReset: DispatchWorkItem?
    private lazy var openEye = eyeImage("OpenEye", symbol: "eye")
    private lazy var closedEye = eyeImage("ClosedEye", symbol: "eye.slash")
    private lazy var idleMark = Self.mark(size: 20, source: resources?.appendingPathComponent("UI/eyesight.svg"))
    var onOpen: ((Int) -> Void)?
    var onCommand: (([String: Any]) -> Void)?
    var snapshot: (() -> [String: Any])?

    init(resources: URL? = nil) {
        self.resources = resources ?? Bundle.main.resourceURL
        super.init()
        let image = Self.mark(size: 22, source: self.resources?.appendingPathComponent("UI/eyesight.svg"))
        image.isTemplate = true
        displayedImage = image
        item.button?.image = image
        item.button?.isEnabled = true
        item.button?.appearsDisabled = false
        item.button?.target = self; item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("Eyesight, Starting camera")
        item.button?.setAccessibilityHelp("Click to open the dashboard. Right-click or Control-click to open the native menu.")
        item.button?.toolTip = "Eyesight: Starting camera. Click to open the dashboard. Right-click or Control-click for the menu."
        contextMenu.delegate = self; contextMenu.autoenablesItems = false
        add("Open Eyesight", "open")
        for key in ["status", "detail", "count", "rate", "relative"] { add("", key, enabled: false) }
        contextMenu.addItem(.separator())
        add("Live eye check", "live")
        add("Blink mirror", "blinkMirror")
        add("Camera setup…", "setup")
        add("Start a reset", "startReset")
        add("Pause for 5 minutes", "pause")
        add("Screen reminders", "reminders")
        add("Preview fade", "preview")
        add("Recalibrate eyes", "calibrate")
        contextMenu.addItem(.separator())
        add("Settings…", "settings")
    }
    deinit {
        blinkReset?.cancel()
        NSStatusBar.system.removeStatusItem(item)
    }
    func update(_ phase: TrackingPhase) {
        let changed = self.phase != phase
        self.phase = phase
        if changed {
            item.button?.toolTip = "Eyesight: \(phase.title). Click to open the dashboard. Right-click or Control-click for the menu."
            item.button?.setAccessibilityLabel("Eyesight, \(phase.title)")
        }
        guard phase == .tracking || phase == .eyesClosed else {
            blinkUntil = .distantPast
            blinkReset?.cancel()
            blinkReset = nil
            show(stateMark(phase))
            return
        }
        show(phase == .eyesClosed || Date() < blinkUntil ? closedEye : openEye)
    }
    func blink() {
        guard let phase = phase, phase == .tracking || phase == .eyesClosed else { return }
        blinkUntil = Date().addingTimeInterval(0.12)
        update(phase)
        blinkReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.blinkReset = nil
            if let phase = self.phase { self.update(phase) }
        }
        blinkReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: reset)
    }
    private func show(_ image: NSImage) {
        guard displayedImage !== image else { return }
        displayedImage = image
        item.button?.image = image
    }
    private func stateMark(_ phase: TrackingPhase) -> NSImage {
        if let image = stateMarks[phase.rawValue] { return image }
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        idleMark.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20))
        NSColor.clear.setFill()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .copy
        NSBezierPath(ovalIn: NSRect(x: 12, y: 0, width: 8, height: 8)).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.setStroke(); NSColor.labelColor.setFill()
        let path = NSBezierPath(); path.lineWidth = 1.2; path.lineCapStyle = .round
        switch phase {
        case .paused:
            path.move(to: NSPoint(x: 15, y: 1)); path.line(to: NSPoint(x: 15, y: 6))
            path.move(to: NSPoint(x: 18, y: 1)); path.line(to: NSPoint(x: 18, y: 6))
        case .cameraDenied, .cameraMissing, .cameraError:
            path.move(to: NSPoint(x: 16, y: 7)); path.line(to: NSPoint(x: 13, y: 1)); path.line(to: NSPoint(x: 19, y: 1)); path.close()
        case .noFace:
            path.appendOval(in: NSRect(x: 13, y: 0.5, width: 6, height: 6))
        case .multipleFaces:
            path.appendOval(in: NSRect(x: 12.5, y: 1.5, width: 4, height: 4)); path.appendOval(in: NSRect(x: 16, y: 2.5, width: 3, height: 3))
        case .delayed:
            path.appendOval(in: NSRect(x: 13, y: 0.5, width: 6, height: 6)); path.move(to: NSPoint(x: 16, y: 5)); path.line(to: NSPoint(x: 16, y: 3)); path.line(to: NSPoint(x: 18, y: 3))
        case .lowQuality:
            path.move(to: NSPoint(x: 13, y: 1)); path.line(to: NSPoint(x: 19, y: 6))
        case .starting, .calibrating:
            path.appendArc(withCenter: NSPoint(x: 16, y: 3.5), radius: 3, startAngle: 20, endAngle: 300)
        default: path.appendOval(in: NSRect(x: 13, y: 0.5, width: 6, height: 6))
        }
        path.stroke(); image.unlockFocus(); image.isTemplate = true
        stateMarks[phase.rawValue] = image
        return image
    }
    private func eyeImage(_ name: String, symbol: String) -> NSImage {
        let url = resources?.appendingPathComponent("Icons/\(name).png")
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
        case "live": onOpen?(4)
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
            case "detail": entry.title = phase?.detail ?? "Starting local camera processing."
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

    static func mark(size: CGFloat, color: NSColor = .labelColor, source: URL? = nil) -> NSImage {
        let url = source ?? Bundle.main.resourceURL?.appendingPathComponent("UI/eyesight.svg")
        let mark = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: "eye", accessibilityDescription: "Eyesight")!
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        mark.draw(in: NSRect(x: 0, y: size * 0.1875, width: size, height: size * 0.625))
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceIn)
        image.unlockFocus()
        return image
    }
}

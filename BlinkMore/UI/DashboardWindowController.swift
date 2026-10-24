import AppKit

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let snapshot: () -> [String: Any]
    private let command: ([String: Any]) -> Void
    private var timer: Timer?
    private var labels: [String: NSTextField] = [:]
    private var controls: [String: NSControl] = [:]
    private let tabs = NSSegmentedControl(labels: ["Blinks", "Eyes", "Settings"], trackingMode: .selectOne, target: nil, action: nil)
    private let pages = NSTabView()
    private let eyes = EyePairView()
    private let chart = WeekChartView()
    private var cameraIDs: [String] = []
    var onClose: (() -> Void)?

    init(snapshot: @escaping () -> [String: Any], command: @escaping ([String: Any]) -> Void) {
        self.snapshot = snapshot; self.command = command
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "BlinkMore"; window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 540)
        super.init(window: window)
        window.delegate = self; window.center()
        build(); refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true, self.window?.isMiniaturized == false else { return }
            self.refresh()
        }
    }
    required init?(coder: NSCoder) { nil }

    private func field(_ key: String, _ initial: String = "", size: CGFloat = 14, weight: NSFont.Weight = .regular, secondary: Bool = false, help: String = "") -> NSTextField {
        let value = dashboardLabel(initial, size: size, weight: weight, secondary: secondary)
        value.identifier = NSUserInterfaceItemIdentifier(key); value.toolTip = help; value.setAccessibilityHelp(help)
        labels[key] = value
        if size == 27 { value.tag = 27 }
        return value
    }
    private func button(_ title: String, _ action: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(pressed(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(action); button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 14)
        controls[action] = button
        return button
    }
    private func heading(_ text: String, help: String = "") -> NSTextField {
        let label = dashboardLabel(text, weight: .semibold); label.toolTip = help; label.setAccessibilityHelp(help); return label
    }
    private func metric(_ key: String, title: String, help: String) -> NSView {
        let value = field(key, "Collecting", size: 27, weight: .semibold, help: help)
        value.setAccessibilityLabel(title)
        let content = dashboardStack([dashboardLabel(title, secondary: true), value], spacing: 4)
        return DashboardCard(content)
    }
    private func equalRow(_ views: [NSView]) -> NSStackView {
        let row = dashboardStack(views, horizontal: true); row.distribution = .fillEqually; row.alignment = .height
        return row
    }
    private func page(_ title: String, _ contents: [NSView]) {
        let stack = DashboardDocumentStack(views: contents)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in contents { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = stack
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)])
        let item = NSTabViewItem(identifier: title); item.label = title; item.view = scroll; pages.addTabViewItem(item)
    }
    private func build() {
        guard let window = window else { return }
        let background = NSVisualEffectView(); background.material = .underWindowBackground; background.blendingMode = .behindWindow
        window.contentView = background
        let logo = NSImageView(image: MenuBarController.mark(size: 28)); logo.image?.isTemplate = true
        logo.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = dashboardStack([logo, dashboardLabel("BlinkMore", size: 19, weight: .semibold), spacer,
            dashboardLabel("AC only", secondary: true), button("Pause", "pause")], horizontal: true)
        let status = dashboardStack([eyes, dashboardStack([field("status", weight: .medium), field("detail", secondary: true)], spacing: 2),
            button("Calibrate", "calibrate"), button("Retry", "retry"), button("Allow camera", "cameraSettings")], horizontal: true)
        eyes.widthAnchor.constraint(equalToConstant: 114).isActive = true
        eyes.heightAnchor.constraint(equalToConstant: 42).isActive = true
        tabs.selectedSegment = 0; tabs.target = self; tabs.action = #selector(tabChanged)
        tabs.setAccessibilityLabel("Dashboard sections")
        tabs.segmentStyle = .rounded; tabs.font = .systemFont(ofSize: 14)
        pages.tabViewType = .noTabsNoBorder
        buildBlinks(); buildEyes(); buildSettings()
        let footer = field("notice", "On this Mac. Camera images are never saved.", secondary: true)
        let root = dashboardStack([header, status, tabs, pages, footer], spacing: 10)
        root.translatesAutoresizingMaskIntoConstraints = false; background.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12)])
        for view in [header, status, pages, footer] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        pages.setContentHuggingPriority(.defaultLow, for: .vertical)
        pages.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
    }
    private func buildBlinks() {
        let top = equalRow([
            metric("blinks", title: "Blinks today", help: "Both eyelids closed during one detected episode, then reopened within 1.2 seconds. Missed frames are excluded."),
            metric("recent", title: "Recent / min", help: "Blinks per tracked minute in the last 60 seconds. Needs 15 seconds of valid data."),
            metric("daily", title: "Today / min", help: "Blinks per tracked minute today. Needs 30 seconds of valid data."),
            metric("relative", title: "Vs your baseline", help: "Today's rate compared with your weighted rate over the preceding six days. Each day needs 30 seconds; the baseline needs five minutes total. This is a personal comparison, not a health target.")])
        let history = dashboardStack([heading("Daily blink rate", help: "Blinks per tracked minute. Empty days have no rate."), chart,
            field("baseline", secondary: true)], spacing: 6)
        chart.widthAnchor.constraint(equalTo: history.widthAnchor).isActive = true
        let types = equalRow([
            metric("leftOnly", title: "Left only", help: "Short closure of the camera's left eye landmark without a matching right closure."),
            metric("rightOnly", title: "Right only", help: "Short closure of the camera's right eye landmark without a matching left closure."),
            metric("long", title: "Long closures", help: "Detected bilateral closure episodes longer than 1.2 seconds. Counted on reopening, separately from blinks. Collection starts with this version."),
            metric("reminders", title: "Reminders", help: "Automatic cues. Manual fade previews are excluded.")])
        let totals = field("tracked", secondary: true)
        let actions = dashboardStack([button("Export history…", "export"), button("Delete history…", "reset")], horizontal: true)
        page("Blinks", [top, DashboardCard(history), types, totals, actions])
    }
    private func buildEyes() {
        let live = equalRow([
            metric("left", title: "Left openness", help: "Relative to the camera's left eye landmark's own open eye calibration. Not anatomical eye size."),
            metric("right", title: "Right openness", help: "Relative to the camera's right eye landmark's own open eye calibration."),
            metric("difference", title: "Movement difference", help: "Daily mean difference between independently calibrated openness values during tracked open eye time. Needs five seconds. Not a medical measurement.")])
        let closed = equalRow([
            metric("closedPercent", title: "Both eyes closed", help: "Share of calibrated tracking time with both eyelids classified as closed. Sampled at camera frame intervals; short closures can be missed. Collection starts with this version."),
            metric("openSeconds", title: "Open interval", help: "Current uninterrupted observed open eye time. A tracking gap resets this interval."),
            metric("latency", title: "Frame delay", help: "Capture to processed result, excluding screen rendering.")])
        let processing = dashboardStack([heading("Tracking"), field("processing"), field("reminder", secondary: true)], spacing: 6)
        let limits = dashboardStack([heading("Eye appearance"), dashboardLabel("Iris color requires a close image with controlled lighting.", secondary: true),
            dashboardLabel("Retina data requires specialized retinal imaging hardware.", secondary: true),
            dashboardLabel("This camera session measures eyelids, not eye health.", secondary: true)], spacing: 6)
        page("Eyes", [live, closed, DashboardCard(processing), DashboardCard(limits)])
    }
    private func preferenceRow(_ title: String, control: NSControl, key: String, help: String = "") -> NSView {
        control.identifier = NSUserInterfaceItemIdentifier(key); control.toolTip = help; control.setAccessibilityLabel(title)
        control.target = self; control.action = #selector(changed(_:)); control.font = .systemFont(ofSize: 14)
        controls[key] = control
        let label = dashboardLabel(title); label.toolTip = help
        label.widthAnchor.constraint(equalToConstant: 165).isActive = true
        let row = dashboardStack([label, control], horizontal: true)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return row
    }
    private func slider(_ title: String, key: String, range: ClosedRange<Double>, help: String) -> NSView {
        let control = NSSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        control.isContinuous = false
        let row = preferenceRow(title, control: control, key: key, help: help) as! NSStackView
        let value = field("setting-" + key, secondary: true)
        value.alignment = .right; value.widthAnchor.constraint(equalToConstant: 82).isActive = true
        row.addArrangedSubview(value)
        return row
    }
    private func buildSettings() {
        let toggle = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        let camera = NSPopUpButton(); let theme = NSPopUpButton()
        theme.addItems(withTitles: ["System", "Light", "Dark"])
        let color = NSColorWell(); color.color = .black
        color.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let rows = [
            preferenceRow("Screen reminders", control: toggle, key: "remindersEnabled"),
            slider("Without a blink", key: "reminderSeconds", range: 3...30, help: "Continuous observed open eye time before the reminder starts."),
            slider("Time to full tint", key: "fadeSeconds", range: 0.3...5, help: "Seconds from the start of a reminder to its full intensity."),
            slider("Tint intensity", key: "intensity", range: 0.15...0.9, help: "Opacity at full tint."),
            slider("Sensitivity", key: "sensitivity", range: 0...1, help: "Higher values detect smaller eyelid closures, but can classify squinting as closed."),
            preferenceRow("Tint color", control: color, key: "color"),
            preferenceRow("Camera", control: camera, key: "cameraID"),
            preferenceRow("Appearance", control: theme, key: "theme")]
        let content = dashboardStack(rows, spacing: 10)
        for row in rows { row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        let actions = dashboardStack([button("Preview 2 second fade", "preview"), button("Recalibrate eyes", "recalibrate")], horizontal: true)
        let note = dashboardLabel("AC starts monitoring. Battery stops the app and camera.", secondary: true)
        page("Settings", [DashboardCard(content), actions, note])
    }
    func selectTab(_ index: Int) {
        guard (0..<pages.numberOfTabViewItems).contains(index) else { return }
        tabs.selectedSegment = index; pages.selectTabViewItem(at: index)
    }
    @objc private func tabChanged() { selectTab(tabs.selectedSegment) }
    @objc private func pressed(_ sender: NSButton) {
        let action = sender.identifier?.rawValue ?? ""
        command(["action": action == "recalibrate" ? "calibrate" : action]); refresh()
    }
    @objc private func changed(_ sender: NSControl) {
        guard let key = sender.identifier?.rawValue else { return }
        let value: Any
        switch sender {
        case let slider as NSSlider:
            let step = key == "reminderSeconds" ? 1.0 : key == "fadeSeconds" ? 0.1 : 0.05
            value = (slider.doubleValue / step).rounded() * step
        case let popup as NSPopUpButton:
            value = key == "theme" ? ["system", "light", "dark"][max(0, popup.indexOfSelectedItem)] : cameraIDs[max(0, popup.indexOfSelectedItem)]
        case let button as NSButton: value = button.state == .on
        case let color as NSColorWell:
            guard let rgb = color.color.usingColorSpace(.sRGB) else { return }
            value = String(format: "#%02x%02x%02x", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        default: return
        }
        command(["action": "set", "key": key, "value": value]); refresh()
    }
    func refresh() {
        let state = snapshot()
        let phase = TrackingPhase(rawValue: state["phase"] as? String ?? "") ?? .starting
        let prefs = state["preferences"] as? [String: Any] ?? [:]
        let statistics = state["statistics"] as? [String: Any] ?? [:]
        let today = statistics["today"] as? [String: Any] ?? [:]
        func number(_ value: Any?, suffix: String = "", digits: Int = 1) -> String {
            guard let value = value as? Double, value.isFinite else { return "Collecting" }
            return String(format: "%.*f", digits, value) + suffix
        }
        func set(_ key: String, _ text: String) {
            if labels[key]?.stringValue != text { labels[key]?.stringValue = text }
            if labels[key]?.tag == 27 { labels[key]?.font = .systemFont(ofSize: text == "Collecting" || text == "Waiting" ? 16 : 27, weight: .semibold) }
        }
        let tracking = [.tracking, .eyesClosed].contains(phase)
        set("status", phase.title)
        set("detail", phase == .calibrating ? "\(Int((state["calibration"] as? Double ?? 0) * 100))% calibrated" : phase.detail)
        labels["detail"]?.toolTip = phase.detail
        eyes.active = tracking; eyes.left = state["left"] as? Double ?? 0; eyes.right = state["right"] as? Double ?? 0; eyes.needsDisplay = true
        eyes.setAccessibilityLabel(tracking ? "Left eye \(Int(eyes.left * 100)) percent open. Right eye \(Int(eyes.right * 100)) percent open." : phase.title)
        (controls["pause"] as? NSButton)?.title = phase == .paused ? "Resume" : "Pause"
        controls["retry"]?.isHidden = ![.cameraMissing, .cameraError, .delayed].contains(phase)
        controls["cameraSettings"]?.isHidden = phase != .cameraDenied
        controls["calibrate"]?.isEnabled = ![.starting, .paused, .cameraDenied, .cameraError, .cameraMissing].contains(phase)
        controls["recalibrate"]?.isEnabled = controls["calibrate"]?.isEnabled ?? false
        set("blinks", "\(today["blinks"] as? Int ?? 0)")
        set("recent", number(statistics["recentRate"]))
        set("daily", number(today["blinkRate"]))
        if let relative = statistics["relativePercent"] as? Double { set("relative", String(format: "%+.0f%%", relative)) }
        else { set("relative", "Collecting") }
        set("baseline", (statistics["baselineRate"] as? Double).map { String(format: "Your baseline: %.1f blinks/min over prior tracked days", $0) } ?? "Baseline needs 5 tracked minutes across prior days.")
        set("leftOnly", "\(today["leftClosures"] as? Int ?? 0)"); set("rightOnly", "\(today["rightClosures"] as? Int ?? 0)")
        set("long", (today["longClosures"] as? Int).map(String.init) ?? "Collecting")
        set("reminders", "\(today["reminders"] as? Int ?? 0)")
        let seconds = today["trackedSeconds"] as? Double ?? 0
        set("tracked", "Tracked today: \(Int(seconds / 3600))h \(Int(seconds / 60) % 60)m, recent: \(Int(statistics["recentSeconds"] as? Double ?? 0))/60s")
        set("left", tracking ? number((state["left"] as? Double).map { $0 * 100 }, suffix: "%", digits: 0) : "Waiting")
        set("right", tracking ? number((state["right"] as? Double).map { $0 * 100 }, suffix: "%", digits: 0) : "Waiting")
        set("difference", number(today["asymmetry"], suffix: "%"))
        set("closedPercent", number(today["closedPercent"], suffix: "%"))
        set("openSeconds", tracking ? number(state["openSeconds"], suffix: "s") : "Waiting")
        set("latency", tracking ? number(state["latencyMs"], suffix: " ms", digits: 0) : "Waiting")
        set("processing", "\(number(state["fps"])) frames/s, p95 \(number(state["p95Ms"], digits: 0)) ms, \(state["dropped"] as? Int ?? 0) dropped")
        let reminder: String
        if prefs["remindersEnabled"] as? Bool == false { reminder = "Screen reminders off" }
        else if state["fading"] as? Bool == true { reminder = "Reminder active. Close your eyes to clear." }
        else if state["reminderState"] as? String == "waitingForBlink" { reminder = "Blink to start the next reminder interval." }
        else { reminder = tracking ? "Next reminder in \(number(max(0, (prefs["reminderSeconds"] as? Double ?? 6) - (state["openSeconds"] as? Double ?? 0)), suffix: "s"))" : "Reminders wait for fresh eye data." }
        set("reminder", reminder)
        let week = statistics["week"] as? [[String: Any]] ?? []
        if !NSDictionary(dictionary: ["week": chart.week]).isEqual(to: ["week": week]) { chart.week = week }
        for key in ["reminderSeconds", "fadeSeconds", "intensity", "sensitivity"] {
            if let value = prefs[key] as? Double, let slider = controls[key] as? NSSlider {
                if window?.firstResponder !== slider { slider.doubleValue = value }
                set("setting-" + key, key == "intensity" || key == "sensitivity" ? number(value * 100, suffix: "%", digits: 0) : number(value, suffix: "s", digits: key == "reminderSeconds" ? 0 : 1))
            }
        }
        (controls["remindersEnabled"] as? NSButton)?.state = prefs["remindersEnabled"] as? Bool == false ? .off : .on
        let theme = prefs["theme"] as? String ?? "system"
        (controls["theme"] as? NSPopUpButton)?.selectItem(at: ["system", "light", "dark"].firstIndex(of: theme) ?? 0)
        let camera = controls["cameraID"] as? NSPopUpButton
        let cameras = state["cameras"] as? [[String: String]] ?? []
        let ids = [""] + cameras.compactMap { $0["id"] }
        if ids != cameraIDs {
            cameraIDs = ids; camera?.removeAllItems(); camera?.addItems(withTitles: ["Automatic"] + cameras.map { $0["name"] ?? "Camera" })
        }
        camera?.selectItem(at: cameraIDs.firstIndex(of: prefs["cameraID"] as? String ?? "") ?? 0)
        if let hex = prefs["color"] as? String, let rgb = UInt32(hex.dropFirst(), radix: 16) {
            (controls["color"] as? NSColorWell)?.color = NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
        }
        let warning = statistics["warning"] as? String ?? ""
        let notice = state["notice"] as? String ?? ""
        set("notice", !notice.isEmpty ? notice : !warning.isEmpty ? warning : "On this Mac. Camera images are never saved.")
        labels["notice"]?.toolTip = labels["notice"]?.stringValue
    }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); onClose?() }
    func takeSnapshot(completion: @escaping (NSImage?) -> Void) {
        guard let view = window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { completion(nil); return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size); image.addRepresentation(bitmap); completion(image)
    }
}

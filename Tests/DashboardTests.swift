import AppKit

@main enum DashboardTests {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("Native dashboard tests passed: compact layout, both themes, every state, native controls, blink icon, context menu"); exit(0) }
            catch { fputs("Native dashboard tests failed: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("test-results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var commands: [[String: Any]] = []
        let week: [[String: Any]] = (0..<7).map { index -> [String: Any] in
            ["day": "2026-10-\(18 + index)", "blinkRate": 10.0 + Double(index) / 2,
             "blinks": 130 + index * 19, "trackedSeconds": 1200.0]
        }
        let today: [String: Any] = ["blinks": 240, "trackedSeconds": 1200.0, "blinkRate": 12.0, "asymmetry": 3.7,
            "leftClosures": 2, "rightClosures": 1, "longClosures": 3, "closedPercent": 1.4, "reminders": 8]
        var state: [String: Any] = ["phase": "tracking", "left": 1.0, "right": 0.93, "calibration": 1.0,
            "openSeconds": 2.4, "latencyMs": 35.2, "p95Ms": 55.0, "fps": 12.5, "dropped": 0, "fading": false,
            "notice": "QA fixture. No camera is used.",
            "preferences": ["reminderSeconds": 6.0, "fadeSeconds": 1.5, "intensity": 0.65, "sensitivity": 0.5, "remindersEnabled": true, "theme": "system", "cameraID": "", "color": "#006fe6"],
            "statistics": ["today": today,
                "week": week, "warning": "", "baselineRate": 10.0, "relativePercent": 20.0, "recentRate": 14.0, "recentSeconds": 52.0],
            "cameras": [["id": "test-camera", "name": "QA camera"]]]
        let controller = DashboardWindowController(snapshot: { state }, command: { commands.append($0) })
        controller.showWindow(nil)
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func find<T: NSView>(_ id: String, _: T.Type = T.self) -> T {
            guard let result = views(controller.window!.contentView!).first(where: { $0.identifier?.rawValue == id }) as? T else { preconditionFailure("Missing control \(id)") }
            return result
        }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            controller.window?.appearance = NSAppearance(named: theme)
            for tab in 0..<3 {
                controller.selectTab(tab); controller.refresh()
                try await Task.sleep(for: .milliseconds(120))
                controller.window?.contentView?.layoutSubtreeIfNeeded()
                let image: NSImage? = await withCheckedContinuation { continuation in controller.takeSnapshot { continuation.resume(returning: $0) } }
                guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                let name = theme == .darkAqua ? "dark" : "light"
                try png.write(to: output.appendingPathComponent("dashboard-\(name)-\(tab).png"))
                for text in views(controller.window!.contentView!).compactMap({ $0 as? NSTextField }).filter({ !$0.isHiddenOrHasHiddenAncestor }) {
                    precondition((text.font?.pointSize ?? 14) >= 14)
                    precondition(text.frame.width > 0, "Collapsed text: \(text.stringValue)")
                }
            }
        }
        controller.selectTab(0)
        precondition(find("blinks", NSTextField.self).stringValue == "240")
        precondition(find("relative", NSTextField.self).stringValue == "+20%")
        for phase in [TrackingPhase.starting, .calibrating, .tracking, .eyesClosed, .noFace, .multipleFaces, .lowQuality, .delayed, .paused, .cameraDenied, .cameraMissing, .cameraError] {
            state["phase"] = phase.rawValue; controller.refresh()
            precondition(find("status", NSTextField.self).stringValue == phase.title)
            precondition(find("cameraSettings", NSButton.self).isHidden == (phase != .cameraDenied))
            precondition(find("pause", NSButton.self).title == (phase == .paused ? "Resume" : "Pause"))
        }
        state["phase"] = "tracking"; state["reminderState"] = "waitingForBlink"
        controller.selectTab(1); controller.refresh()
        precondition(find("reminder", NSTextField.self).stringValue == "Blink to start the next reminder interval.")
        controller.selectTab(2); controller.refresh()
        let sensitivity = find("sensitivity", NSSlider.self); sensitivity.doubleValue = 0.8
        NSApp.sendAction(sensitivity.action!, to: sensitivity.target, from: sensitivity)
        let toggle = find("remindersEnabled", NSButton.self); toggle.state = .off
        NSApp.sendAction(toggle.action!, to: toggle.target, from: toggle)
        let theme = find("theme", NSPopUpButton.self); theme.selectItem(at: 2)
        NSApp.sendAction(theme.action!, to: theme.target, from: theme)
        let camera = find("cameraID", NSPopUpButton.self); camera.selectItem(at: 1)
        NSApp.sendAction(camera.action!, to: camera.target, from: camera)
        let color = find("color", NSColorWell.self); color.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        NSApp.sendAction(color.action!, to: color.target, from: color)
        find("preview", NSButton.self).performClick(nil)
        precondition(commands.contains { $0["key"] as? String == "sensitivity" && $0["value"] as? Double == 0.8 })
        precondition(commands.contains { $0["key"] as? String == "remindersEnabled" && $0["value"] as? Bool == false })
        precondition(commands.contains { $0["key"] as? String == "theme" && $0["value"] as? String == "dark" })
        precondition(commands.contains { $0["key"] as? String == "cameraID" && $0["value"] as? String == "test-camera" })
        precondition(commands.contains { $0["key"] as? String == "color" && $0["value"] as? String == "#336699" })
        precondition(commands.contains { $0["action"] as? String == "preview" })
        controller.window?.setContentSize(NSSize(width: 640, height: 512))
        for tab in 0..<3 {
            controller.selectTab(tab); controller.refresh()
            try await Task.sleep(for: .milliseconds(80))
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            let scroll = views(controller.window!.contentView!).compactMap { $0 as? NSScrollView }.first { !$0.isHiddenOrHasHiddenAncestor }!
            precondition(abs((scroll.documentView?.frame.width ?? 0) - scroll.contentView.bounds.width) < 1)
            precondition(!scroll.hasHorizontalScroller)
            if tab == 2 {
                precondition(find("sensitivity", NSSlider.self).frame.width >= 140)
            }
        }
        let menu = MenuBarController(); menu.snapshot = { state }
        var opened: [Int] = []; menu.onOpen = { opened.append($0) }; menu.onCommand = { commands.append($0) }
        menu.update(.tracking); let open = menu.item.button!.image!
        menu.update(.eyesClosed); precondition(menu.item.button!.image !== open)
        menu.update(.tracking); precondition(menu.item.button!.image === open)
        menu.blink(); precondition(menu.item.button!.image !== open)
        try await Task.sleep(for: .milliseconds(220)); precondition(menu.item.button!.image === open)
        menu.item.button?.performClick(nil); precondition(opened == [0])
        menu.menuNeedsUpdate(menu.contextMenu)
        precondition(menu.contextMenu.items.contains { $0.title == "240 blinks today" })
        for key in ["settings", "pause", "reminders"] {
            let item = menu.contextMenu.items.first { $0.representedObject as? String == key }!
            NSApp.sendAction(item.action!, to: item.target, from: item)
        }
        precondition(opened == [0, 2])
        precondition(commands.contains { $0["action"] as? String == "pause" })
        controller.close()
    }
}

import AppKit
import WebKit

@main enum DashboardTests {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("Hybrid dashboard tests passed: primitives, themes, rings, geometry, milestones, native bridge, menu, compact layout"); exit(0) }
            catch { fputs("Dashboard tests failed: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("test-results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let week: [[String: Any]] = (0..<7).map { i -> [String: Any] in
            ["day": "2026-10-\(18 + i)", "blinkRate": 10.0 + Double(i) / 2, "blinks": 130 + i * 19, "trackedSeconds": 1200.0]
        }
        let points: [[Double]] = (0..<8).map { i -> [Double] in
            let angle = Double(i) * .pi / 4
            return [0.32 + 0.08 * cos(angle), 0.65 + 0.014 * sin(angle)]
        }
        let today: [String: Any] = ["blinks": 240, "trackedSeconds": 1200.0, "blinkRate": 12.0, "asymmetry": 3.7,
            "leftClosures": 2, "rightClosures": 1, "longClosures": 3, "closedPercent": 1.4, "reminders": 8]
        var state: [String: Any] = ["phase": "tracking", "title": "Tracking", "detail": "Synthetic QA data. No camera is used.", "left": 1.0, "right": 0.93, "calibration": 1.0,
            "openSeconds": 2.4, "latencyMs": 35.2, "p95Ms": 55.0, "fps": 12.5, "dropped": 0, "fading": false, "frameAgeMs": 76.0,
            "notice": "Synthetic QA data. No camera is used.", "actualTheme": "light",
            "geometry": ["left": points, "right": points.map { [$0[0] + 0.35, $0[1]] }, "width": 210.0, "height": 310.0, "confidence": 0.98, "leftAperture": 0.258, "rightAperture": 0.248],
            "preferences": ["reminderSeconds": 6.0, "fadeSeconds": 1.5, "intensity": 0.65, "sensitivity": 0.5, "remindersEnabled": true, "theme": "system", "cameraID": "", "color": "#006fe6", "blinkGoal": 300.0, "minuteGoal": 30.0, "dayGoal": 3.0],
            "statistics": ["today": today, "week": week, "warning": "", "baselineRate": 10.0, "relativePercent": 20.0, "recentRate": 14.0, "recentSeconds": 52.0, "lifetime": ["blinks": 1900, "trackedSeconds": 9200.0, "days": 5]],
            "cameras": [["id": "test-camera", "name": "QA camera"]]]
        var commands: [[String: Any]] = []
        let controller = DashboardWindowController(resources: root.appendingPathComponent("BlinkMore/Resources/UI"), snapshot: { state }, command: { message in
            commands.append(message)
            if message["action"] as? String == "set", let key = message["key"] as? String, var preferences = state["preferences"] as? [String: Any] {
                preferences[key] = message["value"]; state["preferences"] = preferences
            }
        })
        controller.selectTab(2); controller.showWindow(nil)
        let view = controller.window!.contentView as! WKWebView
        for _ in 0..<100 {
            if commands.contains(where: { $0["action"] as? String == "ready" }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(commands.contains { $0["action"] as? String == "ready" })
        func js(_ source: String) async throws -> Any? {
            try await withCheckedThrowingContinuation { continuation in
                view.callAsyncJavaScript(source, arguments: [:], in: nil, in: .page) { result in continuation.resume(with: result.map { Optional($0) }) }
            }
        }
        func expect<T: Equatable>(_ source: String, _ expected: T) async throws {
            let value = try await js(source)
            guard let actual = value as? T else { preconditionFailure("Wrong result type: \(source)") }
            precondition(actual == expected, "Unexpected result: \(source)")
        }
        try await Task.sleep(for: .milliseconds(150))
        try await expect("return document.querySelector('[aria-selected=true]').dataset.tab", "2")
        for theme in ["light", "dark"] {
            state["actualTheme"] = theme; controller.window?.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
            controller.refresh(); try await Task.sleep(for: .milliseconds(350))
            for tab in 0..<3 {
                controller.selectTab(tab); controller.refresh(); try await Task.sleep(for: .milliseconds(350))
                let minText = try await js("return Math.min(...[...document.querySelectorAll('main span,main p,main label,main small,main button,main strong,main code,main dt,main dd,main summary')].filter(e=>e.getClientRects().length).map(e=>parseFloat(getComputedStyle(e).fontSize)))") as! Double
                precondition(minText >= 14)
                try await expect("return document.documentElement.scrollWidth <= innerWidth + 1", true)
                if tab == 1 {
            let contrast = try await js("const canvas=document.createElement('canvas'), ctx=canvas.getContext('2d'); canvas.width=2; canvas.height=1; const rgb=color=>{ctx.fillStyle=color;ctx.fillRect(0,0,1,1);return [...ctx.getImageData(0,0,1,1).data].slice(0,3).map(v=>{v/=255;return v<=0.04045?v/12.92:((v+0.055)/1.055)**2.4})}; const lum=c=>0.2126*c[0]+0.7152*c[1]+0.0722*c[2]; const bg=lum(rgb(getComputedStyle(document.body).backgroundColor)); return Math.min(...['.model-text','.text-action'].map(sel=>{const fg=lum(rgb(getComputedStyle(document.querySelector(sel)).color));return (Math.max(bg,fg)+0.05)/(Math.min(bg,fg)+0.05)}))") as! Double
            precondition(contrast >= 4.5)
                }
                let image: NSImage? = await withCheckedContinuation { continuation in controller.takeSnapshot { continuation.resume(returning: $0) } }
                guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: output.appendingPathComponent("dashboard-\(theme)-\(tab).png"))
            }
        }
        controller.selectTab(0); controller.refresh(); try await Task.sleep(for: .milliseconds(350))
        try await expect("return document.getElementById('ring-center-value').textContent", "240")
        try await expect("return document.querySelectorAll('.achievement.earned').length", 3)
        let ringProgress = try await js("const c=document.getElementById('ring-blinks'); return 1-parseFloat(getComputedStyle(c).strokeDashoffset)/(2*Math.PI*Number(c.getAttribute('r')))") as! Double
        precondition(abs(ringProgress - 0.8) < 0.001)
        try await expect("return getComputedStyle(document.documentElement).getPropertyValue('--blur-card').trim()", "12px")
        for phase in [TrackingPhase.starting, .calibrating, .tracking, .eyesClosed, .noFace, .multipleFaces, .lowQuality, .delayed, .paused, .cameraDenied, .cameraMissing, .cameraError] {
            state["phase"] = phase.rawValue; state["title"] = phase.title; state["detail"] = phase.detail; controller.refresh()
            try await Task.sleep(for: .milliseconds(70))
            try await expect("return document.getElementById('tracking-title').textContent", phase.title)
            try await expect("return !document.getElementById('camera-settings').hidden", (phase == .cameraDenied))
        }
        state["phase"] = "tracking"; state["frameAgeMs"] = 76.0; state["reminderState"] = "waitingForBlink"
        controller.selectTab(1); controller.refresh(); try await Task.sleep(for: .milliseconds(150))
        try await expect("return document.querySelectorAll('#left-points circle').length", 8)
        try await expect("return document.getElementById('left-aperture').textContent", "0.258")
        try await expect("return document.getElementById('reminder-state').textContent", "Blink to start the next reminder interval.")
        state["frameAgeMs"] = 900.0; controller.refresh(); try await Task.sleep(for: .milliseconds(150))
        try await expect("return document.getElementById('left-outline').getAttribute('d')", "")
        try await expect("return document.querySelectorAll('#left-points circle').length", 0)
        state["reducedMotion"] = true; controller.refresh(); try await Task.sleep(for: .milliseconds(150))
        try await expect("return getComputedStyle(document.getElementById('ring-blinks')).transitionDuration", "0s")
        controller.selectTab(2)
        _ = try await js("const g=document.getElementById('setting-blinkGoal'); g.value='500'; g.dispatchEvent(new Event('change')); const s=document.getElementById('setting-sensitivity'); s.value='0.8'; s.dispatchEvent(new Event('change')); const t=document.getElementById('appearance'); t.value='dark'; t.dispatchEvent(new Event('change')); document.querySelector('[data-action=preview]').click(); const check=document.getElementById('reminders-enabled'); check.checked=false; check.dispatchEvent(new Event('change'))")
        try await Task.sleep(for: .milliseconds(150))
        precondition(commands.contains { $0["key"] as? String == "blinkGoal" && $0["value"] as? Double == 500 })
        precondition(commands.contains { $0["key"] as? String == "sensitivity" && $0["value"] as? Double == 0.8 })
        precondition(commands.contains { $0["key"] as? String == "theme" && $0["value"] as? String == "dark" })
        precondition(commands.contains { $0["key"] as? String == "remindersEnabled" && $0["value"] as? Bool == false })
        precondition(commands.contains { $0["action"] as? String == "preview" })
        controller.window?.setContentSize(NSSize(width: 720, height: 560))
        for tab in 0..<3 {
            controller.selectTab(tab); try await Task.sleep(for: .milliseconds(150))
            try await expect("return document.documentElement.scrollWidth <= innerWidth+1", true)
        }
        _ = try await js("document.querySelector('[data-tab=\"2\"]').dispatchEvent(new KeyboardEvent('keydown',{key:'Home',bubbles:true}))")
        try await expect("return document.querySelector('[aria-selected=true]').dataset.tab", "0")
        let menu = MenuBarController(); menu.snapshot = { state }; var opened: [Int] = []
        menu.onOpen = { opened.append($0) }; menu.onCommand = { commands.append($0) }
        menu.update(.tracking); let open = menu.item.button!.image!
        menu.update(.eyesClosed); precondition(menu.item.button!.image !== open)
        menu.update(.tracking); precondition(menu.item.button!.image === open)
        menu.blink(); precondition(menu.item.button!.image !== open)
        try await Task.sleep(for: .milliseconds(220)); precondition(menu.item.button!.image === open)
        menu.item.button?.performClick(nil); precondition(opened == [0])
        menu.menuNeedsUpdate(menu.contextMenu); precondition(menu.contextMenu.items.contains { $0.title == "240 blinks today" })
        let settings = menu.contextMenu.items.first { $0.representedObject as? String == "settings" }!
        NSApp.sendAction(settings.action!, to: settings.target, from: settings); precondition(opened == [0, 2])
        controller.close()
    }
}

import AppKit
import WebKit

@main enum DashboardTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("Dashboard tests passed: both themes, every tracking state, native controls, layout, keyboard tabs"); exit(0) }
            catch { fputs("Dashboard tests failed: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }

    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("test-results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var commands: [[String: Any]] = []
        var state: [String: Any] = ["phase": "tracking", "title": "Tracking comfortably", "detail": "QA fixture. No camera is used.", "left": 1.0, "right": 0.93, "closedMask": 0,
            "calibration": 1.0, "openSeconds": 2.4, "latencyMs": 35.2, "p95Ms": 55.0, "fps": 29.5, "dropped": 0, "fading": false,
            "actualTheme": "light", "notice": "",
            "preferences": ["reminderSeconds": 6.0, "fadeSeconds": 1.5, "intensity": 0.65, "sensitivity": 0.5, "remindersEnabled": true, "theme": "system", "cameraID": "", "color": "#000000"],
            "statistics": ["today": ["blinks": 240, "trackedSeconds": 1200.0, "blinkRate": 12.0, "asymmetry": 3.7, "leftClosures": 2, "rightClosures": 1, "reminders": 8], "week": (0..<7).map { ["day": "2026-10-\(17 + $0)", "blinks": 130 + $0 * 19, "trackedSeconds": 1200, "asymmetry": 3.7] }, "warning": ""],
            "cameras": [["id": "test-camera", "name": "QA camera"]]]
        let controller = DashboardWindowController(resources: root.appendingPathComponent("BlinkMore/Resources/UI"), snapshot: { state }, command: { commands.append($0) })
        controller.showWindow(nil)
        let view = controller.window!.contentView as! WKWebView
        for _ in 0..<100 {
            if commands.contains(where: { $0["action"] as? String == "ready" }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(commands.contains(where: { $0["action"] as? String == "ready" }))
        func js(_ source: String) async throws -> Any? {
            try await withCheckedThrowingContinuation { continuation in
                view.callAsyncJavaScript(source, arguments: [:], in: nil, in: .page) { result in
                    continuation.resume(with: result.map { Optional($0) })
                }
            }
        }
        for theme in ["light", "dark"] {
            state["actualTheme"] = theme; controller.refresh()
            try await Task.sleep(for: .milliseconds(300))
            let iconWidth = try await js("return document.querySelector('#theme-cycle svg').getBBox().width") as! Double
            precondition(iconWidth > 10)
            let actual = try await js("return document.documentElement.classList.contains('dark')") as! Bool
            precondition(actual == (theme == "dark"))
            for tab in ["overview", "activity", "settings"] {
                _ = try await js("document.querySelector('[data-tab=\"\(tab)\"]').click()")
                try await Task.sleep(for: .milliseconds(150))
                let image: NSImage? = await withCheckedContinuation { continuation in controller.takeSnapshot { continuation.resume(returning: $0) } }
                guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: output.appendingPathComponent("dashboard-\(theme)-\(tab).png"))
                let overflow = try await js("return document.documentElement.scrollWidth > innerWidth + 1") as! Bool
                precondition(!overflow)
                let minText = try await js("return Math.min(...[...document.querySelectorAll('main span,main p,main label,main small,main button,main td,main th')].filter(e=>e.getClientRects().length).map(e=>parseFloat(getComputedStyle(e).fontSize)))") as! Double
                precondition(minText >= 14)
            }
        }
        _ = try await js("document.querySelector('[data-tab=overview]').click()")
        for phase in [TrackingPhase.starting, .calibrating, .tracking, .eyesClosed, .noFace, .multipleFaces, .lowQuality, .delayed, .paused, .cameraDenied, .cameraMissing, .cameraError] {
            state["phase"] = phase.rawValue; state["title"] = phase.title; state["detail"] = phase.detail
            controller.refresh(); try await Task.sleep(for: .milliseconds(50))
            let title = try await js("return document.getElementById('tracking-title').textContent") as! String
            precondition(title == phase.title)
            let permissionVisible = try await js("return !document.getElementById('camera-settings').hidden") as! Bool
            precondition(permissionVisible == (phase == .cameraDenied))
        }
        _ = try await js("document.querySelector('[data-tab=settings]').click(); document.querySelector('[data-theme=dark]').click(); const s=document.getElementById('sensitivity'); s.value='0.8'; s.dispatchEvent(new Event('change')); document.querySelector('[data-action=preview]').click()")
        try await Task.sleep(for: .milliseconds(100))
        precondition(commands.contains(where: { $0["key"] as? String == "theme" && $0["value"] as? String == "dark" }))
        precondition(commands.contains(where: { $0["key"] as? String == "sensitivity" && $0["value"] as? Double == 0.8 }))
        precondition(commands.contains(where: { $0["action"] as? String == "preview" }))
        _ = try await js("document.querySelector('[data-tab=settings]').dispatchEvent(new KeyboardEvent('keydown',{key:'Home',bubbles:true}))")
        let tab = try await js("return document.querySelector('[aria-selected=true]').dataset.tab") as! String
        precondition(tab == "overview")
        controller.window?.setContentSize(NSSize(width: 780, height: 650))
        try await Task.sleep(for: .milliseconds(100))
        let narrowOverflow = try await js("return document.documentElement.scrollWidth > innerWidth + 1") as! Bool
        precondition(!narrowOverflow)
        controller.close()
    }
}

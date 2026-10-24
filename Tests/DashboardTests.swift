import AppKit
import WebKit

@main enum DashboardTests {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("Optical dashboard passed: themes, compact fit, gauges, milestones, rhythm, exercise controls, geometry, native menu and eye") ; exit(0) }
            catch { fputs("Dashboard tests failed: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath), output = root.appendingPathComponent("test-results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let week: [[String: Any]] = (0..<7).map { i in
            var record: [String: Any] = ["day": "2026-10-\(18 + i)", "blinkRate": 10.0 + Double(i) / 2, "blinks": 130 + i * 19, "trackedSeconds": 1200.0]
            if i < 2 { record["blinkRate"] = NSNull(); record["blinks"] = 0; record["trackedSeconds"] = 0.0 }
            return record
        }
        let points: [[Double]] = (0..<8).map { i in
            let angle = Double(i) * .pi / 4
            return [0.32 + 0.08 * cos(angle), 0.65 + 0.014 * sin(angle)]
        }
        let bins: [[String: Any]] = (0..<60).map { i in ["tracked": (18...25).contains(i) ? 0.0 : 1.0, "blinks": [2,7,11,16,29,34,38,43,48,52,57].contains(i) ? 1 : 0] }
        let today: [String: Any] = ["blinks": 240, "trackedSeconds": 1200.0, "blinkRate": 12.0, "asymmetry": 3.7, "leftClosures": 2, "rightClosures": 1, "longClosures": 3, "closedPercent": 1.4, "reminders": 8, "resets": 2]
        var state: [String: Any] = ["phase": "tracking", "title": "Tracking", "detail": "Both eyes visible.", "left": 1.0, "right": 0.93, "calibration": 1.0, "openSeconds": 2.4,
            "latencyMs": 35.2, "p95Ms": 55.0, "fps": 12.5, "dropped": 0, "fading": false, "frameAgeMs": 76.0, "notice": "Synthetic QA data. No camera is used.", "actualTheme": "light",
            "exercise": ["phase": "idle", "step": "blink", "remaining": 10.0, "progress": 0.0, "due": false],
            "geometry": ["left": points, "right": points.map { [$0[0] + 0.35, $0[1]] }, "width": 210.0, "height": 310.0, "confidence": 0.98, "leftAperture": 0.258, "rightAperture": 0.248],
            "preferences": ["reminderSeconds": 6.0, "fadeSeconds": 1.5, "intensity": 0.65, "sensitivity": 0.5, "remindersEnabled": true, "theme": "system", "cameraID": "", "color": "#006fe6", "minuteGoal": 30.0, "dayGoal": 3.0, "exerciseMinutes": 20.0, "exercisesEnabled": false],
            "statistics": ["today": today, "week": week, "warning": "", "baselineRate": 10.0, "relativePercent": 20.0, "recentRate": 12.7, "recentSeconds": 52.0, "recentBins": bins, "lifetime": ["blinks": 1900, "trackedSeconds": 9200.0, "days": 5, "resets": 6]],
            "cameras": [["id": "test-camera", "name": "QA camera"]]]
        var commands: [[String: Any]] = []
        let controller = DashboardWindowController(resources: root.appendingPathComponent("BlinkMore/Resources/UI"), snapshot: { state }, command: { message in
            commands.append(message)
            if message["action"] as? String == "set", let key = message["key"] as? String, var preferences = state["preferences"] as? [String: Any] {
                preferences[key] = message["value"]; state["preferences"] = preferences
            }
        })
        controller.selectTab(3); controller.showWindow(nil)
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
            let actual = try await js(source) as? T
            precondition(actual == expected, "Unexpected result: \(source), got \(String(describing: actual))")
        }
        func refresh() async throws { controller.refresh(); try await Task.sleep(for: .milliseconds(250)) }
        func screenshot(_ name: String) async throws {
            let image: NSImage? = await withCheckedContinuation { continuation in controller.takeSnapshot { continuation.resume(returning: $0) } }
            guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }
        try await refresh()
        try await expect("await document.fonts.load('500 21px Comfortaa'); return [...document.fonts].some(f=>f.family==='Comfortaa' && f.status==='loaded')", true)
        try await expect("return document.querySelector('.identity h1').textContent", "eyesight")
        try await expect("const image=document.querySelector('.logo'); await image.decode(); return image.complete && image.naturalWidth > 0", true)
        let brandURL = root.appendingPathComponent("BlinkMore/Resources/UI/eyesight.svg")
        precondition(NSImage(contentsOf: brandURL) != nil)
        let nativeMark = MenuBarController.mark(size: 64, color: .white, source: brandURL)
        precondition(nativeMark.tiffRepresentation != nil)
        try await expect("return document.querySelector('[aria-selected=true]').dataset.tab", "3")
        for theme in ["light", "dark"] {
            state["actualTheme"] = theme; controller.window?.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
            try await refresh()
            for tab in 0..<4 {
                controller.selectTab(tab); try await refresh()
                let minText = try await js("return Math.min(...[...document.querySelectorAll('main span,main p,main label,main button,main h2,main h3,main code,main dt,main dd,main summary')].filter(e=>e.getClientRects().length).map(e=>parseFloat(getComputedStyle(e).fontSize)))") as! Double
                precondition(minText >= 14)
                try await expect("return document.documentElement.scrollWidth <= innerWidth+1", true)
                if tab == 0 {
                    let contrast = try await js("const c=document.createElement('canvas'),ctx=c.getContext('2d'); c.width=1;c.height=1; const px=()=>[...ctx.getImageData(0,0,1,1).data].slice(0,3);const lum=a=>{const v=a.map(n=>{n/=255;return n<=0.04045?n/12.92:((n+0.055)/1.055)**2.4});return .2126*v[0]+.7152*v[1]+.0722*v[2]};return Math.min(...['#pause-button span','.readout .muted','.text-action','.axis-labels'].map(s=>{const e=document.querySelector(s),chain=[];for(let n=e;n;n=n.parentElement)chain.unshift(n);ctx.clearRect(0,0,1,1);ctx.fillStyle=getComputedStyle(document.body).backgroundColor;ctx.fillRect(0,0,1,1);chain.forEach(n=>{ctx.fillStyle=getComputedStyle(n).backgroundColor;ctx.fillRect(0,0,1,1)});const bg=lum(px());ctx.fillStyle=getComputedStyle(e).color;ctx.fillRect(0,0,1,1);const fg=lum(px());return (Math.max(bg,fg)+.05)/(Math.min(bg,fg)+.05)}))") as! Double
                    let colors = try await js("return ['#pause-button span','.readout .muted','.text-action','.axis-labels'].map(s=>{const e=document.querySelector(s);return [s,getComputedStyle(e).color,getComputedStyle(e).backgroundColor]})")
                    precondition(contrast >= 4.5, "Text contrast: \(contrast), \(String(describing: colors))")
                }
                if tab < 2 { try await expect("const main=document.querySelector('main'); return main.scrollHeight <= main.clientHeight+1", true) }
                try await screenshot("dashboard-\(theme)-\(tab)")
            }
        }
        controller.selectTab(0); try await refresh()
        try await expect("return document.getElementById('recent-rate').textContent", "12.7")
        try await expect("return document.querySelectorAll('#rhythm-chart .rhythm-event').length", 11)
        try await expect("return document.querySelectorAll('#rhythm-chart .rhythm-gap').length", 8)
        try await expect("return document.querySelector('header').textContent.includes('AC only')", false)
        controller.selectTab(2); try await refresh()
        try await expect("return document.querySelectorAll('.achievement.earned').length", 2)
        let offset = try await js("return parseFloat(getComputedStyle(document.getElementById('gauge-minutes')).strokeDashoffset)") as! Double
        precondition(abs(offset - 100.0 / 3) < 0.01)
        _ = try await js("document.querySelector('#week-days button').focus(); document.querySelector('#week-days button').click()")
        var revisedStats = state["statistics"] as! [String: Any]
        var revisedWeek = revisedStats["week"] as! [[String: Any]]; revisedWeek[6]["blinkRate"] = 13.1
        revisedStats["week"] = revisedWeek; state["statistics"] = revisedStats; try await refresh()
        try await expect("return document.activeElement === document.querySelector('#week-days button')", true)
        state["calibration"] = 0.42
        for phase in [TrackingPhase.starting, .calibrating, .tracking, .eyesClosed, .noFace, .multipleFaces, .lowQuality, .delayed, .paused, .cameraDenied, .cameraMissing, .cameraError] {
            state["phase"] = phase.rawValue; state["title"] = phase.title; state["detail"] = phase.detail
            try await refresh()
            try await expect("return document.getElementById('tracking-title').textContent", phase.title)
            try await expect("return !document.getElementById('camera-settings').hidden", phase == .cameraDenied)
            try await expect("return !document.getElementById('tracking-rail').hidden", [.starting, .calibrating].contains(phase))
            if phase == .starting { try await expect("return document.getElementById('tracking-rail').hasAttribute('aria-valuenow')", false) }
            if phase == .calibrating { try await expect("return document.getElementById('tracking-rail').getAttribute('aria-valuenow')", "42") }
        }
        state["calibration"] = 1.0
        state["phase"] = "tracking"; state["frameAgeMs"] = 76.0; state["reminderState"] = "waitingForBlink"
        controller.selectTab(0); try await refresh()
        _ = try await js("document.querySelector('[data-inspect]').click()")
        try await refresh()
        try await expect("return document.querySelectorAll('#left-points circle').length", 8)
        try await expect("return document.getElementById('left-aperture').textContent", "0.258")
        state["frameAgeMs"] = 900.0; try await refresh()
        try await expect("return document.querySelectorAll('#left-points circle').length", 0)
        controller.selectTab(0); try await refresh()
        try await expect("return document.getElementById('left-live').getAttribute('d')", "")
        state["frameAgeMs"] = 76.0; state["reducedMotion"] = true; try await refresh()
        try await expect("return getComputedStyle(document.querySelector('.blink-ripple')).animationName", "none")
        try await expect("return getComputedStyle(document.querySelector('#tracking-rail span')).animationName", "none")
        controller.selectTab(1); try await refresh()
        _ = try await js("document.querySelector('[data-routine=reset]').click()")
        try await Task.sleep(for: .milliseconds(100))
        precondition(commands.contains { $0["action"] as? String == "exercise" && $0["routine"] as? String == "reset" })
        state["exercise"] = ["phase": "running", "routine": "reset", "step": "blink", "remaining": 8.0, "progress": 0.1, "due": false]
        try await refresh()
        try await expect("return !document.getElementById('practice-session').hidden", true)
        try await expect("return document.getElementById('blink-scene').hasAttribute('hidden')", false)
        try await expect("return document.querySelector('.exercise-progress').getAttribute('aria-valuenow')", "10")
        try await screenshot("dashboard-practice-blink")
        revisedStats = state["statistics"] as! [String: Any]
        var revisedLifetime = revisedStats["lifetime"] as! [String: Any]; revisedLifetime["blinks"] = 1901
        revisedStats["lifetime"] = revisedLifetime; state["statistics"] = revisedStats; try await refresh()
        try await expect("return document.getElementById('exercise-art').dataset.blink", "first")
        state["phase"] = "cameraDenied"; try await refresh()
        try await expect("return document.getElementById('exercise-feedback').textContent.includes('Camera feedback off')", true)
        _ = try await js("document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}))")
        try await Task.sleep(for: .milliseconds(100))
        precondition(commands.contains { $0["action"] as? String == "exercise" && $0["command"] as? String == "pause" })
        state["exercise"] = ["phase": "paused", "routine": "reset", "step": "look", "remaining": 18.0, "progress": 0.4, "due": false]
        try await refresh()
        try await expect("return document.activeElement.id", "exercise-resume")
        try await expect("return document.getElementById('look-scene').hasAttribute('hidden')", false)
        state["exercise"] = ["phase": "completed", "routine": "reset", "step": "look", "remaining": 0.0, "progress": 1.0, "due": false]
        try await refresh()
        try await expect("return document.activeElement.id", "exercise-end")
        try await screenshot("dashboard-practice-completed")
        controller.selectTab(3); state["exercise"] = ["phase": "idle"]; try await refresh()
        _ = try await js("const s=document.getElementById('setting-sensitivity');s.value='0.8';s.dispatchEvent(new Event('change'));const c=document.getElementById('exercises-enabled');c.checked=true;c.dispatchEvent(new Event('change'))")
        try await Task.sleep(for: .milliseconds(100))
        precondition(commands.contains { $0["key"] as? String == "sensitivity" && $0["value"] as? Double == 0.8 })
        precondition(commands.contains { $0["key"] as? String == "exercisesEnabled" && $0["value"] as? Bool == true })
        controller.window?.setContentSize(NSSize(width: 680, height: 520))
        state["phase"] = "tracking"
        for tab in 0..<4 {
            controller.selectTab(tab); try await refresh()
            try await expect("return document.documentElement.scrollWidth <= innerWidth+1", true)
            if tab < 2 { try await expect("const m=document.querySelector('main');return m.scrollHeight <= m.clientHeight+1", true) }
        }
        controller.selectTab(1); state["exercise"] = ["phase": "running", "routine": "look", "step": "look", "remaining": 12.0, "progress": 0.4]; try await refresh()
        try await expect("const m=document.querySelector('main');return m.scrollHeight <= m.clientHeight+1", true)
        try await screenshot("dashboard-practice-minimum")
        state["exercise"] = ["phase": "idle"]; try await refresh()
        _ = try await js("document.querySelector('[data-tab=\"1\"]').dispatchEvent(new KeyboardEvent('keydown',{key:'End',bubbles:true}))")
        try await expect("return document.querySelector('[aria-selected=true]').dataset.tab", "3")
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
        NSApp.sendAction(settings.action!, to: settings.target, from: settings); precondition(opened == [0,3])
        controller.close()
    }
}

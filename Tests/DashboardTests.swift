import AppKit
import WebKit
import ScreenCaptureKit

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
        var state: [String: Any] = ["phase": "tracking", "title": "Tracking", "detail": "Both eyes visible.", "left": 1.0, "right": 0.93, "calibration": 1.0, "sampleTime": 100.0, "openSeconds": 2.4,
            "latencyMs": 35.2, "p95Ms": 55.0, "fps": 12.5, "dropped": 0, "fading": false, "frameAgeMs": 76.0, "notice": "", "actualTheme": "light",
            "exercise": ["phase": "idle", "step": "blink", "remaining": 10.0, "progress": 0.0, "due": false],
            "geometry": ["left": points, "right": points.map { [$0[0] + 0.35, $0[1]] }, "width": 210.0, "height": 310.0, "box": [0.3,0.2,0.328125,0.645833], "confidence": 0.98, "leftAperture": 0.258, "rightAperture": 0.248],
            "preferences": ["reminderSeconds": 6.0, "fadeSeconds": 1.5, "intensity": 0.65, "sensitivity": 0.5, "remindersEnabled": true, "theme": "system", "cameraID": "", "color": "#006fe6", "minuteGoal": 30.0, "resetGoal": 2.0, "dayGoal": 3.0, "exerciseMinutes": 20.0, "exercisesEnabled": false],
            "statistics": ["today": today, "week": week, "warning": "", "baselineRate": 10.0, "relativePercent": 20.0, "recentRate": 12.7, "recentSeconds": 52.0, "recentBins": bins, "lifetime": ["blinks": 1900, "trackedSeconds": 9200.0, "days": 5, "resets": 6]],
            "cameras": [["id": "test-camera", "name": "Built in camera"]]]
        state["scene"] = ["count":1,"ageMs":300.0]
        state["motion"] = (0..<451).map { i -> [String:Any] in
            let close = i % 69 == 0
            return ["t":70.0+Double(i)/15,"left":close ? 0.16 : 1.0+sin(Double(i)/27)*0.05,"right":close ? 0.18 : 0.93+sin(Double(i)/27)*0.04,"events":i % 69 == 1 ? 4 : 0]
        }
        state["coverage"] = ["observedSeconds":195.0,"span":300,"segments":[
            ["start":0,"end":40,"phase":"paused"],["start":40,"end":60,"phase":"calibrating"],
            ["start":60,"end":180,"phase":"tracking"],["start":180,"end":190,"phase":"multipleFaces"],
            ["start":190,"end":200,"phase":"calibrating"],["start":200,"end":265,"phase":"tracking"],
            ["start":265,"end":290,"phase":"delayed"],["start":290,"end":300,"phase":"tracking"]]]
        var commands: [[String: Any]] = []
        let controller = DashboardWindowController(resources: root.appendingPathComponent("BlinkMore/Resources/UI"), snapshot: { state }, command: { message in
            commands.append(message)
            if message["action"] as? String == "set", let key = message["key"] as? String, var preferences = state["preferences"] as? [String: Any] {
                preferences[key] = message["value"]; state["preferences"] = preferences
            }
        })
        let minimum = controller.window!.minSize
        precondition(minimum.width == 680 && (520...528).contains(minimum.height), "Native toolbar exceeded the compact window budget: \(minimum)")
        controller.selectTab(3); controller.showWindow(nil)
        let view = controller.webView
        for _ in 0..<100 {
            if commands.contains(where: { $0["action"] as? String == "ready" }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(commands.contains { $0["action"] as? String == "ready" })
        func js(_ source: String, arguments: [String: Any] = [:]) async throws -> Any? {
            try await withCheckedThrowingContinuation { continuation in
                view.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page) { result in continuation.resume(with: result.map { Optional($0) }) }
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
            if #available(macOS 14.4, *), name.hasSuffix("-0"), let window = controller.window {
                NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(150))
                // Current-process content captures only this synthetic test app, without screen permission.
                let content = try await SCShareableContent.currentProcess
                guard let ownWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { throw CocoaError(.fileReadUnknown) }
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width * window.backingScaleFactor)
                config.height = Int(window.frame.height * window.backingScaleFactor)
                config.showsCursor = false; config.ignoreShadowsSingleWindow = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: ownWindow), configuration: config)
                let bitmap = NSBitmapImageRep(cgImage: image)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name + "-native.png"))
            }
        }
        try await refresh()
        try await expect("return !document.querySelector('.footer-end') && document.getElementById('footer-notice').hidden", true)
        precondition(controller.window?.toolbar != nil && controller.pageControl.segmentCount == 5)
        try await expect("return document.documentElement.classList.contains('native-controls') && getComputedStyle(document.querySelector('nav')).display === 'none'", true)
        controller.pageControl.selectedSegment = 1
        NSApp.sendAction(controller.pageControl.action!, to: controller.pageControl.target, from: controller.pageControl)
        try await refresh()
        try await expect("return document.body.dataset.page", "4")
        controller.selectTab(3); try await refresh()
        precondition(controller.pageControl.selectedSegment == 4)
        controller.pauseControl.performClick(nil)
        precondition(commands.contains { $0["action"] as? String == "pause" })
        try await expect("const ids=[...document.querySelectorAll('[id]')].map(e=>e.id);return new Set(ids).size===ids.length",true)
        try await expect("await document.fonts.load('500 21px Comfortaa'); return [...document.fonts].some(f=>f.family==='Comfortaa' && f.status==='loaded')", true)
        try await expect("return document.querySelector('.identity h1').textContent", "eyesight")
        try await expect("const image=document.querySelector('.logo'); await image.decode(); return image.complete && image.naturalWidth > 0", true)
        try await expect("return [...document.querySelectorAll('svg[viewBox]')].every(svg=>svg.viewBox.baseVal.width>0&&svg.viewBox.baseVal.height>0)", true)
        let brandURL = root.appendingPathComponent("BlinkMore/Resources/UI/eyesight.svg")
        let brandViewBox = try XMLDocument(contentsOf: brandURL, options: []).rootElement()?.attribute(forName: "viewBox")?.stringValue?.split(whereSeparator: \.isWhitespace).compactMap(Double.init) ?? []
        precondition(brandViewBox.count == 4 && brandViewBox[2] > 0 && brandViewBox[3] > 0 && abs(brandViewBox[2] / brandViewBox[3] - 1.6) < 0.001, "Brand SVG viewBox aspect ratio changed")
        let logoFit = try await js("const image=document.querySelector('.logo'),box=image.getBoundingClientRect(),style=getComputedStyle(image),ratio=aspect,drawnWidth=Math.min(box.width,box.height*ratio),drawnHeight=drawnWidth/ratio;return image.complete&&style.objectFit==='contain'&&drawnWidth<=box.width&&drawnHeight<=box.height&&Math.abs(drawnWidth/drawnHeight-ratio)<0.001", arguments: ["aspect": brandViewBox[2] / brandViewBox[3]]) as? Bool
        precondition(logoFit == true, "Brand SVG does not fit its viewBox proportionally")
        precondition(NSImage(contentsOf: brandURL) != nil)
        let nativeMark = MenuBarController.mark(size: 64, color: .white, source: brandURL)
        precondition(nativeMark.tiffRepresentation != nil)
        try await expect("return document.querySelector('[aria-selected=true]').dataset.tab", "3")
        for theme in ["light", "dark"] {
            state["actualTheme"] = theme; controller.window?.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
            try await refresh()
            try await expect("return document.documentElement.classList.contains('dark')", theme == "dark")
            for tab in 0..<5 {
                controller.selectTab(tab); try await refresh()
                let minText = try await js("return Math.min(...[...document.querySelectorAll('main span,main p,main label,main button,main h2,main h3,main code,main dt,main dd,main summary')].filter(e=>e.getClientRects().length).map(e=>parseFloat(getComputedStyle(e).fontSize)))") as! Double
                precondition(minText >= 14)
                try await expect("return document.documentElement.scrollWidth <= innerWidth+1", true)
                if tab == 0 {
                    let contrast = try await js("const c=document.createElement('canvas'),ctx=c.getContext('2d'); c.width=1;c.height=1; const px=()=>[...ctx.getImageData(0,0,1,1).data].slice(0,3);const lum=a=>{const v=a.map(n=>{n/=255;return n<=0.04045?n/12.92:((n+0.055)/1.055)**2.4});return .2126*v[0]+.7152*v[1]+.0722*v[2]};return Math.min(...['#tracking-title','.readout .muted','.text-action','.axis-labels'].map(s=>{const e=document.querySelector(s),chain=[];for(let n=e;n;n=n.parentElement)chain.unshift(n);ctx.clearRect(0,0,1,1);ctx.fillStyle=getComputedStyle(document.body).backgroundColor;ctx.fillRect(0,0,1,1);chain.forEach(n=>{ctx.fillStyle=getComputedStyle(n).backgroundColor;ctx.fillRect(0,0,1,1)});const bg=lum(px());ctx.fillStyle=getComputedStyle(e).color;ctx.fillRect(0,0,1,1);const fg=lum(px());return (Math.max(bg,fg)+.05)/(Math.min(bg,fg)+.05)}))") as! Double
                    let colors = try await js("return ['#tracking-title','.readout .muted','.text-action','.axis-labels'].map(s=>{const e=document.querySelector(s);return [s,getComputedStyle(e).color,getComputedStyle(e).backgroundColor]})")
                    precondition(contrast >= 4.5, "Text contrast: \(contrast), \(String(describing: colors))")
                }
                if tab < 2 {
                    try await expect("const main=document.querySelector('main'); return main.scrollHeight <= main.clientHeight+1", true) }
                if tab == 4 {
                    try await expect("return window.scrollY", 0)

                }
                if tab == 4 {
                    try await expect("const graph=document.getElementById('motion-chart').getBoundingClientRect(),main=document.querySelector('main').getBoundingClientRect();return graph.bottom<=main.bottom+1",true)
                    let timings = try await js("const times=[];for(let i=0;i<30;i++){const start=performance.now();window.blinkmore.update(state);times.push(performance.now()-start)}times.sort((a,b)=>a-b);return {samples:30,p95Ms:times[28],meanMs:times.reduce((a,b)=>a+b,0)/30,theme:state.actualTheme,fixture:'451 synthetic native samples; excludes capture and Vision'}",arguments:["state":state])
                    let data = try JSONSerialization.data(withJSONObject:timings!,options:[.prettyPrinted,.sortedKeys])
                    try data.write(to:output.appendingPathComponent("studio-render-\(theme).json"))
                }
                try await screenshot("dashboard-\(theme)-\(tab)")
                if tab == 3 {
                    _ = try await js("document.querySelector('.privacy-panel').scrollIntoView({block:'center'})")
                    try await expect("const image=document.querySelector('.privacy-mark');await image.decode();const rect=image.getBoundingClientRect(),style=getComputedStyle(image),ratio=image.naturalWidth/image.naturalHeight,drawnWidth=Math.min(rect.width,rect.height*ratio),drawnHeight=drawnWidth/ratio;return image.complete&&image.naturalWidth>0&&image.naturalHeight>0&&Number.isFinite(ratio)&&style.objectFit==='contain'&&rect.width>=48&&rect.width<=56&&rect.height>=48&&rect.height<=56&&drawnWidth>0&&drawnHeight>0&&drawnWidth<=rect.width&&drawnHeight<=rect.height",true)
                    try await screenshot("dashboard-privacy-\(theme)")
                }
            }
        }
        controller.selectTab(0); try await refresh()
        try await expect("return document.getElementById('recent-rate').textContent", "12.7")
        try await expect("return document.getElementById('rhythm-chart').getAttribute('preserveAspectRatio')", "none")
        try await expect("return document.querySelectorAll('#rhythm-chart .rhythm-event').length", 11)
        try await expect("return document.querySelectorAll('#rhythm-chart .rhythm-gap').length", 8)
        try await expect("return document.querySelector('header').textContent.includes('AC only')", false)
        controller.selectTab(2); try await refresh()
        try await expect("return document.querySelectorAll('.achievement.earned').length", 3)
        try await expect("return document.getElementById('coverage-total').textContent","195s valid exposure")
        try await expect("return document.querySelectorAll('#coverage-segments rect').length",8)
        try await expect("const chart=document.getElementById('coverage-chart'),group=document.getElementById('coverage-segments'),clip=document.querySelector('#coverage-clip rect'),segments=[...group.querySelectorAll('rect')];return group.getAttribute('clip-path')==='url(#coverage-clip)'&&clip.getAttribute('x')==='0'&&clip.getAttribute('width')==='640'&&segments.map(r=>r.getAttribute('class')).join(',')==='coverage-interrupted,coverage-calibrating,coverage-observed,coverage-interrupted,coverage-calibrating,coverage-observed,coverage-unknown,coverage-observed'",true)
        try await expect("const clip=document.querySelector('#coverage-clip rect'),segments=[...document.querySelectorAll('#coverage-segments rect')],x=segments.map(r=>Number(r.getAttribute('x'))),w=segments.map(r=>Number(r.getAttribute('width')));return segments.every((r,i)=>{const y=Number(r.getAttribute('y')),h=Number(r.getAttribute('height'));return x[i]>=0&&x[i]+w[i]<=640&&y>=Number(clip.getAttribute('y'))&&y+h<=Number(clip.getAttribute('y'))+Number(clip.getAttribute('height'))&&(i===0||Math.abs(x[i]-(x[i-1]+w[i-1]))<0.01)})&&Math.abs(x[0])<0.01&&Math.abs(x[x.length-1]+w[w.length-1]-640)<0.01",true)
        try await expect("const ids=[...document.querySelectorAll('[id]')].map(e=>e.id),refs=[...document.querySelectorAll('svg [clip-path]')].map(e=>e.getAttribute('clip-path').match(/^url\\(#(.+)\\)$/)?.[1]);return ids.length===new Set(ids).size&&refs.length===1&&refs.every(id=>document.getElementById(id)?.ownerSVGElement===document.getElementById('coverage-chart'))",true)
        _ = try await js("document.getElementById('coverage-section').scrollIntoView({block:'start'})")
        try await screenshot("dashboard-coverage")
        let coverageFixture = state["coverage"] as! [String: Any]
        state["coverage"] = ["observedSeconds":0.0,"span":300,"segments":[]]; try await refresh()
        try await expect("return document.querySelectorAll('#coverage-segments rect').length",0)
        try await expect("return !document.getElementById('coverage-empty').hidden&&document.getElementById('coverage-summary').textContent==='Waiting for observations'",true)
        state["coverage"] = coverageFixture; try await refresh()
        let offset = try await js("return parseFloat(getComputedStyle(document.getElementById('gauge-minutes')).strokeDashoffset)") as! Double
        precondition(abs(offset - 33.3) < 0.01)
        try await expect("return document.getElementById('gauge-resets').closest('.gauge-card').dataset.complete", "true")
        try await expect("return document.getElementById('reset-goal-note').textContent", "Goal reached")
        try await expect("const references=[...document.querySelectorAll('.gauge-value,.intention-value,.gauge-rim')];return references.every(e=>{const s=getComputedStyle(e).stroke,id=s.match(/#[a-z-]+/);return id&&document.getElementById(id[0].slice(1))!==null})", true)
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
            precondition(controller.pauseControl.title == (phase == .paused ? "Resume" : "Pause"))
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
        try await expect("return document.body.dataset.page", "4")
        precondition(controller.showsLive)
        try await expect("return document.getElementById('live-difference').textContent", "7%")
        _ = try await js("document.getElementById('start-check').click()")
        try await Task.sleep(for: .milliseconds(100))
        precondition(commands.contains { $0["action"] as? String == "startCheck" })
        state["eyeCheck"] = ["phase":"running", "remaining": 20.0, "progress": 1.0/3, "observedSeconds":8.0, "blinks":2, "difference":4.5]
        state["sampleTime"] = 100.2; try await refresh()
        try await expect("return !document.getElementById('check-session').hidden && !document.getElementById('cancel-check').hidden", true)
        try await expect("return document.activeElement.id", "cancel-check")
        try await expect("return document.getElementById('motion-left').getAttribute('d').includes('L')", true)
        _ = try await js("document.getElementById('cancel-check').click()")
        try await Task.sleep(for: .milliseconds(100))
        precondition(commands.contains { $0["action"] as? String == "cancelCheck" })
        try await screenshot("dashboard-live-check")
        state["eyeCheck"] = ["phase":"completed", "remaining":0.0, "progress":1.0, "observedSeconds":24.0, "blinks":7, "difference":4.1]
        try await refresh()
        try await expect("return document.getElementById('check-status').textContent", "Observation complete")
        try await expect("return document.activeElement.id", "review-check")
        state["eyeCheck"] = ["phase":"idle"]
        state["title"] = "Tracking"; state["detail"] = "Both eyes visible."
        try await refresh()
        _ = try await js("document.querySelector('[data-span=\"15\"]').click()")
        try await expect("return document.getElementById('motion-start').textContent", "15s ago")
        _ = try await js("document.querySelector('[data-studio=\"difference\"]').click()")
        try await expect("return document.getElementById('motion-title').textContent", "Left minus right opening")
        try await expect("return document.getElementById('motion-right').getAttribute('d')", "")
        try await screenshot("dashboard-live-difference")
        _ = try await js("document.querySelector('[data-studio=\"geometry\"]').click()")
        try await expect("return document.getElementById('geometry-workspace').hidden", false)
        try await expect("return document.getElementById('left-span').textContent.includes('px')", true)
        try await expect("return document.getElementById('left-area').textContent.includes('px²') && document.getElementById('right-area').textContent.includes('px²')",true)
        try await expect("return document.querySelectorAll('#motion-left-fill stop').length",2)
        try await expect("return document.getElementById('left-tilt').textContent", "0°")
        _ = try await js("document.getElementById('overlay-points').click()")
        try await expect("return getComputedStyle(document.getElementById('left-points')).display", "none")
        try await expect("return document.querySelector('button[data-studio=\"geometry\"]').getAttribute('aria-pressed')","true")
        _ = try await js("document.getElementById('overlay-points').click();document.querySelector('.anatomy').open=true")
        _ = try await js("document.getElementById('geometry-workspace').scrollIntoView({block:'start'})")
        try await screenshot("dashboard-live-geometry")
        state["attention"] = "More than one face. Observation paused."
        state["scene"] = ["count":2,"ageMs":100.0]
        try await refresh()
        try await expect("return document.getElementById('scene-summary').textContent", "2 measurable faces in view, observation paused")
        try await expect("return document.getElementById('attention-banner').hidden", false)
        state["attention"] = ""; state["scene"] = ["count":1,"ageMs":100.0]
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
        try await expect("return document.getElementById('exercise-feedback').textContent.includes('Camera feedback is unavailable')", true)
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
        state["phase"] = "tracking"; state["title"] = "Tracking"; state["frameAgeMs"] = 76.0; state["calibration"] = 1.0
        state["exercise"] = ["phase":"idle"]
        controller.showSetup(); try await refresh()
        try await expect("return document.getElementById('setup-workspace').hidden",false)
        try await expect("return document.querySelectorAll('.setup-check[data-ready=true]').length",5)
        try await expect("return document.getElementById('setup-summary').textContent","Ready")
        for theme in ["light","dark"] {
            state["actualTheme"] = theme; try await refresh()
            try await expect("const action=document.getElementById('setup-calibrate').getBoundingClientRect(),main=document.querySelector('main').getBoundingClientRect();return action.bottom<=main.bottom+1",true)
            try await screenshot("dashboard-setup-\(theme)")
        }
        try await screenshot("dashboard-setup")
        state["phase"] = "cameraDenied"; state["frameAgeMs"] = 800.0; try await refresh()
        try await expect("return document.getElementById('setup-allow').hidden",false)
        try await expect("return document.getElementById('setup-face').hasAttribute('hidden')",true)
        try await expect("return document.getElementById('setup-calibrate').disabled",true)
        state["phase"] = "noFace"; state["frameAgeMs"] = 76.0; state["scene"] = ["count":0,"ageMs":300.0]
        try await refresh()
        try await expect("return document.getElementById('setup-summary').textContent==='Move into view'&&document.getElementById('setup-face').hasAttribute('hidden')&&document.getElementById('setup-calibrate').disabled",true)
        state["phase"] = "cameraMissing"; state["scene"] = ["count":1,"ageMs":300.0]
        try await refresh()
        try await expect("return !document.getElementById('setup-retry').hidden&&document.getElementById('setup-allow').hidden&&document.getElementById('setup-calibrate').disabled",true)
        state["phase"] = "tracking"; state["frameAgeMs"] = 76.0
        controller.selectTab(1)
        state["exercise"] = ["phase":"running","routine":"blink","step":"blink","remaining":5.0,"progress":0.5]
        var clip: [[String:Any]] = []
        for i in 0..<13 {
            let left: Double = i == 6 ? 0.1 : 1.0
            let right: Double = i == 6 ? 0.12 : 0.95
            let events: Int = i == 8 ? 4 : 0
            clip.append(["t":Double(i)/15.0,"left":left,"right":right,"events":events])
        }
        state["mirror"] = ["phase":"running","observedSeconds":4.6,"blinks":1,"clip":clip]
        try await refresh()
        try await expect("return document.getElementById('mirror-panel').hidden",false)
        try await expect("return document.getElementById('mirror-replay').disabled",true)
        try await expect("const eyes=document.getElementById('mirror-eyes'),trace=document.getElementById('mirror-trace');return eyes.getAttribute('viewBox')==='0 0 440 100'&&eyes.getAttribute('preserveAspectRatio')!=='none'&&trace.getAttribute('viewBox')==='0 0 320 72'&&trace.getAttribute('preserveAspectRatio')==='none'",true)
        state["exercise"] = ["phase":"completed","routine":"blink","step":"blink","remaining":0.0,"progress":1.0]
        state["mirror"] = ["phase":"completed","observedSeconds":9.4,"blinks":3,"clip":clip]
        state["reducedMotion"] = false; try await refresh()
        try await expect("return document.getElementById('mirror-replay').disabled",false)
        try await expect("return document.getElementById('mirror-totals').textContent","3 blinks, 9.4s observed")
        try await expect("return ['#mirror-trace-left','#mirror-trace-right'].every(selector=>{const path=document.querySelector(selector),box=path.getBBox(),view=path.ownerSVGElement.viewBox.baseVal;return box.width>0&&box.x>=0&&box.y>=0&&box.x+box.width<=view.width&&box.y+box.height<=view.height})",true)
        _ = try await js("document.getElementById('mirror-replay').click()")
        try await Task.sleep(for:.milliseconds(100))
        try await expect("return document.getElementById('mirror-source').textContent","Recorded blink")
        try await screenshot("dashboard-mirror")
        for theme in ["light","dark"] {
            state["actualTheme"] = theme; try await refresh()
            try await expect("return document.documentElement.classList.contains('dark')", theme == "dark")
            try await expect("const m=document.querySelector('main');return m.scrollHeight<=m.clientHeight+1",true)
            try await screenshot("dashboard-mirror-\(theme)")
        }
        state["mirror"] = ["phase":"completed","observedSeconds":0.0,"blinks":0,"clip":[]]
        try await refresh()
        try await expect("return document.getElementById('mirror-replay').disabled",true)
        state["mirror"] = ["phase":"completed","observedSeconds":9.4,"blinks":3,"clip":clip]
        state["reducedMotion"] = true; try await refresh()
        _ = try await js("document.getElementById('mirror-replay').click()")
        try await expect("return document.activeElement.id","mirror-trace")
        controller.selectTab(3); state["exercise"] = ["phase": "idle"]; try await refresh()
        _ = try await js("const s=document.getElementById('setting-sensitivity');s.value='0.8';s.dispatchEvent(new Event('change'));const c=document.getElementById('exercises-enabled');c.checked=true;c.dispatchEvent(new Event('change'))")
        try await Task.sleep(for: .milliseconds(100))
        precondition(commands.contains { $0["key"] as? String == "sensitivity" && $0["value"] as? Double == 0.8 })
        precondition(commands.contains { $0["key"] as? String == "exercisesEnabled" && $0["value"] as? Bool == true })
        controller.window?.setContentSize(NSSize(width: 680, height: 520))
        try await Task.sleep(for: .milliseconds(100))
        let viewportFits = try await js("return Math.round(innerWidth)===680&&Math.round(innerHeight)===height", arguments: ["height": Int(controller.webView.bounds.height.rounded())]) as? Bool
        precondition(viewportFits == true, "Web content must fit below the native toolbar")
        state["phase"] = "tracking"
        for tab in 0..<5 {
            controller.selectTab(tab); try await refresh()
            try await expect("return document.documentElement.scrollWidth <= innerWidth+1", true)
            if tab < 2 { try await expect("const m=document.querySelector('main');return m.scrollHeight <= m.clientHeight+1", true) }
        }
        controller.showSetup(); try await refresh()
        try await expect("const b=document.getElementById('setup-calibrate').getBoundingClientRect(),m=document.querySelector('main').getBoundingClientRect();return b.bottom<=m.bottom+1",true)
        controller.selectTab(1); state["exercise"] = ["phase":"completed","routine":"blink","step":"blink","remaining":0.0,"progress":1.0]; try await refresh()
        try await expect("return !document.getElementById('mirror-panel').hidden",true)
        try await expect("const panel=document.getElementById('mirror-panel').getBoundingClientRect(),items=['#mirror-eyes','#mirror-trace','.mirror-replay','#mirror-description'].map(s=>document.querySelector(s).getBoundingClientRect());return items.every(b=>b.left>=panel.left-1&&b.right<=panel.right+1)&&document.querySelector('main').scrollHeight<=document.querySelector('main').clientHeight+1",true)
        try await expect("const m=document.querySelector('main');return m.scrollHeight<=m.clientHeight+1",true)
        controller.selectTab(1); state["exercise"] = ["phase": "running", "routine": "look", "step": "look", "remaining": 12.0, "progress": 0.4]; try await refresh()
        try await expect("const m=document.querySelector('main');return m.scrollHeight <= m.clientHeight+1", true)
        try await screenshot("dashboard-practice-minimum")
        state["exercise"] = ["phase": "idle"]; try await refresh()
        _ = try await js("document.querySelector('[data-tab=\"1\"]').dispatchEvent(new KeyboardEvent('keydown',{key:'End',bubbles:true}))")
        try await expect("return document.querySelector('[aria-selected=true]').dataset.tab", "3")
        controller.webView.pageZoom = 2
        for theme in ["light", "dark"] {
            state["actualTheme"] = theme
            for tab in 0..<5 {
                controller.selectTab(tab); try await refresh()
                try await expect("return document.documentElement.scrollWidth <= innerWidth+1", true)
                try await expect("return [...document.querySelectorAll('main button,main select,main input,main summary')].filter(e=>e.getClientRects().length).every(e=>{const r=e.getBoundingClientRect();return r.width>=24&&r.height>=24})", true)
            }
        }
        try await screenshot("dashboard-enlarged")
        controller.webView.pageZoom = 1
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

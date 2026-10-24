import AppKit
import AVFoundation
import IOKit.ps
import UniformTypeIdentifiers
import CoreGraphics

final class ApplicationController: NSObject, NSApplicationDelegate {
    let preferences = AppPreferences()
    let statistics = DailyStatistics()
    private let fade = OverlayFade()
    private var menu: MenuBarController!
    private var tracker: EyeTrackingService?
    private var sessionID = UUID()
    private var lastCameraStart: Double = 0
    private var requestingPermission = false
    private var stoppingCamera = false
    private var frame = TrackingFrame()
    private var powerTimer: Timer?
    private var fadeTimer: Timer?
    private var saveTimer: Timer?
    private var dashboard: DashboardWindowController?
    private var previewUntil: Double = 0
    private var reminderPolicy = ReminderPolicy()
    private var exercise = ExercisePolicy()
    private var checking = false
    private var sleeping = false
    private var locked = false
    private var inactiveSession = false
    private var userIdle = false
    private var systemSuspended: Bool { sleeping || locked || inactiveSession }
    private var latency: [Double] = []
    private var cameras: [[String: String]] = []
    private var notice = ""
    private var noticeUntil = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = MenuBarController()
        menu.onOpen = { [weak self] tab in self?.openDashboard(tab: tab) }
        menu.onCommand = { [weak self] message in self?.command(message) }
        menu.snapshot = { [weak self] in self?.snapshot() ?? [:] }
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        let close = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(close); NSApp.mainMenu = mainMenu
        preferences.onChange = { [weak self] in
            guard let self = self else { return }
            self.applyTheme(); self.tracker?.setSensitivity(self.preferences.sensitivity)
            self.reconcile(); self.dashboard?.refresh()
        }
        updateCameras()
        NotificationCenter.default.addObserver(self, selector: #selector(updateCameras), name: AVCaptureDevice.wasConnectedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateCameras), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            workspace.addObserver(self, selector: #selector(sleepChanged(_:)), name: name, object: nil)
        }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(sessionChanged(_:)), name: name, object: nil)
        }
        // shortcut: distributed lock notifications need live verification on each macOS release.
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(lockChanged(_:)), name: Notification.Name(name), object: nil)
        }
        applyTheme(); reconcile()
        powerTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile(); self?.writeDiagnostics() }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateFade() }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.statistics.flush() }
        // Power checks and fade safety must continue while a native menu is tracking.
        for timer in [powerTimer, fadeTimer, saveTimer].compactMap({ $0 }) { RunLoop.main.add(timer, forMode: .common) }
        if !UserDefaults.standard.bool(forKey: "dashboardIntroducedV2") {
            UserDefaults.standard.set(true, forKey: "dashboardIntroducedV2")
            openDashboard()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard(); return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        powerTimer?.invalidate(); fadeTimer?.invalidate(); saveTimer?.invalidate()
        fade.setVisible(false, color: preferences.fadeColor, intensity: preferences.intensity, duration: 0)
        statistics.flush(synchronous: true)
        guard let tracker = tracker else { return .terminateNow }
        self.tracker = nil
        tracker.stop { [statistics] in
            statistics.flush(synchronous: true)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func updateCameras() {
        if !Thread.isMainThread { DispatchQueue.main.async { [weak self] in self?.updateCameras() }; return }
        cameras = EyeTrackingService.cameras().map { ["id": $0.uniqueID, "name": $0.localizedName] }
    }

    @objc private func sleepChanged(_ notification: Notification) {
        sleeping = notification.name == NSWorkspace.willSleepNotification; lifecycleChanged()
    }
    @objc private func sessionChanged(_ notification: Notification) {
        inactiveSession = notification.name == NSWorkspace.sessionDidResignActiveNotification; lifecycleChanged()
    }
    @objc private func lockChanged(_ notification: Notification) {
        locked = notification.name.rawValue == "com.apple.screenIsLocked"; lifecycleChanged()
    }
    private func lifecycleChanged() {
        exercise.end(now: EyeTrackingService.clock()); reminderPolicy.reset(); previewUntil = 0
        reconcile(); updateFade()
    }

    private var effectivePhase: TrackingPhase {
        if [.tracking, .eyesClosed, .calibrating].contains(frame.phase), EyeTrackingService.clock() - frame.timestamp > 0.5 { return .delayed }
        return frame.phase
    }

    private func onACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return false }
        return source as String == kIOPSACPowerValue
    }

    private func reconcile() {
        guard onACPower() else { NSApplication.shared.terminate(nil); return }
        userIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) >= 60
        if systemSuspended || preferences.pauseUntil != nil {
            stopCamera(); frame.phase = .paused; menu.update(.paused); return
        }
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization == .denied || authorization == .restricted {
            stopCamera(); frame.phase = .cameraDenied; menu.update(.cameraDenied); return
        }
        if authorization == .notDetermined {
            guard !requestingPermission else { return }
            requestingPermission = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { self?.requestingPermission = false; self?.reconcile() }
            }
            return
        }
        if tracker != nil {
            let now = EyeTrackingService.clock()
            let failed = [.cameraMissing, .cameraError].contains(frame.phase) && now - lastCameraStart > 5
            let stalled = frame.timestamp > 0 ? now - frame.timestamp > 5 : now - lastCameraStart > 10
            if failed || stalled { stopCamera() }
            return
        }
        guard !stoppingCamera else { return }
        lastCameraStart = EyeTrackingService.clock()
        let token = UUID(); sessionID = token; frame = TrackingFrame()
        menu.update(.starting)
        let service = EyeTrackingService(cameraID: preferences.cameraID, sensitivity: preferences.sensitivity, statistics: statistics) { [weak self] value in
            guard let self = self, self.sessionID == token else { return }
            self.frame = value
            if value.latencyMs.isFinite && value.latencyMs > 0 {
                self.latency.append(value.latencyMs)
                if self.latency.count > 120 { self.latency.removeFirst(self.latency.count - 120) }
            }
            self.menu.update(value.phase)
            if value.events & 4 != 0 { self.menu.blink() }
            self.updateFade()
        }
        tracker = service; service.start()
    }

    private func stopCamera() {
        guard let service = tracker else { return }
        statistics.cancelCheck(now: EyeTrackingService.clock())
        sessionID = UUID(); tracker = nil; stoppingCamera = true
        service.stop { [weak self] in
            self?.stoppingCamera = false; self?.statistics.flush()
        }
        previewUntil = 0; reminderPolicy.reset()
        fade.setVisible(false, color: preferences.fadeColor, intensity: preferences.intensity, duration: 0)
    }

    private func updateFade() {
        let now = EyeTrackingService.clock()
        menu?.update(effectivePhase)
        let wasChecking = checking
        checking = statistics.checkRunning(now: now)
        if wasChecking && !checking { reminderPolicy.waitForBlink() }
        let wasActive = exercise.active
        if exercise.tick(now: now, eligible: !systemSuspended && !userIdle && preferences.pauseUntil == nil,
                         enabled: preferences.exercisesEnabled, minutes: preferences.exerciseMinutes) {
            statistics.completedReset(seconds: exercise.routine.duration); statistics.flush()
        }
        if wasActive && !exercise.active { reminderPolicy.waitForBlink(); previewUntil = 0 }
        let preview = now < previewUntil
        let decision = reminderPolicy.update(now: now, frame: frame,
            enabled: !systemSuspended && !exercise.active && !checking && preferences.pauseUntil == nil && preferences.remindersEnabled, threshold: preferences.reminderSeconds)
        let visible = !systemSuspended && !exercise.active && !checking && preferences.pauseUntil == nil && (preview || decision.visible)
        if decision.triggered && !preview { statistics.reminder() }
        fade.setVisible(visible, color: preferences.fadeColor, intensity: preferences.intensity,
                        duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : preview ? min(0.25, preferences.fadeSeconds) : preferences.fadeSeconds)
    }

    private func writeDiagnostics() {
        guard CommandLine.arguments.contains("--diagnose") else { return }
        let value: [String: Any] = ["phase": effectivePhase.rawValue, "calibration": frame.calibration,
            "delayMs": frame.latencyMs, "fps": frame.fps, "dropped": frame.dropped,
            "frameAge": max(0, EyeTrackingService.clock() - frame.timestamp), "quality": frame.qualityNote,
            "reminderState": reminderPolicy.mode.rawValue, "fading": fade.isFaded,
            "exercise": exercise.snapshot(now: EyeTrackingService.clock())]
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlinkMore/diagnostic-status.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url, options: .atomic)
        } catch { NSLog("Diagnostic status could not be saved") }
    }

    private func applyTheme() {
        switch preferences.theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    @objc private func openSettings() { openDashboard(tab: 3) }

    func openDashboard(tab: Int? = nil) {
        if dashboard == nil {
            dashboard = DashboardWindowController(snapshot: { [weak self] in self?.snapshot() ?? [:] }, command: { [weak self] in self?.command($0) })
            dashboard?.onClose = { [weak self] in
                guard let self = self else { return }
                if self.exercise.phase != .idle { self.exercise.end(now: EyeTrackingService.clock()); self.reminderPolicy.waitForBlink() }
                self.statistics.cancelCheck(now: EyeTrackingService.clock()); self.reminderPolicy.waitForBlink()
                self.dashboard = nil
            }
        }
        if let tab = tab { dashboard?.selectTab(tab) }
        dashboard?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func togglePause() {
        preferences.pauseUntil = preferences.pauseUntil == nil ? Date().addingTimeInterval(300) : nil
    }

    func snapshot() -> [String: Any] {
        let ordered = latency.sorted()
        let actualTheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let phase = effectivePhase
        var result: [String: Any] = ["phase": phase.rawValue, "title": phase.title, "detail": phase.detail]
        result["exercise"] = exercise.snapshot(now: EyeTrackingService.clock())
        result["eyeCheck"] = statistics.checkSnapshot(now: EyeTrackingService.clock())
        result["sampleTime"] = frame.timestamp
        result["closedMask"] = frame.closedMask
        result["left"] = frame.left; result["right"] = frame.right
        result["geometry"] = ["left": frame.leftContour.map { [$0.x, $0.y] },
            "right": frame.rightContour.map { [$0.x, $0.y] },
            "leftAperture": frame.leftAperture, "rightAperture": frame.rightAperture,
            "width": frame.faceWidth, "height": frame.faceHeight, "confidence": frame.faceConfidence]
        result["frameAgeMs"] = frame.timestamp > 0 ? max(0, EyeTrackingService.clock() - frame.timestamp) * 1000 : NSNull()
        result["reducedMotion"] = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        result["calibration"] = frame.calibration; result["openSeconds"] = frame.openSeconds
        result["latencyMs"] = frame.latencyMs
        result["p95Ms"] = ordered.isEmpty ? 0 : ordered[min(ordered.count - 1, ordered.count * 95 / 100)]
        result["reminderState"] = reminderPolicy.mode.rawValue
        result["fps"] = frame.fps; result["dropped"] = frame.dropped; result["fading"] = fade.isFaded
        result["actualTheme"] = actualTheme; result["preferences"] = preferences.snapshot()
        result["statistics"] = statistics.snapshot(); result["cameras"] = cameras
        result["notice"] = Date() < noticeUntil ? notice : ""
        return result
    }

    func command(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        switch action {
        case "ready": dashboard?.refresh()
        case "startReset": startExercise(.reset)
        case "startCheck":
            guard tracker != nil, [.tracking, .eyesClosed].contains(effectivePhase), frame.calibrated,
                  EyeTrackingService.clock() - frame.timestamp < 0.35 else {
                notify("Face the camera and finish calibration before starting a check."); return
            }
            let now = EyeTrackingService.clock()
            exercise.end(now: now); statistics.startCheck(now: now)
            previewUntil = 0; reminderPolicy.waitForBlink(); updateFade(); openDashboard(tab: 4)
        case "cancelCheck":
            statistics.cancelCheck(now: EyeTrackingService.clock()); reminderPolicy.waitForBlink(); updateFade()
        case "exercise":
            guard let value = message["command"] as? String else { return }
            let now = EyeTrackingService.clock()
            switch value {
            case "start":
                guard let raw = message["routine"] as? String, let routine = ExercisePolicy.Routine(rawValue: raw) else { return }
                startExercise(routine)
            case "pause": exercise.pause(now: now)
            case "resume": exercise.resume(now: now)
            case "end", "skip": exercise.end(now: now); reminderPolicy.waitForBlink()
            case "later": exercise.later(now: now)
            default: return
            }
            updateFade()
        case "pause": togglePause()
        case "calibrate":
            guard let tracker = tracker else { return }
            statistics.cancelCheck(now: EyeTrackingService.clock()); tracker.recalibrate()
            frame = TrackingFrame(phase: .calibrating); reminderPolicy.reset(); previewUntil = 0; updateFade()
            notify("Calibration restarted. Look toward the camera and blink normally.")
        case "preview": statistics.cancelCheck(now: EyeTrackingService.clock()); exercise.end(now: EyeTrackingService.clock()); reminderPolicy.waitForBlink(); previewUntil = EyeTrackingService.clock() + 2; updateFade()
        case "retry": stopCamera(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reconcile() }
        case "cameraSettings":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
        case "set": setPreference(message)
        case "export": exportStatistics()
        case "reset": resetStatistics()
        default: notify("That control is not available.")
        }
        dashboard?.refresh()
    }

    private func startExercise(_ routine: ExercisePolicy.Routine) {
        guard preferences.pauseUntil == nil, !systemSuspended else { return }
        statistics.cancelCheck(now: EyeTrackingService.clock())
        userIdle = false; exercise.start(routine, now: EyeTrackingService.clock())
        previewUntil = 0; reminderPolicy.reset(); updateFade(); openDashboard(tab: 1)
    }

    private func setPreference(_ message: [String: Any]) {
        guard let key = message["key"] as? String else { return }
        let value = message["value"]
        switch key {
        case "theme": if let v = value as? String { preferences.theme = v }
        case "color": if let v = value as? String, !preferences.setColor(hex: v) { notify("Choose a valid fade color.") }
        case "remindersEnabled", "exercisesEnabled":
            if let v = value as? NSNumber, CFGetTypeID(v) == CFBooleanGetTypeID() {
                if key == "remindersEnabled" { preferences.remindersEnabled = v.boolValue }
                else { preferences.exercisesEnabled = v.boolValue }
            }
        case "cameraID":
            if let v = value as? String, v.isEmpty || cameras.contains(where: { $0["id"] == v }) {
                stopCamera(); preferences.cameraID = v.isEmpty ? nil : v
            }
        case "reminderSeconds", "fadeSeconds", "intensity", "sensitivity", "exerciseMinutes", "minuteGoal", "dayGoal", "resetGoal":
            guard let v = value as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(), v.doubleValue.isFinite else { return }
            switch key {
            case "reminderSeconds": preferences.reminderSeconds = v.doubleValue
            case "fadeSeconds": preferences.fadeSeconds = v.doubleValue
            case "intensity": preferences.intensity = v.doubleValue
            case "exerciseMinutes": preferences.exerciseMinutes = v.doubleValue
            case "minuteGoal": preferences.minuteGoal = v.doubleValue
            case "dayGoal": preferences.dayGoal = v.doubleValue
            case "resetGoal": preferences.resetGoal = v.doubleValue
            default: statistics.cancelCheck(now: EyeTrackingService.clock()); preferences.sensitivity = v.doubleValue
            }
        default: notify("That preference is not available.")
        }
    }

    private func notify(_ text: String) { notice = text; noticeUntil = Date().addingTimeInterval(5) }

    private func exportStatistics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Eyesight-statistics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try statistics.exportData().write(to: url, options: .atomic); notify("Statistics exported.") }
        catch { notify("Statistics could not be exported. Choose another location.") }
    }

    private func resetStatistics() {
        let alert = NSAlert()
        alert.messageText = "Delete all daily statistics?"
        alert.informativeText = "Your tracking preferences and calibration are kept. Recovery copies are not deleted. This cannot be undone."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete statistics")
        if alert.runModal() == .alertSecondButtonReturn {
            do { try statistics.reset(); notify("Daily statistics deleted.") }
            catch { notify("Statistics could not be deleted. Your data is still available.") }
        }
    }
}

import AppKit

@main enum StateTests {
    static func main() throws {
        NSTimeZone.default = TimeZone(identifier: "Europe/Chisinau")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = ISO8601DateFormatter().date(from: "2026-10-24T20:59:58Z")!
        let url = root.appendingPathComponent("stats.json")
        let stats = DailyStatistics(url: url, now: date)
        var frame = TrackingFrame(phase: .tracking)
        frame.trackedDelta = 0.1; frame.events = 5; frame.calibrated = true; frame.asymmetry = 0.2
        for _ in 0..<400 { stats.record(frame, now: date) }
        stats.reminder(now: date)
        stats.flush(synchronous: true)
        let restored = DailyStatistics(url: url, now: date)
        let today = restored.snapshot(now: date)["today"] as! [String: Any]
        precondition(today["blinks"] as? Int == 400)
        precondition(abs((today["trackedSeconds"] as! Double) - 40) < 0.001)
        precondition(abs((today["blinkRate"] as! Double) - 600) < 0.001)
        precondition(abs((today["asymmetry"] as! Double) - 20) < 0.001)
        precondition(today["reminders"] as? Int == 1)
        precondition((restored.snapshot(now: date.addingTimeInterval(5))["today"] as! [String: Any])["blinks"] as? Int == 0)
        let dstStart = ISO8601DateFormatter().date(from: "2026-10-24T21:00:00Z")!
        let dst = DailyStatistics(url: root.appendingPathComponent("dst.json"), now: dstStart)
        dst.record(frame, now: dstStart)
        dst.record(frame, now: dstStart.addingTimeInterval(24 * 3600 + 60))
        precondition((dst.snapshot(now: dstStart.addingTimeInterval(24 * 3600 + 60))["today"] as! [String: Any])["blinks"] as? Int == 2)
        for _ in 0..<20 { restored.record(frame, now: date); restored.flush() }
        try restored.reset()
        restored.flush(synchronous: true)
        let empty = try JSONDecoder().decode([DailyRecord].self, from: restored.exportData())
        precondition(empty.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: url.path))
        try Data("broken".utf8).write(to: url)
        let recovery = DailyStatistics(url: url, now: date)
        precondition(!(recovery.snapshot(now: date)["warning"] as! String).isEmpty)
        let original = try Data(contentsOf: url)
        precondition(original == Data("broken".utf8))
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        precondition(files.contains(where: { $0.contains("recovery-") }))
        recovery.record(frame, now: date); recovery.flush(synchronous: true)
        let recovered = try JSONDecoder().decode([DailyRecord].self, from: Data(contentsOf: url))
        precondition(recovered.count == 1)
        let directory = root.appendingPathComponent("not-a-file")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = DailyStatistics(url: directory, now: date)
        blocked.record(frame, now: date)
        do { try blocked.reset(); preconditionFailure("Reset must preserve a directory") } catch {}
        precondition((blocked.snapshot(now: date)["today"] as! [String: Any])["blinks"] as? Int == 1)
        precondition(DailyRecord(day: "2026-10-25").valid)
        precondition(!DailyRecord(day: "2026-02-30").valid)
        precondition(!DailyRecord(day: "----------").valid)
        precondition(!DailyRecord(day: "2026-10-25", asymmetryWeighted: 100, asymmetrySeconds: 1).valid)
        precondition(!DailyRecord(day: "2026-10-25", asymmetrySeconds: -1).valid)
        let suite = "BlinkMoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3.0, forKey: "blinkThreshold"); defaults.set(1.0, forKey: "fadeSpeed")
        let preferences = AppPreferences(defaults: defaults)
        precondition(preferences.reminderSeconds == 3 && preferences.fadeSeconds == 1)
        preferences.reminderSeconds = 100; preferences.sensitivity = -1
        precondition(preferences.reminderSeconds == 30 && preferences.sensitivity == 0)
        preferences.theme = "dark"; preferences.theme = "invalid"
        precondition(preferences.theme == "dark")
        precondition(!preferences.setColor(hex: "<script>"))
        precondition(preferences.setColor(hex: "#123abc") && preferences.colorHex == "#123abc")
        let legacyData = Data("""
        [{"day":"2026-10-24","trackedSeconds":60,"blinks":12,"leftClosures":1,"rightClosures":2,"reminders":0,"asymmetryWeighted":0,"asymmetrySeconds":0}]
        """.utf8)
        let legacyURL = root.appendingPathComponent("legacy.json")
        try legacyData.write(to: legacyURL)
        let legacy = DailyStatistics(url: legacyURL, now: date)
        let old = legacy.snapshot(now: date)["today"] as! [String: Any]
        precondition(old["blinks"] as? Int == 12 && old["longClosures"] is NSNull)
        precondition((legacy.snapshot(now: date)["warning"] as! String).isEmpty)
        let metrics = DailyStatistics(url: root.appendingPathComponent("metrics.json"), now: date)
        let priorDay = date.addingTimeInterval(-86400)
        var measured = TrackingFrame(phase: .tracking)
        measured.trackedDelta = 0.1; measured.calibrated = true
        for i in 0..<3000 {
            measured.events = i % 50 == 0 ? 7 : 3
            metrics.record(measured, now: priorDay)
        }
        for i in 0..<600 {
            measured.events = i % 100 < 3 ? 7 : 3
            metrics.record(measured, now: date)
        }
        let comparison = metrics.snapshot(now: date)
        let lifetime = comparison["lifetime"] as! [String: Any]
        precondition(lifetime["blinks"] as? Int == 78 && lifetime["days"] as? Int == 2)
        precondition(abs((lifetime["trackedSeconds"] as! Double) - 360) < 0.001)
        metrics.flush(synchronous: true)
        let restoredMetrics = DailyStatistics(url: root.appendingPathComponent("metrics.json"), now: date)
        let restoredLifetime = restoredMetrics.snapshot(now: date)["lifetime"] as! [String: Any]
        precondition(restoredLifetime["blinks"] as? Int == 78 && restoredLifetime["days"] as? Int == 2)
        precondition(abs((comparison["baselineRate"] as! Double) - 12) < 0.001)
        precondition(abs((comparison["relativePercent"] as! Double) - 50) < 0.001)
        precondition(abs((comparison["recentRate"] as! Double) - 18) < 0.001)
        precondition(metrics.snapshot(now: date.addingTimeInterval(60))["recentRate"] is NSNull)
        measured.phase = .eyesClosed; measured.closedMask = 3; measured.events = 3
        for _ in 0..<100 { metrics.record(measured, now: date) }
        measured.phase = .tracking; measured.closedMask = 0; measured.events = 35
        metrics.record(measured, now: date)
        let closure = metrics.snapshot(now: date)["today"] as! [String: Any]
        precondition(closure["longClosures"] as? Int == 1)
        precondition(abs((closure["closedPercent"] as! Double) - 10 / 70.1 * 100) < 0.001)
        precondition(closure["blinks"] as? Int == 18)
        precondition(!DailyRecord(day: "2026-10-24", bothClosedSeconds: 2, calibratedSeconds: 1).valid)
        precondition(!DailyRecord(day: "2026-10-24", calibratedSeconds: .nan).valid)
        let collecting = DailyStatistics(url: root.appendingPathComponent("collecting.json"), now: date)
        measured.events = 3
        for _ in 0..<149 { collecting.record(measured, now: date) }
        precondition(collecting.snapshot(now: date)["recentRate"] is NSNull)
        collecting.record(measured, now: date)
        precondition(collecting.snapshot(now: date)["recentRate"] as? Double == 0)
        try metrics.reset()
        precondition(metrics.snapshot(now: date)["recentRate"] is NSNull)
        precondition((metrics.snapshot(now: date)["lifetime"] as! [String: Any])["blinks"] as? Int == 0)
        preferences.blinkGoal = 500; preferences.minuteGoal = 45; preferences.dayGoal = 4
        let restoredPreferences = AppPreferences(defaults: defaults)
        precondition(restoredPreferences.blinkGoal == 500 && restoredPreferences.minuteGoal == 45 && restoredPreferences.dayGoal == 4)
        preferences.blinkGoal = -1; preferences.minuteGoal = 1000; preferences.dayGoal = 100
        precondition(preferences.blinkGoal == 10 && preferences.minuteGoal == 720 && preferences.dayGoal == 7)
        precondition(!preferences.exercisesEnabled && preferences.exerciseMinutes == 20)
        preferences.exercisesEnabled = true; preferences.exerciseMinutes = 999
        precondition(AppPreferences(defaults: defaults).exercisesEnabled && preferences.exerciseMinutes == 60)
        preferences.exerciseMinutes = -1
        precondition(preferences.exerciseMinutes == 5)
        let resetStats = DailyStatistics(url: root.appendingPathComponent("resets.json"), now: date)
        resetStats.completedReset(seconds: 30, now: date)
        resetStats.completedReset(seconds: 20, now: date)
        resetStats.completedReset(seconds: -1, now: date)
        resetStats.flush(synchronous: true)
        let resetRestored = DailyStatistics(url: root.appendingPathComponent("resets.json"), now: date)
        let resets = resetRestored.snapshot(now: date)
        precondition((resets["today"] as! [String: Any])["resets"] as? Int == 2)
        precondition((resets["today"] as! [String: Any])["resetSeconds"] as? Double == 50)
        precondition((resets["lifetime"] as! [String: Any])["resets"] as? Int == 2)
        precondition(old["resets"] is NSNull)
        precondition(!DailyRecord(day: "2026-10-24", resets: -1).valid)
        precondition(!DailyRecord(day: "2026-10-24", resetSeconds: .infinity).valid)
        let bins = comparison["recentBins"] as! [[String: Any]]
        precondition(bins.count == 60 && bins.last?["blinks"] as? Int == 18)
        precondition((metrics.snapshot(now: date.addingTimeInterval(60))["recentBins"] as! [[String: Any]]).allSatisfy { $0["tracked"] as? Double == 0 })
        try resetRestored.reset()
        precondition((resetRestored.snapshot(now: date)["lifetime"] as! [String: Any])["resets"] as? Int == 0)
        print("State tests passed: persistence, legacy history, rate windows, personal baseline, closure types, reset, recovery, DST, validation, preferences")
    }
}

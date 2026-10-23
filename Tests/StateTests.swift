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
        print("State tests passed: persistence, reset ordering, recovery, DST rollover, validation, preferences")
    }
}

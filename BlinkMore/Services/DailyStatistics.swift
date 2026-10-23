import Foundation

struct DailyRecord: Codable {
    var day: String
    var trackedSeconds: Double = 0
    var blinks = 0
    var leftClosures = 0
    var rightClosures = 0
    var reminders = 0
    var asymmetryWeighted: Double = 0
    var asymmetrySeconds: Double = 0

    var valid: Bool {
        Self.validDay(day) &&
        trackedSeconds.isFinite && (0...90001).contains(trackedSeconds) &&
        asymmetryWeighted.isFinite && asymmetryWeighted >= 0 && asymmetryWeighted <= asymmetrySeconds + 0.000001 &&
        asymmetrySeconds.isFinite && (0...90001).contains(asymmetrySeconds) &&
        [blinks, leftClosures, rightClosures, reminders].allSatisfy { (0...1_000_000).contains($0) }
    }
    private static func validDay(_ day: String) -> Bool {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.count) == [4, 2, 2], parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let date = Int(parts[2]), (1970...9999).contains(year) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        guard let value = calendar.date(from: DateComponents(year: year, month: month, day: date)) else { return false }
        return calendar.component(.month, from: value) == month && calendar.component(.day, from: value) == date
    }
    var json: [String: Any] {
        ["day": day, "trackedSeconds": trackedSeconds, "blinks": blinks,
         "leftClosures": leftClosures, "rightClosures": rightClosures, "reminders": reminders,
         "blinkRate": trackedSeconds >= 30 ? Double(blinks) * 60 / trackedSeconds : NSNull(),
         "asymmetry": asymmetrySeconds >= 5 ? asymmetryWeighted / asymmetrySeconds * 100 : NSNull()]
    }
}

final class DailyStatistics {
    private let lock = NSLock()
    private let io = DispatchQueue(label: "com.oxremy.blinkmore.statistics", qos: .utility)
    private let url: URL
    private var records: [String: DailyRecord] = [:]
    private var dirty = false
    private var saveAllowed = true
    private var warning: String?
    private var day: String
    private var dayStart: Date
    private var nextMidnight: Date
    private let formatter: DateFormatter

    init(url: URL? = nil, now: Date = Date()) {
        formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        day = formatter.string(from: now)
        dayStart = Calendar.current.startOfDay(for: now)
        nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlinkMore/daily-statistics.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            guard (try? self.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                saveAllowed = false; warning = "The statistics path is not a file. Existing contents were preserved."
                return
            }
            do {
                let values = try JSONDecoder().decode([DailyRecord].self, from: Data(contentsOf: self.url))
                guard values.allSatisfy(\.valid), Set(values.map(\.day)).count == values.count else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                records = Dictionary(uniqueKeysWithValues: values.map { ($0.day, $0) })
            } catch {
                do {
                    let backup = self.url.deletingPathExtension().appendingPathExtension("recovery-\(Int(now.timeIntervalSince1970)).json")
                    try FileManager.default.copyItem(at: self.url, to: backup)
                    warning = "Statistics could not be read. The original file was preserved for recovery."
                } catch {
                    saveAllowed = false
                    warning = "Statistics are available for this session, but the existing file could not be safely recovered."
                }
            }
        }
    }

    func record(_ frame: TrackingFrame, now: Date = Date()) {
        guard frame.events & 1 != 0, frame.trackedDelta.isFinite, (0...0.25).contains(frame.trackedDelta) else { return }
        lock.lock(); defer { lock.unlock() }
        rollDay(now)
        var value = records[day] ?? DailyRecord(day: day)
        value.trackedSeconds += frame.trackedDelta
        if frame.events & 4 != 0 { value.blinks += 1 }
        if frame.events & 8 != 0 { value.leftClosures += 1 }
        if frame.events & 16 != 0 { value.rightClosures += 1 }
        if frame.phase == .tracking && frame.calibrated && frame.asymmetry.isFinite {
            value.asymmetryWeighted += frame.asymmetry.clamped(to: 0...1) * frame.trackedDelta
            value.asymmetrySeconds += frame.trackedDelta
        }
        records[day] = value; dirty = true
    }

    func reminder(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        rollDay(now)
        var value = records[day] ?? DailyRecord(day: day)
        value.reminders += 1; records[day] = value; dirty = true
    }

    func snapshot(now: Date = Date()) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        rollDay(now)
        let week = (0..<7).reversed().map { offset -> [String: Any] in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now
            let key = formatter.string(from: date)
            return (records[key] ?? DailyRecord(day: key)).json
        }
        return ["today": (records[day] ?? DailyRecord(day: day)).json,
                "week": week, "warning": warning ?? ""]
    }

    func exportData() throws -> Data {
        lock.lock(); let values = records.values.sorted { $0.day < $1.day }; lock.unlock()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(values)
    }

    func flush(synchronous: Bool = false) {
        let save = {
            self.lock.lock()
            guard self.dirty, self.saveAllowed else { self.lock.unlock(); return }
            self.dirty = false
            let values = self.records.values.sorted { $0.day < $1.day }
            self.lock.unlock()
            do {
                let data = try JSONEncoder().encode(values)
                try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: self.url, options: [.atomic])
            } catch {
                self.lock.lock(); self.dirty = true
                self.warning = "Statistics could not be saved. Your current session remains available."
                self.lock.unlock()
            }
        }
        if synchronous { io.sync(execute: save) } else { io.async(execute: save) }
    }

    func reset() throws {
        // Serialize deletion with pending writes so old data cannot reappear after reset.
        try io.sync {
            lock.lock(); defer { lock.unlock() }
            if FileManager.default.fileExists(atPath: url.path) {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CocoaError(.fileWriteInvalidFileName) }
                try FileManager.default.removeItem(at: url)
            }
            records.removeAll(); dirty = false; warning = nil; saveAllowed = true
        }
    }

    private func rollDay(_ now: Date) {
        if now >= nextMidnight || now < dayStart {
            day = formatter.string(from: now)
            dayStart = Calendar.current.startOfDay(for: now)
            nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        }
    }
}

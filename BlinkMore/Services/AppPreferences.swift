import AppKit

final class AppPreferences {
    private let defaults: UserDefaults
    private var storedColor: NSColor
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedColor = defaults.data(forKey: "fadeColor").flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0)
        } ?? .black
    }

    var reminderSeconds: Double {
        get { bounded("blinkThreshold", fallback: 6, range: 3...30) }
        set { defaults.set(newValue.clamped(to: 3...30), forKey: "blinkThreshold"); onChange?() }
    }
    var fadeSeconds: Double {
        get { bounded("fadeSpeed", fallback: 1.5, range: 0.3...5) }
        set { defaults.set(newValue.clamped(to: 0.3...5), forKey: "fadeSpeed"); onChange?() }
    }
    var intensity: Double {
        get { bounded("fadeIntensity", fallback: 0.65, range: 0.15...0.9) }
        set { defaults.set(newValue.clamped(to: 0.15...0.9), forKey: "fadeIntensity"); onChange?() }
    }
    var sensitivity: Double {
        get { bounded("adaptiveSensitivity", fallback: 0.5, range: 0...1) }
        set { defaults.set(newValue.clamped(to: 0...1), forKey: "adaptiveSensitivity"); onChange?() }
    }
    var remindersEnabled: Bool {
        get { defaults.object(forKey: "remindersEnabled") == nil || defaults.bool(forKey: "remindersEnabled") }
        set { defaults.set(newValue, forKey: "remindersEnabled"); onChange?() }
    }
    var detectionAlerts: Bool {
        get { defaults.object(forKey: "detectionAlerts") == nil || defaults.bool(forKey: "detectionAlerts") }
        set { defaults.set(newValue, forKey: "detectionAlerts"); onChange?() }
    }
    var soundEnabled: Bool {
        get { defaults.bool(forKey: "soundEnabled") }
        set { defaults.set(newValue, forKey: "soundEnabled"); onChange?() }
    }
    var exercisesEnabled: Bool {
        get { defaults.bool(forKey: "exercisesEnabled") }
        set { defaults.set(newValue, forKey: "exercisesEnabled"); onChange?() }
    }
    var exerciseMinutes: Double {
        get { bounded("exerciseMinutes", fallback: 20, range: 5...60) }
        set { defaults.set(newValue.clamped(to: 5...60).rounded(), forKey: "exerciseMinutes"); onChange?() }
    }
    var blinkGoal: Double {
        get { bounded("dailyBlinkGoal", fallback: 300, range: 10...10000) }
        set { defaults.set(newValue.clamped(to: 10...10000).rounded(), forKey: "dailyBlinkGoal"); onChange?() }
    }
    var minuteGoal: Double {
        get { bounded("dailyMinuteGoal", fallback: 30, range: 1...720) }
        set { defaults.set(newValue.clamped(to: 1...720).rounded(), forKey: "dailyMinuteGoal"); onChange?() }
    }
    var resetGoal: Double {
        get { bounded("dailyResetGoal", fallback: 1, range: 1...10) }
        set { defaults.set(newValue.clamped(to: 1...10).rounded(), forKey: "dailyResetGoal"); onChange?() }
    }
    var dayGoal: Double {
        get { bounded("weeklyDayGoal", fallback: 3, range: 1...7) }
        set { defaults.set(newValue.clamped(to: 1...7).rounded(), forKey: "weeklyDayGoal"); onChange?() }
    }
    var theme: String {
        get { let value = defaults.string(forKey: "appearance") ?? "system"; return ["system", "light", "dark"].contains(value) ? value : "system" }
        set { guard ["system", "light", "dark"].contains(newValue) else { return }; defaults.set(newValue, forKey: "appearance"); onChange?() }
    }
    var cameraID: String? {
        get { defaults.string(forKey: "selectedCameraID") }
        set { defaults.set(newValue, forKey: "selectedCameraID"); onChange?() }
    }
    var pauseUntil: Date? {
        get { let value = defaults.double(forKey: "pauseUntil"); return value > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: value) : nil }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "pauseUntil"); onChange?() }
    }
    var fadeColor: NSColor {
        get { storedColor }
        set {
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false) else { return }
            storedColor = newValue; defaults.set(data, forKey: "fadeColor"); onChange?()
        }
    }
    var colorHex: String {
        guard let color = fadeColor.usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02x%02x%02x", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    func setColor(hex: String) -> Bool {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return false }
        fadeColor = NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        return true
    }
    func snapshot() -> [String: Any] {
        ["reminderSeconds": reminderSeconds, "fadeSeconds": fadeSeconds, "intensity": intensity,
         "detectionAlerts": detectionAlerts, "soundEnabled": soundEnabled, "sensitivity": sensitivity, "remindersEnabled": remindersEnabled, "theme": theme,
         "cameraID": cameraID ?? "", "color": colorHex, "pauseUntil": pauseUntil?.timeIntervalSince1970 ?? 0,
         "exercisesEnabled": exercisesEnabled, "exerciseMinutes": exerciseMinutes, "minuteGoal": minuteGoal, "resetGoal": resetGoal, "dayGoal": dayGoal]
    }
    private func bounded(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let value = defaults.double(forKey: key)
        return value.isFinite ? value.clamped(to: range) : fallback
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(range.upperBound, max(range.lowerBound, self)) }
}

import Foundation

struct ReminderPolicy {
    enum Mode: String { case idle, reminding, waitingForBlink }
    struct Decision { let visible: Bool; let triggered: Bool }
    private(set) var mode: Mode = .idle
    private var started: Double = 0
    private var lastOpenCapture: Double?
    private var previousOpenSeconds: Double = 0

    mutating func reset() { self = ReminderPolicy() }
    mutating func waitForBlink() { mode = .waitingForBlink }

    mutating func update(now: Double, frame: TrackingFrame, enabled: Bool, threshold: Double) -> Decision {
        guard enabled else { reset(); return Decision(visible: false, triggered: false) }
        let age = now - frame.timestamp
        let fresh = frame.timestamp > 0 && (0...0.35).contains(age) && frame.calibrated
        if fresh && (frame.phase == .eyesClosed || frame.events & 4 != 0) {
            reset(); return Decision(visible: false, triggered: false)
        }
        if fresh && frame.phase == .tracking {
            lastOpenCapture = frame.timestamp
            if mode == .waitingForBlink && frame.openSeconds + 0.01 < previousOpenSeconds { mode = .idle }
            previousOpenSeconds = frame.openSeconds
            if mode == .idle && frame.openSeconds >= threshold {
                mode = .reminding; started = now
                return Decision(visible: true, triggered: true)
            }
        } else if lastOpenCapture == nil || now - lastOpenCapture! >= 0.5 {
            reset(); return Decision(visible: false, triggered: false)
        }
        if mode == .reminding && now - started >= 6 { mode = .waitingForBlink }
        return Decision(visible: mode == .reminding, triggered: false)
    }
}

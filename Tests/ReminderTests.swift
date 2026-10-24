import Foundation

@main enum ReminderTests {
    static func main() {
        func open(_ time: Double, duration: Double) -> TrackingFrame {
            var frame = TrackingFrame(phase: .tracking)
            frame.timestamp = time; frame.calibrated = true; frame.openSeconds = duration
            return frame
        }
        var policy = ReminderPolicy()
        precondition(!policy.update(now: 4, frame: open(4, duration: 3.9), enabled: true, threshold: 4).visible)
        let start = policy.update(now: 4.1, frame: open(4.1, duration: 4), enabled: true, threshold: 4)
        precondition(start.visible && start.triggered)
        precondition(!policy.update(now: 4.2, frame: open(4.2, duration: 4.1), enabled: true, threshold: 4).triggered)
        var gap = TrackingFrame(phase: .delayed); gap.timestamp = 4.3
        precondition(policy.update(now: 4.4, frame: gap, enabled: true, threshold: 4).visible)
        precondition(policy.update(now: 4.5, frame: open(4.5, duration: 0), enabled: true, threshold: 4).visible)
        precondition(policy.update(now: 4.8, frame: open(4.8, duration: 0.3), enabled: true, threshold: 4).visible)
        var closed = open(4.9, duration: 0); closed.phase = .eyesClosed; closed.closedMask = 3
        precondition(!policy.update(now: 4.9, frame: closed, enabled: true, threshold: 4).visible)
        precondition(policy.mode == .idle)
        precondition(!policy.update(now: 5, frame: open(5, duration: 0), enabled: true, threshold: 4).visible)
        _ = policy.update(now: 9, frame: open(9, duration: 4), enabled: true, threshold: 4)
        precondition(!policy.update(now: 15, frame: open(15, duration: 10), enabled: true, threshold: 4).visible)
        precondition(policy.mode == .waitingForBlink)
        for i in 16...40 {
            let value = policy.update(now: Double(i), frame: open(Double(i), duration: Double(i) - 5), enabled: true, threshold: 4)
            precondition(!value.visible && !value.triggered)
        }
        _ = policy.update(now: 41, frame: open(41, duration: 0), enabled: true, threshold: 4)
        precondition(policy.mode == .idle)
        precondition(policy.update(now: 45, frame: open(45, duration: 4), enabled: true, threshold: 4).triggered)
        precondition(!policy.update(now: 45.6, frame: gap, enabled: true, threshold: 4).visible)
        precondition(policy.mode == .idle)
        _ = policy.update(now: 50, frame: open(50, duration: 4), enabled: true, threshold: 4)
        precondition(!policy.update(now: 50.1, frame: open(50.1, duration: 4), enabled: false, threshold: 4).visible)
        policy.waitForBlink()
        precondition(!policy.update(now: 51, frame: open(51, duration: 5), enabled: true, threshold: 4).visible)
        var reopened = open(52, duration: 0); reopened.events = 7
        _ = policy.update(now: 52, frame: reopened, enabled: true, threshold: 4)
        precondition(policy.mode == .idle)
        print("Reminder tests passed: one cue per blink interval, transient gap stability, closure, timeout, rearming, pause, preview separation")
    }
}

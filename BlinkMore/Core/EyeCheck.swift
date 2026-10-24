import Foundation

struct EyeCheck {
    enum Phase: String { case idle, running, completed, cancelled }
    private(set) var phase: Phase = .idle
    private var started: Double = 0
    private var lastTimestamp = -Double.infinity
    private var observed: Double = 0
    private var leftWeighted: Double = 0
    private var rightWeighted: Double = 0
    private var differenceWeighted: Double = 0
    private var differenceSeconds: Double = 0
    private var blinks = 0
    private var leftClosures = 0
    private var rightClosures = 0
    private var elapsed: Double = 0

    mutating func start(now: Double) {
        guard now.isFinite else { return }
        self = EyeCheck(); started = now; phase = .running
    }
    mutating func tick(now: Double) {
        guard phase == .running, now.isFinite else { return }
        elapsed = min(30, max(0, now - started))
        if elapsed >= 30 { phase = .completed }
    }
    mutating func cancel(now: Double) {
        guard phase == .running else { return }
        tick(now: now)
        if phase == .running { phase = .cancelled }
    }
    mutating func record(_ frame: TrackingFrame) {
        guard phase == .running, frame.timestamp.isFinite, frame.timestamp > lastTimestamp,
              frame.timestamp >= started, frame.timestamp <= started + 30,
              frame.events & 1 != 0, frame.calibrated, [.tracking, .eyesClosed].contains(frame.phase),
              frame.trackedDelta.isFinite, (0...0.25).contains(frame.trackedDelta),
              frame.left.isFinite, frame.right.isFinite, (0...3).contains(frame.left), (0...3).contains(frame.right) else { return }
        lastTimestamp = frame.timestamp
        let seconds = min(frame.trackedDelta, frame.timestamp - started, 30 - observed)
        observed += seconds
        leftWeighted += frame.left * seconds; rightWeighted += frame.right * seconds
        if frame.phase == .tracking {
            differenceWeighted += min(1, abs(frame.left - frame.right)) * seconds
            differenceSeconds += seconds
        }
        if frame.events & 4 != 0 { blinks += 1 }
        if frame.events & 8 != 0 { leftClosures += 1 }
        if frame.events & 16 != 0 { rightClosures += 1 }
    }
    func snapshot() -> [String: Any] {
        ["phase": phase.rawValue, "elapsed": elapsed, "remaining": 30 - elapsed,
         "progress": elapsed / 30, "observedSeconds": observed,
         "coverage": elapsed > 0 ? min(1, observed / elapsed) : 0,
         "left": observed + 1e-6 >= 5 ? leftWeighted / observed : NSNull(),
         "right": observed + 1e-6 >= 5 ? rightWeighted / observed : NSNull(),
         "difference": differenceSeconds + 1e-6 >= 5 ? differenceWeighted / differenceSeconds * 100 : NSNull(),
         "blinks": blinks, "leftClosures": leftClosures, "rightClosures": rightClosures]
    }
}

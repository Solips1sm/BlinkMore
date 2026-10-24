import Foundation

// Memory only; preserve inference samples before the main thread coalesces delivery.
final class MotionTrace {
    private let lock = NSLock()
    private var samples: [(Double, Double?, Double?, UInt32)] = []

    func record(_ frame: TrackingFrame) {
        guard frame.timestamp.isFinite, frame.timestamp > 0 else { return }
        let valid = frame.calibrated && [.tracking, .eyesClosed].contains(frame.phase) && frame.left.isFinite && frame.right.isFinite
        lock.lock(); defer { lock.unlock() }
        if let last = samples.last {
            if frame.timestamp == last.0 { return }
            if frame.timestamp < last.0 { samples.removeAll(keepingCapacity: true) }
        }
        samples.append((frame.timestamp, valid ? frame.left : nil, valid ? frame.right : nil, valid ? frame.events & 60 : 0))
        samples.removeAll { $0.0 < frame.timestamp - 60 }
        if samples.count > 1000 { samples.removeFirst(samples.count - 1000) }
    }

    func snapshot() -> [[String: Any]] {
        lock.lock(); let copy = samples; lock.unlock()
        return copy.map { ["t": $0.0, "left": $0.1.map { $0 as Any } ?? NSNull(),
                          "right": $0.2.map { $0 as Any } ?? NSNull(), "events": $0.3] }
    }
}

struct AttentionPolicy {
    private var candidate: TrackingPhase?
    private var since = 0.0
    private var lastPing = -Double.infinity
    private(set) var message = ""

    mutating func update(phase: TrackingPhase, now: Double, enabled: Bool) -> Bool {
        guard now.isFinite else { return false }
        let problem = [.multipleFaces, .lowQuality, .delayed, .cameraError, .cameraMissing, .cameraDenied].contains(phase)
        guard enabled && problem else { candidate = nil; message = ""; return false }
        if candidate != phase { candidate = phase; since = now; message = "" }
        guard now - since >= 2 else { return false }
        let fresh = message.isEmpty
        message = phase == .multipleFaces ? "More than one face. Observation paused." : phase.detail
        guard fresh && now - lastPing >= 30 else { return false }
        lastPing = now; return true
    }
}

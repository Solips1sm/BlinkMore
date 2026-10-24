import Foundation

// Memory only; preserve inference samples before the main thread coalesces delivery.
final class MotionTrace {
    private let lock = NSLock()
    private var coverage: [(time: Double, phase: TrackingPhase, delta: Double)] = []
    private var coverageStart = 0
    private var mirror = BlinkMirror()
    private var samples: [(Double, Double?, Double?, UInt32)] = []
    private var samplesStart = 0

    func record(_ frame: TrackingFrame) {
        guard frame.timestamp.isFinite, frame.timestamp > 0 else { return }
        let valid = frame.calibrated && [.tracking, .eyesClosed].contains(frame.phase) && frame.left.isFinite && frame.right.isFinite
        lock.lock(); defer { lock.unlock() }
        if let last = coverage.last, frame.timestamp < last.time {
            coverage.removeAll(keepingCapacity: true); coverageStart = 0; mirror.update(phase: "cancelled")
        }
        if coverage.last?.time != frame.timestamp {
            let delta = valid && frame.trackedDelta.isFinite ? min(0.25, max(0, frame.trackedDelta)) : 0
            coverage.append((frame.timestamp, frame.phase, delta))
            while coverageStart < coverage.count && coverage[coverageStart].time < frame.timestamp - 301 { coverageStart += 1 }
            if coverage.count - coverageStart > 6000 { coverageStart += coverage.count - coverageStart - 6000 }
            if coverageStart > 256 && coverageStart * 2 >= coverage.count {
                coverage.removeFirst(coverageStart); coverageStart = 0
            }
        }
        mirror.record(frame)
        if let last = samples.last {
            if frame.timestamp == last.0 { return }
            if frame.timestamp < last.0 { samples.removeAll(keepingCapacity: true); samplesStart = 0 }
        }
        samples.append((frame.timestamp, valid ? frame.left : nil, valid ? frame.right : nil, valid ? frame.events & 60 : 0))
        while samplesStart < samples.count && samples[samplesStart].0 < frame.timestamp - 60 { samplesStart += 1 }
        if samples.count - samplesStart > 1000 { samplesStart += samples.count - samplesStart - 1000 }
        if samplesStart > 256 && samplesStart * 2 >= samples.count {
            samples.removeFirst(samplesStart); samplesStart = 0
        }
    }

    func snapshot() -> [[String: Any]] {
        lock.lock(); let copy = Array(samples[samplesStart..<samples.endIndex]); lock.unlock()
        return copy.map { ["t": $0.0, "left": $0.1.map { $0 as Any } ?? NSNull(),
                          "right": $0.2.map { $0 as Any } ?? NSNull(), "events": $0.3] }
    }

    func clear() {
        lock.lock(); samples.removeAll(keepingCapacity: true); samplesStart = 0
        coverage.removeAll(keepingCapacity: true); coverageStart = 0; mirror = BlinkMirror(); lock.unlock()
    }

    func startMirror(now: Double) { lock.lock(); mirror.start(now: now); lock.unlock() }
    func updateMirror(phase: String) { lock.lock(); mirror.update(phase: phase); lock.unlock() }
    func mirrorSnapshot() -> [String: Any] {
        lock.lock(); let copy = mirror.detachedSnapshotCopy(); lock.unlock()
        return copy.snapshot()
    }

    func coverageSnapshot(now: Double) -> [String: Any] {
        guard now.isFinite else { return ["segments": [], "observedSeconds": 0, "span": 300] }
        lock.lock(); let points = Array(coverage[coverageStart..<coverage.endIndex]); lock.unlock()
        let floor = now - 300
        var segments: [(start: Double, end: Double, phase: TrackingPhase)] = []
        var observed = 0.0
        func append(_ start: Double, _ end: Double, _ phase: TrackingPhase) {
            let a = max(floor, start), b = min(now, end)
            guard b > a else { return }
            if let last = segments.last, last.phase == phase, abs(last.end - a) < 0.000001 {
                segments[segments.count - 1].end = b
            } else { segments.append((a, b, phase)) }
        }
        for (i, point) in points.enumerated() where point.time <= now {
            observed += max(0, min(now, point.time) - max(floor, point.time - point.delta))
            let end = i + 1 < points.count ? points[i + 1].time : now
            let offline = [.paused, .cameraDenied, .cameraMissing, .cameraError, .starting].contains(point.phase)
            let knownEnd = offline ? end : min(end, point.time + 0.5)
            append(point.time, knownEnd, point.phase)
            append(knownEnd, end, .delayed)
        }
        return ["span": 300, "observedSeconds": min(300, observed),
                "segments": segments.map { ["start": $0.start - floor, "end": $0.end - floor, "phase": $0.phase.rawValue] }]
    }

}

struct BlinkMirror {
    private var phase = "idle"
    private var started = 0.0
    private var samples: [(time: Double, left: Double?, right: Double?, events: UInt32)] = []
    private var samplesStart = 0
    private var observed = 0.0
    private var blinks = 0

    mutating func start(now: Double) {
        guard now.isFinite else { return }
        self = BlinkMirror(); started = now; phase = "running"
    }
    mutating func update(phase next: String) {
        guard phase == "running" || phase == "paused" else { return }
        if ["running", "paused", "completed"].contains(next) { phase = next }
        else { phase = "cancelled" }
    }
    mutating func record(_ frame: TrackingFrame) {
        guard phase == "running", frame.timestamp.isFinite, frame.timestamp >= started,
              samples.last.map({ frame.timestamp > $0.time }) ?? true else { return }
        let valid = frame.calibrated && frame.events & 1 != 0 && [.tracking, .eyesClosed].contains(frame.phase)
            && frame.left.isFinite && frame.right.isFinite && frame.trackedDelta.isFinite && (0...0.25).contains(frame.trackedDelta)
        samples.append((frame.timestamp, valid ? frame.left : nil, valid ? frame.right : nil, valid ? frame.events & 60 : 0))
        if samples.count - samplesStart > 300 { samplesStart += samples.count - samplesStart - 300 }
        if samplesStart > 128 && samplesStart * 2 >= samples.count {
            samples.removeFirst(samplesStart); samplesStart = 0
        }
        if valid {
            observed = min(10, observed + min(frame.trackedDelta, frame.timestamp - started))
            if frame.events & 4 != 0 { blinks += 1 }
        }
    }
    fileprivate func detachedSnapshotCopy() -> BlinkMirror {
        var copy = self
        copy.samples = Array(samples[samplesStart..<samples.endIndex])
        copy.samplesStart = 0
        return copy
    }
    func snapshot() -> [String: Any] {
        var clip: [[String: Any]] = []
        let samples = samples[samplesStart..<samples.endIndex]
        if let blink = samples.last(where: { $0.events & 4 != 0 }) {
            let start = blink.time - 0.5
            clip = samples.filter { (start...blink.time + 0.3).contains($0.time) }.map {
                ["t": $0.time - start, "left": $0.left.map { $0 as Any } ?? NSNull(),
                 "right": $0.right.map { $0 as Any } ?? NSNull(), "events": $0.events]
            }
        }
        return ["phase": phase, "observedSeconds": observed, "blinks": blinks, "clip": clip]
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

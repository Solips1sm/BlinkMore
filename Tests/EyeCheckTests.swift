import Foundation

@main enum EyeCheckTests {
    static func main() {
        var check = EyeCheck()
        check.start(now: 100)
        var frame = TrackingFrame(phase: .tracking, left: 1, right: 0.8, trackedDelta: 0.1, events: 1, calibrated: true)
        for i in 1...100 { frame.timestamp = 100 + Double(i) / 10; frame.events = i % 20 == 0 ? 5 : 1; check.record(frame) }
        check.record(frame)
        check.tick(now: 110)
        var result = check.snapshot()
        precondition(abs(result["observedSeconds"] as! Double - 10) < 1e-6)
        precondition(result["blinks"] as! Int == 5)
        precondition(abs(result["difference"] as! Double - 20) < 1e-6)
        frame.timestamp = 115; frame.calibrated = false; check.record(frame)
        frame.timestamp = 116; frame.calibrated = true; frame.left = .nan; check.record(frame)
        check.tick(now: 130)
        result = check.snapshot()
        precondition(check.phase == .completed && abs(result["coverage"] as! Double - 1.0 / 3) < 1e-6)
        frame.timestamp = 129; frame.left = 1; check.record(frame)
        precondition(check.snapshot()["blinks"] as! Int == 5)
        check.start(now: 200); check.tick(now: 230)
        precondition(check.snapshot()["left"] is NSNull)
        check.start(now: 300); check.cancel(now: 305)
        precondition(check.phase == .cancelled && check.snapshot()["elapsed"] as! Double == 5)
        check.start(now: .nan); precondition(check.phase == .cancelled)
        print("Eye check passed: valid exposure, weighted opening difference, one count, missing coverage, terminal state, cancellation and empty results")
    }
}

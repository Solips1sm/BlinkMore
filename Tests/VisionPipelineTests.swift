import AppKit
import AVFoundation
import Vision

@main enum VisionPipelineTests {
    @MainActor static func main() async throws {
        precondition(EyeTrackingService.captureDuration(ranges: [1...30]) == CMTime(value: 1, timescale: 15))
        precondition(EyeTrackingService.captureDuration(ranges: [24...60]) == nil)
        precondition(EyeTrackingService.captureDuration(ranges: []) == nil)
        var delivery = TrackingDelivery()
        var blink = TrackingFrame(phase: .tracking, timestamp: 10, events: 4, calibrated: true)
        delivery.replace(blink)
        var fresh = TrackingFrame(phase: .tracking, timestamp: 10.1, left: 0.9, calibrated: true)
        delivery.replace(fresh)
        let received = delivery.take()!
        precondition(received.timestamp == 10.1 && received.left == 0.9 && received.events & 4 != 0)
        precondition(delivery.take() == nil)
        delivery.replace(fresh); precondition(delivery.take()!.events == 0)
        delivery.replace(blink); fresh.timestamp = 10.2; delivery.replace(fresh)
        fresh.timestamp = 10.3; delivery.replace(fresh)
        precondition(delivery.take()!.events == 0)
        delivery.replace(blink); delivery.replace(TrackingFrame(phase: .noFace, timestamp: 10.1))
        fresh.timestamp = 10.2; delivery.replace(fresh)
        precondition(delivery.take()!.events == 0)
        blink.timestamp = 11; delivery.replace(blink); fresh.timestamp = 10.9; delivery.replace(fresh)
        precondition(delivery.take()!.events == 0)
        let main = VNFaceObservation(boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.6))
        let background = VNFaceObservation(boundingBox: CGRect(x: 0.75, y: 0.2, width: 0.15, height: 0.2))
        let peer = VNFaceObservation(boundingBox: CGRect(x: 0.65, y: 0.2, width: 0.35, height: 0.6))
        let size = CGSize(width: 640, height: 480)
        if case .selected(let face) = FaceSelection.choose([background, main], previous: nil, imageSize: size) { precondition(face === main) } else { preconditionFailure() }
        if case .ambiguous = FaceSelection.choose([main, peer], previous: nil, imageSize: size) {} else { preconditionFailure() }
        if case .selected(let face) = FaceSelection.choose([peer, main], previous: main.boundingBox, imageSize: size) { precondition(face === main) } else { preconditionFailure() }
        if case .none = FaceSelection.choose([], previous: nil, imageSize: size) {} else { preconditionFailure() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let statistics = DailyStatistics(url: root.appendingPathComponent("stats.json"))
        var frames: [(TrackingPhase, Double)] = []
        let service = EyeTrackingService(cameraID: nil, sensitivity: 0.5, statistics: statistics) { frame in
            frames.append((frame.phase, frame.timestamp))
            if ![.noFace, .delayed].contains(frame.phase) { print("Unexpected phase:", frame.phase.rawValue, frame.qualityNote); fflush(stdout) }
        }
        var buffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(buffer!, [])
        memset(CVPixelBufferGetBaseAddress(buffer!), 0, CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        for _ in 0..<25 {
            service.enqueue(buffer!, timestamp: EyeTrackingService.clock())
            try await Task.sleep(for: .milliseconds(35))
        }
        for _ in 0..<60 {
            if frames.contains(where: { $0.0 == .noFace }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(frames.contains { $0.0 == .noFace } && frames.allSatisfy { [.noFace, .delayed].contains($0.0) })
        let searches = frames.filter { $0.0 == .noFace }
        if let first = searches.first, let last = searches.last {
            // Search starts are 200 ms apart; admitted captures can differ in age by 100 ms.
            precondition(Double(searches.count - 1) * 0.2 <= last.1 - first.1 + 0.1 + 1e-6)
        }
        await withCheckedContinuation { continuation in service.stop { continuation.resume() } }
        // A separate pipeline cannot confuse a pending fresh result with the stale probe.
        var staleFrames: [TrackingFrame] = []
        let staleService = EyeTrackingService(cameraID: nil, sensitivity: 0.5, statistics: statistics) { staleFrames.append($0) }
        staleService.enqueue(buffer!, timestamp: EyeTrackingService.clock() - 1)
        for _ in 0..<20 {
            if !staleFrames.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(staleFrames.count == 1 && staleFrames[0].phase == .delayed)
        let today = statistics.snapshot()["today"] as! [String: Any]
        precondition(today["trackedSeconds"] as! Double == 0)
        await withCheckedContinuation { continuation in staleService.stop { continuation.resume() } }
        print("Vision pipeline tests passed: actual no-face inference, bounded search rate, camera rate fallback, coalesced blink preservation and expiry, stale-frame rejection, no invented activity")
    }
}

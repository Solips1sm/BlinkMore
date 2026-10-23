import AppKit
import AVFoundation
import Vision

@main enum VisionPipelineTests {
    @MainActor static func main() async throws {
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
        precondition(frames.contains { $0.0 == .noFace } && frames.allSatisfy { [.noFace, .delayed].contains($0.0) })
        let searches = frames.filter { $0.0 == .noFace }
        for pair in zip(searches, searches.dropFirst()) { precondition(pair.1.1 - pair.0.1 >= 0.15) }
        let before = frames.count
        service.enqueue(buffer!, timestamp: EyeTrackingService.clock() - 1)
        for _ in 0..<20 {
            if frames.count > before { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(frames.count == before + 1 && frames.last!.0 == .delayed)
        let today = statistics.snapshot()["today"] as! [String: Any]
        precondition(today["trackedSeconds"] as! Double == 0)
        await withCheckedContinuation { continuation in service.stop { continuation.resume() } }
        print("Vision pipeline tests passed: actual no-face inference, bounded search rate, stale-frame rejection, no invented activity")
    }
}

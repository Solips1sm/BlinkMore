import Foundation

@main enum CoreBridgeTests {
    static func main() {
        precondition(MemoryLayout<BMPoint>.size == 16)
        precondition(MemoryLayout<BMInput>.size == 72)
        precondition(MemoryLayout<BMOutput>.size == 80)
        let tracker = bm_tracker_new()!
        defer { bm_tracker_free(tracker) }
        func step(_ timestamp: Double, closed: Bool) -> BMOutput {
            let left = (0..<8).map { i -> BMPoint in
                let angle = Double(i) * .pi / 4
                return BMPoint(x: 0.5 + 0.1 * cos(angle), y: 0.5 + (closed ? 0.004 : 0.04) * sin(angle))
            }
            let right = left
            return left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in
                bm_tracker_process(tracker, BMInput(left: l.baseAddress, left_count: UInt32(l.count), right: r.baseAddress,
                    right_count: UInt32(r.count), face_width: 200, face_height: 300, timestamp: timestamp, confidence: 1, sensitivity: 0.5))
            } }
        }
        for i in 1...60 { _ = step(Double(i) / 30, closed: false) }
        let open = step(2.04, closed: false)
        precondition(open.phase == 2 && open.flags & 2 != 0 && open.left_openness > 0.9)
        precondition(step(2.08, closed: true).closed_mask == 3)
        _ = step(2.12, closed: true)
        precondition(step(2.16, closed: false).flags & 4 != 0)
        precondition(step(2.20, closed: false).flags & 4 == 0)
        precondition(step(2.19, closed: false).phase == 5)
        bm_tracker_reset(tracker)
        precondition(step(3, closed: false).phase == 1)
        print("Swift to Rust ABI tests passed: layout, borrowed buffers, calibration, blink, stale input, reset")
    }
}

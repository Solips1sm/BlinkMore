import Foundation
@main enum PerformanceBenchmarks {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        let stats = DailyStatistics(url: folder.appendingPathComponent("stats.json"), now: now)
        var results: [[String: Any]] = []
        var checksum = 0
        for (name, operation) in [("statisticsSnapshot", { stats.snapshot(now: now) })] {
            for _ in 0..<100 { _ = operation() }
            var times: [Double] = []
            for _ in 0..<1000 {
                let start = DispatchTime.now().uptimeNanoseconds
                let value = operation()
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1000)
                checksum += value.count
            }
            times.sort()
            results.append(["name": name, "samples": times.count, "medianUs": times[500], "p95Us": times[950]])
        }
        precondition(checksum > 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit":"microseconds", "fixture":"Isolated empty statistics store; excludes camera and Vision", "results":results], options: [.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
    }
}

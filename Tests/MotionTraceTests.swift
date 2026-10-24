import Foundation

@main enum MotionTraceTests {
    static func main() {
        let trace = MotionTrace()
        for i in 0..<1200 {
            trace.record(TrackingFrame(phase: .tracking, timestamp: 1+Double(i)/15, left: i == 1198 ? 0.1 : 1, right: 1, events: i == 1199 ? 4 : 0, calibrated: true))
        }
        let samples = trace.snapshot()
        precondition(samples.count <= 901 && samples.count >= 899)
        precondition(samples[samples.count-2]["left"] as! Double == 0.1)
        precondition(samples.last!["events"] as! UInt32 == 4)
        trace.record(TrackingFrame(phase: .noFace,timestamp:81))
        precondition(trace.snapshot().last!["left"] is NSNull)
        trace.record(TrackingFrame(phase: .tracking,timestamp:0.5,left:1,right:1,calibrated:true))
        precondition(trace.snapshot().count == 1)
        trace.record(TrackingFrame(timestamp:.nan)); precondition(trace.snapshot().count == 1)
        let dense = MotionTrace()
        for i in 0..<2300 {
            dense.record(TrackingFrame(phase:.tracking,timestamp:1+Double(i)/60,left:1,right:1,calibrated:true))
        }
        let denseSamples = dense.snapshot()
        precondition(denseSamples.count == 1000)
        precondition(abs((denseSamples.first!["t"] as! Double) - (1+1300.0/60)) < 1e-9)
        precondition(abs((denseSamples.last!["t"] as! Double) - (1+2299.0/60)) < 1e-9)
        let denseMirror = MotionTrace()
        denseMirror.startMirror(now:300)
        for i in 0..<700 {
            denseMirror.record(TrackingFrame(phase:.tracking,timestamp:300+Double(i)/60,left:1,right:1,
                trackedDelta:1.0/60,events:i == 699 ? 5 : 1,calibrated:true))
        }
        let denseClip = denseMirror.mirrorSnapshot()["clip"] as! [[String:Any]]
        precondition((denseMirror.mirrorSnapshot()["blinks"] as! Int) == 1 && (30...31).contains(denseClip.count))
        let denseCoverage = MotionTrace()
        for i in 0..<19000 {
            denseCoverage.record(TrackingFrame(phase:.tracking,timestamp:1+Double(i)/60))
        }
        let retainedCoverage = denseCoverage.coverageSnapshot(now:1+18999.0/60)["segments"] as! [[String:Any]]
        precondition((retainedCoverage.first?["start"] as? Double ?? 0) > 199)
        let history = MotionTrace()
        history.startMirror(now: 100)
        for i in 0...30 {
            history.record(TrackingFrame(phase:.tracking,timestamp:100+Double(i)/15,left:i == 12 ? 0.1 : 1,right:i == 12 ? 0.1 : 0.9,trackedDelta:1.0/15,events:i == 14 ? 7 : 3,calibrated:true))
        }
        var mirror = history.mirrorSnapshot()
        precondition(mirror["blinks"] as! Int == 1)
        precondition(abs((mirror["observedSeconds"] as! Double)-2)<1e-6)
        let clip = mirror["clip"] as! [[String:Any]]
        precondition(clip.contains { ($0["left"] as? Double) == 0.1 })
        history.updateMirror(phase:"paused")
        history.record(TrackingFrame(phase:.tracking,timestamp:103,left:1,right:1,trackedDelta:0.1,events:7,calibrated:true))
        precondition(history.mirrorSnapshot()["blinks"] as! Int == 1)
        history.updateMirror(phase:"running")
        history.record(TrackingFrame(phase:.tracking,timestamp:104,left:1,right:1,trackedDelta:0.1,events:7,calibrated:true))
        history.updateMirror(phase:"completed")
        mirror = history.mirrorSnapshot(); precondition(mirror["blinks"] as! Int == 2)
        history.record(TrackingFrame(phase:.tracking,timestamp:104.1,left:1,right:1,trackedDelta:0.1,events:7,calibrated:true))
        precondition(history.mirrorSnapshot()["blinks"] as! Int == 2)
        let coverage = history.coverageSnapshot(now:108)
        precondition(abs((coverage["observedSeconds"] as! Double)-(2.3+1.0/15))<1e-6)
        let segments = coverage["segments"] as! [[String:Any]]
        precondition(segments.contains { $0["phase"] as? String == "delayed" })
        precondition(segments.allSatisfy { ($0["start"] as! Double) >= 0 && ($0["end"] as! Double) <= 300 })
        history.record(TrackingFrame(phase:.paused,timestamp:109))
        let paused = history.coverageSnapshot(now:120)["segments"] as! [[String:Any]]
        precondition(paused.last!["phase"] as! String == "paused" && paused.last!["end"] as! Double == 300)
        history.clear(); precondition((history.coverageSnapshot(now:120)["segments"] as! [[String:Any]]).isEmpty)
        precondition(history.mirrorSnapshot()["phase"] as! String == "idle")
        history.startMirror(now:200)
        history.record(TrackingFrame(phase:.tracking,timestamp:201,left:1,right:1,trackedDelta:0.1,events:7,calibrated:true))
        history.updateMirror(phase:"cancelled"); history.updateMirror(phase:"running")
        precondition(history.mirrorSnapshot()["phase"] as! String == "cancelled")
        var policy = AttentionPolicy()
        precondition(!policy.update(phase:.multipleFaces,now:10,enabled:true))
        precondition(!policy.update(phase:.multipleFaces,now:11.9,enabled:true))
        precondition(policy.update(phase:.multipleFaces,now:12,enabled:true))
        precondition(!policy.update(phase:.multipleFaces,now:13,enabled:true))
        precondition(!policy.message.isEmpty)
        precondition(!policy.update(phase:.tracking,now:14,enabled:true) && policy.message.isEmpty)
        precondition(!policy.update(phase:.delayed,now:15,enabled:true))
        precondition(!policy.update(phase:.delayed,now:17,enabled:true) && !policy.message.isEmpty)
        precondition(!policy.update(phase:.tracking,now:40,enabled:true))
        precondition(!policy.update(phase:.lowQuality,now:41,enabled:true))
        precondition(policy.update(phase:.lowQuality,now:43,enabled:true))
        precondition(!policy.update(phase:.lowQuality,now:44,enabled:false) && policy.message.isEmpty)
        print("Motion and attention tests passed: inference closures, bounded history, gaps, clock reset, alert debounce, cooldown and disabling")
    }
}

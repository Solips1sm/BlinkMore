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

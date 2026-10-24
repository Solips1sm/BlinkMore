import Foundation

struct ExercisePolicy {
    enum Routine: String { case reset, blink, look
        var duration: Double { self == .reset ? 30 : self == .blink ? 10 : 20 }
    }
    enum Phase: String { case idle, running, paused, completed }
    private(set) var phase: Phase = .idle
    private(set) var routine: Routine = .reset
    private(set) var due = false
    private var started: Double = 0
    private var accumulated: Double = 0
    private var deadline: Double?
    private var scheduled = false
    private var interval: Double = 1200
    var active: Bool { phase == .running || phase == .paused }

    func elapsed(now: Double) -> Double {
        min(routine.duration, max(0, accumulated + (phase == .running ? max(0, now - started) : 0)))
    }
    mutating func start(_ routine: Routine, now: Double) {
        guard now.isFinite else { return }
        self.routine = routine; phase = .running; accumulated = 0; started = now; due = false; deadline = nil
    }
    mutating func pause(now: Double) {
        guard phase == .running, now.isFinite else { return }
        accumulated = elapsed(now: now); phase = .paused
    }
    mutating func resume(now: Double) {
        guard phase == .paused, now.isFinite else { return }
        started = now; phase = .running
    }
    mutating func end(now: Double) {
        phase = .idle; accumulated = 0; due = false
        deadline = scheduled && now.isFinite ? now + interval : nil
    }
    mutating func later(now: Double) {
        guard !active, now.isFinite else { return }
        due = false; deadline = scheduled ? now + 300 : nil
    }
    mutating func tick(now: Double, eligible: Bool, enabled: Bool, minutes: Double) -> Bool {
        guard now.isFinite else { return false }
        let nextInterval = (minutes.isFinite ? min(60, max(5, minutes)) : 20) * 60
        if enabled != scheduled || nextInterval != interval {
            scheduled = enabled; interval = nextInterval; due = false; deadline = nil
        }
        guard eligible else { end(now: now); deadline = nil; return false }
        if phase == .running && elapsed(now: now) >= routine.duration {
            accumulated = routine.duration; phase = .completed; due = false
            deadline = scheduled ? now + interval : nil
            return true
        }
        if !scheduled { due = false; deadline = nil }
        if scheduled && !active && !due {
            if deadline == nil { deadline = now + interval }
            if now >= deadline! { due = true; deadline = nil }
        }
        return false
    }
    func snapshot(now: Double) -> [String: Any] {
        let elapsed = elapsed(now: now)
        let step = routine == .look || (routine == .reset && elapsed >= 10) ? "look" : "blink"
        let stepDuration: Double = step == "look" ? 20 : 10
        let stepElapsed = routine == .reset && step == "look" ? elapsed - 10 : elapsed
        return ["phase": phase.rawValue, "routine": routine.rawValue, "step": step,
                "remaining": max(0, stepDuration - stepElapsed), "progress": elapsed / routine.duration,
                "due": due]
    }
}

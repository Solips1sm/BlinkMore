import Foundation
import CoreGraphics

@main enum SessionActivityTests {
    static func main() {
        precondition(kCGSessionOnConsoleKey as String == "kCGSSessionOnConsoleKey")
        var activity = SessionActivity()
        precondition(!activity.suspended)
        activity.receive(.lock); activity.receive(.sleep); activity.receive(.screenSleep); activity.receive(.resign)
        activity.receive(.wake)
        precondition(activity.suspended && activity.locked && activity.screenSleeping && activity.inactive)
        activity.receive(.unlock); activity.receive(.activate)
        precondition(activity.suspended && activity.screenSleeping)
        activity.receive(.screenWake); precondition(!activity.suspended)
        activity.receive(.sleep); activity.receive(.sleep); activity.receive(.wake)
        precondition(!activity.suspended)
        var lockedLaunch = SessionActivity(session: ["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": true, "kCGSessionLoginDoneKey": true])
        precondition(lockedLaunch.suspended)
        lockedLaunch.receive(.wake); precondition(lockedLaunch.suspended)
        lockedLaunch.receive(.unlock); precondition(!lockedLaunch.suspended)
        let otherSession = SessionActivity(session: ["kCGSSessionOnConsoleKey": false])
        precondition(otherSession.suspended)
        print("Session lifecycle passed: overlapping lock, sleep, screen and console state, repeated events, locked launch")
    }
}

import Foundation

struct SessionActivity {
    enum Event { case sleep, wake, screenSleep, screenWake, lock, unlock, resign, activate }
    private(set) var sleeping = false
    private(set) var screenSleeping = false
    private(set) var locked = false
    private(set) var inactive = false
    var suspended: Bool { sleeping || screenSleeping || locked || inactive }

    init(session: [String: Any]? = nil) {
        if let session {
            // shortcut: macOS exposes initial lock state through this session key; retain notification tracking too.
            locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
            inactive = session["kCGSSessionOnConsoleKey"] as? Bool == false || session["kCGSessionLoginDoneKey"] as? Bool == false
        }
    }

    mutating func receive(_ event: Event) {
        switch event {
        case .sleep: sleeping = true
        case .wake: sleeping = false
        case .screenSleep: screenSleeping = true
        case .screenWake: screenSleeping = false
        case .lock: locked = true
        case .unlock: locked = false
        case .resign: inactive = true
        case .activate: inactive = false
        }
    }
}

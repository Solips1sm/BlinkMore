import AppKit
import IOKit.ps
import Darwin

final class BlinkMoreACAgent {
    private var appURL: URL? {
        ["/Applications/Eyesight.app", "/Applications/BlinkMore.app"].map { URL(fileURLWithPath: $0) }
            .first { Bundle(url: $0)?.bundleIdentifier == "com.oxremy.blinkmorefree" }
    }
    private var opening = false
    private var stops = PowerStopPolicy()

    func onACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return false
        }
        return source as String == kIOPSACPowerValue
    }

    private func stop(_ app: NSRunningApplication) {
        guard stops.request(app.processIdentifier) else { return }
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.stops.complete(app.processIdentifier, onAC: self.onACPower(), terminated: app.isTerminated) { app.forceTerminate() }
            self.reconcile()
        }
    }

    func reconcile() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.oxremy.blinkmorefree")
            .filter { !$0.isTerminated && ["/Applications/Eyesight.app", "/Applications/BlinkMore.app"].contains($0.bundleURL?.standardizedFileURL.path ?? "") }
        guard onACPower() else {
            for app in apps {
                stop(app)
            }
            return
        }
        guard apps.isEmpty, !opening, let appURL = appURL else { return }
        opening = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = false
        if CommandLine.arguments.contains("--diagnose") { configuration.arguments = ["--diagnose"] }
        NSLog("AC power: launching Eyesight")
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                self.opening = false
                if let error = error {
                    NSLog("Eyesight launch failed: %@", error.localizedDescription)
                }
                if !self.onACPower(), let app = app {
                    self.stop(app)
                }
            }
        }
    }
}

@main enum BlinkMoreACMain {
    static func main() {
        if CommandLine.arguments.contains("--stop") {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.oxremy.blinkmorefree")
                .filter { ["/Applications/Eyesight.app", "/Applications/BlinkMore.app"].contains($0.bundleURL?.standardizedFileURL.path ?? "") }
            apps.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(3)
            while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
            exit(0)
        }

        let agent = BlinkMoreACAgent()
        guard let powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            Unmanaged<BlinkMoreACAgent>.fromOpaque(context).takeUnretainedValue().reconcile()
        }, Unmanaged.passUnretained(agent).toOpaque())?.takeRetainedValue() else {
            fputs("Cannot subscribe to power source notifications\n", stderr)
            exit(1)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes)
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in agent.reconcile() }
        RunLoop.main.add(timer, forMode: .common)
        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in agent.reconcile() }
        let terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "com.oxremy.blinkmorefree" { agent.reconcile() }
        }
        agent.reconcile()
        RunLoop.main.run()
        withExtendedLifetime((wakeObserver, terminationObserver)) {}
    }
}

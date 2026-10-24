import AppKit
import WebKit

@main enum NativeWindowTests {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); print("Native window passed: actual menu click, restore, reopen, setup route, blink images, state accessibility and WebKit recovery"); exit(0) }
            catch { fputs("Native window failed: \(error)\n",stderr); exit(1) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Eyesight-Native-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:temp) }
        let resources = Bundle.main.resourceURL?.appendingPathComponent("UI") ?? root.appendingPathComponent("BlinkMore/Resources/UI")
        let owner = ApplicationController(preferences:AppPreferences(defaults:defaults), statistics:DailyStatistics(url:temp.appendingPathComponent("stats.json")), resources:resources)
        owner.command(["action":"set", "key":"practiceGoal", "value":43.0])
        owner.command(["action":"set", "key":"practiceDayGoal", "value":4.0])
        var goals = owner.snapshot()["preferences"] as! [String:Any]
        precondition(goals["practiceGoal"] as? Double == 40 && goals["practiceDayGoal"] as? Double == 4)
        owner.command(["action":"set", "key":"practiceGoal", "value":true])
        goals = owner.snapshot()["preferences"] as! [String:Any]
        precondition(goals["practiceGoal"] as? Double == 40)
        owner.installMenu()
        func ready(_ window: DashboardWindowController) async throws {
            for _ in 0..<100 {
                if window.interfaceAvailable { return }
                try await Task.sleep(for:.milliseconds(100))
            }
            preconditionFailure("Native window did not load its local interface")
        }
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<200 {
                if condition() { return }
                try await Task.sleep(for:.milliseconds(50))
            }
        }
        func studio(_ window: DashboardWindowController) async throws -> String? {
            let value: Any = try await withCheckedThrowingContinuation { continuation in
                window.webView.callAsyncJavaScript("return document.getElementById('examine').dataset.studio",arguments:[:],in:nil,in:.page) { result in continuation.resume(with:result) }
            }
            return value as? String
        }
        func selectStudio(_ window: DashboardWindowController, _ name: String) async throws -> String? {
            let value: Any = try await withCheckedThrowingContinuation { continuation in
                window.webView.callAsyncJavaScript("document.querySelector('[data-studio=\"' + name + '\"]').click(); return document.getElementById('examine').dataset.studio",arguments:["name":name],in:nil,in:.page) { result in continuation.resume(with:result) }
            }
            return value as? String
        }
        func waitForStudio(_ window: DashboardWindowController, _ expected: String) async throws {
            for _ in 0..<40 {
                if try await studio(window) == expected { return }
                try await Task.sleep(for:.milliseconds(50))
            }
            preconditionFailure("Native window studio did not change to \(expected)")
        }
        owner.menu.item.button!.performClick(nil)
        let first = owner.dashboard!
        try await ready(first)
        precondition(first.window!.isVisible)
        let assets: Any = try await withCheckedThrowingContinuation { continuation in
            first.webView.callAsyncJavaScript("const logo=document.querySelector('.logo');await logo.decode();return logo.naturalWidth>0&&getComputedStyle(logo).objectFit==='contain'&&typeof window.blinkmore.update==='function'",arguments:[:],in:nil,in:.page) { result in continuation.resume(with:result) }
        }
        precondition(assets as? Bool == true, "Bundled SVG, stylesheet and controls must load")
        precondition(first.window!.collectionBehavior.contains(.moveToActiveSpace))

        // Leaving setup must clear its native route before a reload.
        let enterLive: Any = try await withCheckedThrowingContinuation { continuation in
            first.webView.callAsyncJavaScript("document.getElementById('tab-live').click();return document.getElementById('examine').dataset.studio",arguments:[:],in:nil,in:.page) { result in continuation.resume(with:result) }
        }
        precondition(enterLive as? String == "motion")
        try await waitForStudio(first,"motion")
        let enterSetup: Any = try await withCheckedThrowingContinuation { continuation in
            first.webView.callAsyncJavaScript("document.querySelector('[data-setup]').click();return document.getElementById('examine').dataset.studio",arguments:[:],in:nil,in:.page) { result in continuation.resume(with:result) }
        }
        precondition(enterSetup as? String == "setup")
        try await waitForStudio(first,"setup")
        let returnToLive: Any = try await withCheckedThrowingContinuation { continuation in
            first.webView.callAsyncJavaScript("document.querySelector('#setup-workspace [data-studio=\"motion\"]').click();return document.getElementById('examine').dataset.studio",arguments:[:],in:nil,in:.page) { result in continuation.resume(with:result) }
        }
        precondition(returnToLive as? String == "motion")
        try await waitForStudio(first,"motion")
        first.reloadInterface(); try await ready(first); try await waitForStudio(first,"motion")

        first.window!.orderOut(nil); owner.menu.item.button!.performClick(nil)
        precondition(first.window!.isVisible, "Clicking the status item must reopen a hidden dashboard")

        first.window!.close(); precondition(owner.dashboard == nil)
        owner.menu.item.button!.performClick(nil)
        let second = owner.dashboard!
        precondition(second !== first); try await ready(second)
        let setup = owner.menu.contextMenu.items.first { $0.representedObject as? String == "setup" }!
        NSApp.sendAction(setup.action!,to:setup.target,from:setup)
        try await Task.sleep(for:.milliseconds(250))
        let initialStudio = try await studio(second); precondition(initialStudio == "setup")
        var images: [Data] = []
        for phase in [TrackingPhase.tracking,.eyesClosed,.paused,.multipleFaces,.cameraDenied,.delayed,.calibrating] {
            owner.menu.update(phase)
            precondition(owner.menu.item.button!.isEnabled && !owner.menu.item.button!.appearsDisabled)
            precondition(owner.menu.item.button!.accessibilityLabel()!.contains(phase.title))
            images.append(owner.menu.item.button!.image!.tiffRepresentation!)
        }
        precondition(Set(images).count == images.count)
        owner.menu.update(.paused)
        let pausedImage = owner.menu.item.button!.image!
        owner.menu.blink(); precondition(owner.menu.item.button!.image === pausedImage)
        let motionStudio = try await selectStudio(second,"motion"); precondition(motionStudio == "motion")
        try await Task.sleep(for:.milliseconds(100))
        second.reloadInterface(); try await ready(second)
        try await waitForStudio(second,"motion")
        second.showSetup(); try await waitForStudio(second,"setup")
        second.refresh(); second.reloadInterface(); second.reloadInterface(); try await ready(second)
        let reloadedStudio = try await studio(second); precondition(reloadedStudio == "setup")
        second.webViewWebContentProcessDidTerminate(second.webView)
        precondition(!second.interfaceAvailable && second.window!.isVisible)
        try await ready(second)
        let recoveredStudio = try await studio(second); precondition(recoveredStudio == "setup")
        second.webViewWebContentProcessDidTerminate(second.webView)
        precondition(!second.interfaceAvailable && second.window!.isVisible)
        func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap { [$0]+descendants($0) } }
        let reload = descendants(second.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Reload window" }!
        precondition(!reload.isHidden)
        reload.performClick(nil); try await ready(second)
        let manuallyReloadedStudio = try await studio(second); precondition(manuallyReloadedStudio == "setup")

        fputs("Native controls, setup routing and WebKit recovery passed; checking strict native minimize behavior\n", stderr)
        let restoredWindow = second.window!
        guard let miniButton = restoredWindow.standardWindowButton(.miniaturizeButton) else {
            preconditionFailure("Dashboard miniaturize button was unavailable")
        }
        precondition(miniButton.isEnabled, "Dashboard miniaturize button should be enabled")
        miniButton.performClick(nil)
        try await waitFor { restoredWindow.isMiniaturized }
        precondition(restoredWindow.isMiniaturized, "Clicking the enabled native miniaturize button must minimize the dashboard")
        owner.menu.item.button!.performClick(nil)
        try await waitFor { restoredWindow.isVisible && !restoredWindow.isMiniaturized }
        precondition(restoredWindow.isVisible && !restoredWindow.isMiniaturized, "Clicking the status item must restore a minimized dashboard")
        restoredWindow.orderOut(nil); owner.menu.item.button!.performClick(nil)
        precondition(restoredWindow.isVisible, "Clicking the status item must reopen a hidden dashboard")
        second.window!.close()
        precondition(owner.applicationShouldTerminate(NSApp) == .terminateNow)
        owner.command(["action":"preview"])
        precondition(owner.snapshot()["fading"] as? Bool == false)
        precondition(owner.applicationShouldTerminate(NSApp) == .terminateLater)
    }
}

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
        let owner = ApplicationController(preferences:AppPreferences(defaults:defaults), statistics:DailyStatistics(url:temp.appendingPathComponent("stats.json")), resources:root.appendingPathComponent("BlinkMore/Resources/UI"))
        owner.installMenu()
        func ready(_ window: DashboardWindowController) async throws {
            for _ in 0..<100 {
                if window.interfaceAvailable { return }
                try await Task.sleep(for:.milliseconds(100))
            }
            preconditionFailure("Native window did not load its local interface")
        }
        owner.menu.item.button!.performClick(nil)
        let first = owner.dashboard!
        try await ready(first)
        precondition(first.window!.isVisible)
        precondition(first.window!.collectionBehavior.contains(.moveToActiveSpace))
        first.window!.miniaturize(nil)
        try await Task.sleep(for:.milliseconds(200))
        precondition(first.window!.isMiniaturized)
        owner.menu.item.button!.performClick(nil)
        precondition(first.window!.isVisible && !first.window!.isMiniaturized)
        first.window!.orderOut(nil); owner.menu.item.button!.performClick(nil)
        precondition(first.window!.isVisible)
        first.window!.close(); precondition(owner.dashboard == nil)
        owner.menu.item.button!.performClick(nil)
        let second = owner.dashboard!
        precondition(second !== first); try await ready(second)
        let setup = owner.menu.contextMenu.items.first { $0.representedObject as? String == "setup" }!
        NSApp.sendAction(setup.action!,to:setup.target,from:setup)
        try await Task.sleep(for:.milliseconds(250))
        let studio: Any = try await withCheckedThrowingContinuation { continuation in
            second.webView.callAsyncJavaScript("return document.getElementById('examine').dataset.studio",arguments:[:],in:nil,in:.page) { result in continuation.resume(with:result) }
        }
        precondition(studio as? String == "setup")
        var images: [Data] = []
        for phase in [TrackingPhase.tracking,.eyesClosed,.paused,.multipleFaces,.cameraDenied,.delayed,.calibrating] {
            owner.menu.update(phase)
            precondition(owner.menu.item.button!.isEnabled && !owner.menu.item.button!.appearsDisabled)
            precondition(owner.menu.item.button!.accessibilityLabel()!.contains(phase.title))
            images.append(owner.menu.item.button!.image!.tiffRepresentation!)
        }
        precondition(Set(images).count == images.count)
        second.refresh(); second.reloadInterface(); second.reloadInterface(); try await ready(second)
        second.webViewWebContentProcessDidTerminate(second.webView)
        precondition(!second.interfaceAvailable && second.window!.isVisible)
        try await ready(second)
        second.webViewWebContentProcessDidTerminate(second.webView)
        precondition(!second.interfaceAvailable && second.window!.isVisible)
        func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap { [$0]+descendants($0) } }
        let reload = descendants(second.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Reload window" }!
        precondition(!reload.isHidden)
        reload.performClick(nil); try await ready(second)
        second.window!.close()
    }
}

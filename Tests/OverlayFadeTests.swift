import AppKit

@main enum OverlayFadeTests {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let fade = OverlayFade()
            precondition(fade.windows.count == NSScreen.screens.count && !fade.windows.isEmpty)
            for (window, screen) in zip(fade.windows, NSScreen.screens) {
                precondition(window.frame == screen.frame && window.ignoresMouseEvents && !window.canBecomeKey)
                precondition(window.collectionBehavior.contains(.canJoinAllSpaces))
            }
            fade.setVisible(true, color: .black, intensity: 0.15, duration: 0)
            precondition(fade.isFaded && fade.windows.allSatisfy { $0.isVisible })
            try await Task.sleep(for: .milliseconds(120))
            precondition(fade.windows.allSatisfy { $0.alphaValue > 0.99 })
            fade.setVisible(false, color: .black, intensity: 0.15, duration: 0)
            precondition(!fade.isFaded && fade.windows.allSatisfy { !$0.isVisible })
            fade.setVisible(true, color: .black, intensity: 0.15, duration: 0.4)
            try await Task.sleep(for: .milliseconds(30))
            fade.setVisible(false, color: .black, intensity: 0.15, duration: 0)
            try await Task.sleep(for: .milliseconds(450))
            precondition(!fade.isFaded && fade.windows.allSatisfy { !$0.isVisible })
            fade.setVisible(true, color: .black, intensity: 0.15, duration: 0)
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            precondition(!fade.isFaded && fade.windows.allSatisfy { !$0.isVisible })
            fade.setVisible(true, color: .black, intensity: 0.15, duration: 0)
            fade.setVisible(false, color: .black, intensity: 0.15, duration: 0.07)
            fade.setVisible(true, color: .black, intensity: 0.15, duration: 0)
            try await Task.sleep(for: .milliseconds(150))
            precondition(fade.isFaded && fade.windows.allSatisfy { $0.isVisible && $0.alphaValue > 0.99 })
            fade.setVisible(false, color: .black, intensity: 0.15, duration: 0)
            print("Native overlay passed: screen geometry, all Spaces, click-through, fade/reversal, immediate lock cleanup, display rebuild")
            exit(0)
        }
        NSApp.run()
    }
}

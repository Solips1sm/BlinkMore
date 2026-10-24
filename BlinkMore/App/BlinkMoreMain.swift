import AppKit

@main
enum BlinkMoreMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = ApplicationController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}

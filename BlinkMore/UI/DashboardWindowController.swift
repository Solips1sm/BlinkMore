import AppKit
import WebKit

private final class DashboardRelay: NSObject, WKScriptMessageHandler {
    weak var owner: DashboardWindowController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

final class DashboardWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    private let webView: WKWebView
    private let resources: URL
    private let snapshot: () -> [String: Any]
    private let command: ([String: Any]) -> Void
    private var timer: Timer?
    private var ready = false
    private var updating = false
    private var selectedTab = 0
    var showsLive: Bool { selectedTab == 4 }
    var onClose: (() -> Void)?

    init(resources: URL? = nil, snapshot: @escaping () -> [String: Any], command: @escaping ([String: Any]) -> Void) {
        self.snapshot = snapshot; self.command = command
        self.resources = resources ?? Bundle.main.resourceURL!.appendingPathComponent("UI")
        let relay = DashboardRelay()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(relay, name: "blinkmore")
        webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Eyesight"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 520)
        window.contentView = webView; window.center()
        super.init(window: window)
        relay.owner = self; window.delegate = self; webView.navigationDelegate = self
        webView.loadFileURL(self.resources.appendingPathComponent("index.html"), allowingReadAccessTo: self.resources)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true, self.window?.isMiniaturized == false else { return }
            self.refresh()
        }
    }
    required init?(coder: NSCoder) { nil }

    func refresh() {
        guard ready, !updating else { return }
        updating = true
        webView.callAsyncJavaScript("window.blinkmore.update(state)", arguments: ["state": snapshot()], in: nil, in: .page) { [weak self] _ in self?.updating = false }
    }

    func selectTab(_ index: Int) {
        guard (0...4).contains(index) else { return }; selectedTab = index
        guard ready else { return }
        webView.callAsyncJavaScript("window.blinkmore.selectTab(tab)", arguments: ["tab": index], in: nil, in: .page, completionHandler: nil)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, allowed(url),
              let body = message.body as? [String: Any], let action = body["action"] as? String,
              action.count < 40 else { return }
        if action == "view" {
            if let index = body["tab"] as? Int, (0...4).contains(index) { selectedTab = index; refresh() }
            return
        }
        if action == "ready" { ready = true; selectTab(selectedTab) }
        command(body); refresh()
    }

    private func allowed(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.path == resources.appendingPathComponent("index.html").standardizedFileURL.path
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, allowed(url) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; selectTab(selectedTab); refresh() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showLoadError() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showLoadError() }
    private func showLoadError() {
        let label = NSTextField(wrappingLabelWithString: "The dashboard could not load. Reinstall this build to restore its interface files.")
        label.frame = NSRect(x: 32, y: 120, width: 640, height: 70)
        let view = NSView(frame: window?.contentView?.bounds ?? .zero); view.addSubview(label)
        window?.contentView = view
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "blinkmore")
        webView.navigationDelegate = nil; onClose?()
    }
    func takeSnapshot(completion: @escaping (NSImage?) -> Void) {
        webView.takeSnapshot(with: nil) { image, _ in completion(image) }
    }
}

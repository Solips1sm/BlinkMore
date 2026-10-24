import AppKit
import WebKit

private final class DashboardRelay: NSObject, WKScriptMessageHandler {
    weak var owner: DashboardWindowController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

final class DashboardWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private let resources: URL
    private let snapshot: () -> [String: Any]
    private let command: ([String: Any]) -> Void
    private var timer: Timer?
    private var ready = false
    private let host = NSView()
    private let fallback = NSVisualEffectView()
    private let loadingTitle = NSTextField(labelWithString: "Opening Eyesight")
    private let loadingDetail = NSTextField(wrappingLabelWithString: "Loading the interface on this Mac.")
    private let spinner = NSProgressIndicator()
    private let reloadButton = NSButton(title: "Reload window", target: nil, action: nil)
    private var loadTimeout: DispatchWorkItem?
    private var recoveries = 0
    private var pendingSetup = false
    private var pendingNavigation: WKNavigation?
    private var loadGeneration = 0
    private var updating = false
    private var selectedTab = 0
    var showsLive: Bool { selectedTab == 4 }
    var showsPractice: Bool { selectedTab == 1 }
    var showsProgress: Bool { selectedTab == 2 }
    var interfaceAvailable: Bool { ready && fallback.isHidden }
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
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = host
        if resources == nil {
            if !window.setFrameUsingName("EyesightDashboard") { window.center() }
            window.setFrameAutosaveName("EyesightDashboard")
        } else { window.center() }
        super.init(window: window)
        relay.owner = self; window.delegate = self; webView.navigationDelegate = self
        for view in [webView, fallback] {
            host.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor), view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        }
        fallback.material = .windowBackground; fallback.blendingMode = .withinWindow
        loadingTitle.font = .systemFont(ofSize: 18, weight: .regular)
        loadingDetail.font = .systemFont(ofSize: 14); loadingDetail.textColor = .secondaryLabelColor
        loadingDetail.alignment = .center
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        reloadButton.target = self; reloadButton.action = #selector(reloadInterface)
        reloadButton.bezelStyle = .rounded
        let stack = NSStackView(views: [spinner, loadingTitle, loadingDetail, reloadButton])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 12
        fallback.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: fallback.centerXAnchor), stack.centerYAnchor.constraint(equalTo: fallback.centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualTo: fallback.widthAnchor, constant: -80), loadingDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 460)])
        reloadInterface()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true, self.window?.isMiniaturized == false else { return }
            self.refresh()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        refresh()
    }

    func showSetup() {
        pendingSetup = true; selectTab(4)
        if ready { openSetup() }
    }

    private func openSetup() {
        pendingSetup = false
        webView.callAsyncJavaScript("window.blinkmore.showSetup()", arguments: [:], in: nil, in: .page, completionHandler: nil)
    }

    @objc func reloadInterface() {
        loadTimeout?.cancel(); loadGeneration += 1; ready = false; updating = false
        loadingTitle.stringValue = "Opening Eyesight"
        loadingDetail.stringValue = "Loading the interface on this Mac."
        fallback.isHidden = false; webView.isHidden = true; reloadButton.isHidden = true
        spinner.startAnimation(nil)
        pendingNavigation = webView.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
        let timeout = DispatchWorkItem { [weak self] in if self?.ready == false { self?.showLoadError() } }
        loadTimeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    func refresh() {
        guard ready, !updating else { return }
        updating = true
        let generation = loadGeneration
        webView.callAsyncJavaScript("window.blinkmore.update(state)", arguments: ["state": snapshot()], in: nil, in: .page) { [weak self] result in
            guard self?.loadGeneration == generation else { return }
            self?.updating = false
            if case .failure(let error) = result {
                NSLog("Eyesight interface update failed: %@", error.localizedDescription)
                self?.showLoadError()
            }
        }
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
        if action == "ready" {
            ready = true; loadTimeout?.cancel(); spinner.stopAnimation(nil)
            fallback.isHidden = true; webView.isHidden = false
            selectTab(selectedTab)
            if pendingSetup { openSetup() }
        }
        command(body); refresh()
    }

    private func allowed(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.path == resources.appendingPathComponent("index.html").standardizedFileURL.path
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, allowed(url) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard recoveries == 0 else { showLoadError(); return }
        recoveries += 1; reloadInterface()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if navigation === pendingNavigation { showLoadError() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if navigation === pendingNavigation { showLoadError() } }
    private func showLoadError() {
        ready = false; updating = false; loadTimeout?.cancel(); spinner.stopAnimation(nil)
        loadingTitle.stringValue = "The interface needs a reload"
        loadingDetail.stringValue = "Your camera and reminders run separately. Reload this window to restore its controls."
        fallback.isHidden = false; webView.isHidden = true; reloadButton.isHidden = false
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); loadTimeout?.cancel(); webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "blinkmore")
        webView.navigationDelegate = nil; onClose?()
    }
    func takeSnapshot(completion: @escaping (NSImage?) -> Void) {
        webView.takeSnapshot(with: nil) { image, _ in completion(image) }
    }
}

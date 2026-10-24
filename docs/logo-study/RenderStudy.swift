import AppKit
import WebKit

@main enum RenderStudy {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await render(); exit(0) }
            catch { fputs("Logo render failed: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }
    @MainActor static func render() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let jobs = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "render-jobs.json"))) as! [[String: Any]]
        for job in jobs {
            let width = (job["width"] as! NSNumber).doubleValue, height = (job["height"] as! NSNumber).doubleValue
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view; window.orderBack(nil)
            view.loadFileURL(root.appendingPathComponent(job["file"] as! String), allowingReadAccessTo: root)
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(100))
                if !view.isLoading { break }
            }
            func evaluate(_ source: String) async throws -> Any? {
                try await withCheckedThrowingContinuation { continuation in
                    view.callAsyncJavaScript(source, arguments: [:], in: nil, in: .page) { result in continuation.resume(with: result.map { Optional($0) }) }
                }
            }
            let expectedCards = job["cards"] as? Int ?? 15
            let loaded = try await evaluate("await document.fonts.ready; return [...document.fonts].every(f=>f.status==='loaded') && document.querySelectorAll('.card').length===\(expectedCards)")
            precondition(loaded as? Bool == true)
            if job["galleryCheck"] as? Bool == true {
                let interactions = try await evaluate("""
                const families=()=>[...document.querySelectorAll('.family')].filter(f=>!f.hidden);
                const initial=families().length===5 && families()[0].id==='family-01';
                document.querySelector('[data-filter="2"]').click();
                const last=families().length===5 && families()[0].id==='family-11';
                document.querySelector('[data-filter="all"]').click();
                const all=families().length===15;
                document.getElementById('theme').click();
                const dark=document.body.classList.contains('dark');
                document.querySelector('[data-filter="0"]').click();
                return initial && last && all && dark && document.querySelectorAll('.analysis a[download]').length===45;
                """)
                precondition(interactions as? Bool == true)
            }
            let heightCheck = job["allowVerticalScroll"] as? Bool == true ? "true" : "document.documentElement.scrollHeight<=innerHeight"
            let fits = try await evaluate("return document.documentElement.scrollWidth<=innerWidth && \(heightCheck)")
            precondition(fits as? Bool == true, "Contact sheet overflows: \(job)")
            try await Task.sleep(for: .milliseconds(150))
            let picture = try await view.takeSnapshot(configuration: nil)
            guard let data = picture.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: root.appendingPathComponent(job["output"] as! String))
            print(job["output"]!); fflush(stdout)
            window.orderOut(nil); view.stopLoading()
        }
    }
}

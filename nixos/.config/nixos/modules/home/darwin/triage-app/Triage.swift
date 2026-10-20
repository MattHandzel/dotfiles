// Triage.app: a native window for the message-triage server on 127.0.0.1:8771
// (~/Obsidian/Main/scripts/message-triage). Built at activation by
// message-triage.nix into ~/Applications/Triage.app, where Raycast and
// Spotlight find it. Replaces the Chrome --app window (2026-10-06): a real app
// has its own bundle id for AeroSpace, no Chrome ⌘N/⌘T/⌘W tab chrome, and can
// tell the page when it is brought forward.
//
// The page (ui.html) owns all the behaviour. This shell only:
//   * calls window.triageActivated() whenever the app becomes active, so the
//     page hides raw Beeper and drops a stale visit back to the launcher;
//   * turns the close button / ⌘W into window.triageClose() ("back to work":
//     end the visit, return to the previous AeroSpace workspace) instead of
//     destroying the window and its state;
//   * opens every non-local link in the default browser (or Obsidian);
//   * shows a waiting page and retries while the server is down.
import AppKit
import WebKit

let home = URL(string: "http://127.0.0.1:8771/")!

func isHome(_ u: URL) -> Bool {
    (u.host == "127.0.0.1" || u.host == "localhost") && u.port == 8771
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var retry: Timer?
    var offline = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.mainMenu = buildMenu()
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default() // localStorage (theme, zoom) survives restarts
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground") // no white flash in dark mode
        if #available(macOS 13.3, *) { web.isInspectable = true }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Triage"
        window.contentView = web
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 360)
        // The title bar takes the page's own background (ui.html --bg), so the window
        // reads as one surface instead of a grey strip over a dark page (2026-10-06 v3).
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x0e / 255.0, green: 0x0e / 255.0, blue: 0x11 / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xf7 / 255.0, green: 0xf7 / 255.0, blue: 0xf8 / 255.0, alpha: 1)
        }
        if !window.setFrameUsingName("Triage") { window.center() }
        window.setFrameAutosaveName("Triage")
        window.makeKeyAndOrderFront(nil)
        load()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: activation

    func applicationDidBecomeActive(_ n: Notification) {
        show()
        web.evaluateJavaScript("window.triageActivated && window.triageActivated()", completionHandler: nil)
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func show() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible || !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
    }

    // The close button and ⌘W mean "back to work", not "destroy the window".
    func windowShouldClose(_ s: NSWindow) -> Bool {
        web.evaluateJavaScript("typeof window.triageClose === 'function' ? (window.triageClose(), true) : false") { r, _ in
            if (r as? Bool) != true { NSApp.hide(nil) }
        }
        return false
    }

    // MARK: loading

    func load() {
        offline = false
        web.load(URLRequest(url: home, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10))
    }

    @objc func reload(_ sender: Any?) { retry?.invalidate(); load() }

    @objc func inspect(_ sender: Any?) {
        // No public API to open the inspector; the context menu's Inspect Element works too.
        web.perform(Selector(("_showWebInspector")))
    }

    func failed(_ e: Error) {
        let ns = e as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if !offline {
            offline = true
            web.loadHTMLString(offlinePage(ns.localizedDescription), baseURL: nil)
        }
        scheduleProbe()
    }

    func scheduleProbe() {
        retry?.invalidate()
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.probe() }
    }

    func probe() {
        var req = URLRequest(url: home.appendingPathComponent("api/state"), timeoutInterval: 3)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if (resp as? HTTPURLResponse)?.statusCode == 200 { self.load() } else { self.scheduleProbe() }
            }
        }.resume()
    }

    func offlinePage(_ why: String) -> String {
        let esc = why.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><meta charset=utf-8><title>Triage</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 14px/1.5 -apple-system, system-ui; margin: 0; height: 100vh; display: grid; place-items: center;
               background: Canvas; color: CanvasText; }
        div { max-width: 460px; padding: 16px; } p { color: GrayText; } code { font-size: 12px; }
        </style>
        <div><h2>Waiting for the triage server</h2>
        <p>Nothing is answering on 127.0.0.1:8771 (\(esc)). This page retries every 2 seconds.</p>
        <p>Restart it: <code>launchctl kickstart -k gui/$(id -u)/org.nix-community.home.message-triage</code><br>
        Log: <code>~/Library/Logs/message-triage.log</code></p></div>
        """
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) { failed(e) }
    func webView(_ w: WKWebView, didFail nav: WKNavigation!, withError e: Error) { failed(e) }
    func webViewWebContentProcessDidTerminate(_ w: WKWebView) { load() }

    // Local pages stay here; everything else goes to its own app.
    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = a.request.url else { return decisionHandler(.cancel) }
        if isHome(u) || u.scheme == "about" || u.scheme == "data" { return decisionHandler(.allow) }
        NSWorkspace.shared.open(u)
        decisionHandler(.cancel)
    }

    // target=_blank and window.open().
    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction,
                 windowFeatures f: WKWindowFeatures) -> WKWebView? {
        if let u = a.request.url { NSWorkspace.shared.open(u) }
        return nil
    }

    // <input type=file> (the composer's attach button). WKWebView shows no picker
    // unless the UI delegate opens one.
    func webView(_ w: WKWebView, runOpenPanelWith p: WKOpenPanelParameters, initiatedByFrame f: WKFrameInfo,
                 completionHandler done: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = p.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { r in done(r == .OK ? panel.urls : nil) }
    }

    // MARK: menu

    // Deliberately small. WKWebView offers every ⌘ key to the page first, but a
    // menu item would still claim any key the page lets through, and the page
    // uses Beeper's keys (⌘K ⌘J ⌘E ⌘L ⌘R ⌘T ⌘F ⌘P ⌘U ⌘[ ⌘] ...). So: no File
    // menu, no Find, and Reload sits on ⌥⌘R, not ⌘R (quote-and-reply).
    func buildMenu() -> NSMenu {
        let bar = NSMenu()
        func sub(_ title: String, _ items: [NSMenuItem]) {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            top.submenu = m
            bar.addItem(top)
        }
        func item(_ t: String, _ a: Selector?, _ k: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            return i
        }
        let reload = item("Reload", #selector(reload(_:)), "r", [.command, .option])
        reload.target = self
        let insp = item("Web Inspector", #selector(inspect(_:)), "i", [.command, .option])
        insp.target = self
        sub("Triage", [
            item("About Triage", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Hide Triage", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            item("Quit Triage", #selector(NSApplication.terminate(_:)), "q"),
        ])
        sub("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        sub("View", [reload, insp])
        sub("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return bar
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

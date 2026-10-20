// Work Test.app: a native window for the work-test server on 127.0.0.1:8772
// (~/Obsidian/Main/scripts/work-test). Built at activation by work-test.nix
// into ~/Applications/Work Test.app, where Raycast and Spotlight find it.
// Matt asked for it on 2026-10-06: "make this an actual application, or ...
// a script ... that I can run with Raycast that opens it up".
//
// The page (app.html) owns all the behaviour. This shell only:
//   * passes the page's budget notifications to macOS (WKWebView has no web
//     Notification API) and bounces the Dock icon when the app is in back;
//   * lets the chime play without a click first;
//   * hides the window on close / ⌘W instead of destroying it;
//   * mirrors the page title (the running clock) into the window title;
//   * opens worktest://open?date=2026-10-06#t5 as that day and task
//     (`worktest.py open` uses it);
//   * opens every non-local link in the default browser (or Obsidian);
//   * shows a waiting page and retries while the server is down.
import AppKit
import UserNotifications
import WebKit

let port = 8772
let home = URL(string: "http://127.0.0.1:\(port)/")!

func isHome(_ u: URL) -> Bool {
    (u.host == "127.0.0.1" || u.host == "localhost") && u.port == port
}

// worktest://open?date=…#t5 -> http://127.0.0.1:8772/?date=…#t5
func pageURL(_ u: URL) -> URL {
    guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return home }
    c.scheme = "http"; c.host = "127.0.0.1"; c.port = port; c.path = "/"
    return c.url ?? home
}

// The page calls `new Notification(title, {body})` at a budget. Same shape, sent to Swift. wtApp tells the page
// this build also takes {activate: pid}.
let notificationShim = """
(() => {
  const post = m => { try { window.webkit.messageHandlers.wt.postMessage(m); } catch (e) {} };
  class WTNotification {
    constructor(title, opts) { post({ title: String(title), body: String((opts && opts.body) || '') }); }
    close() {}
  }
  WTNotification.permission = 'granted';
  WTNotification.requestPermission = () => Promise.resolve('granted');
  window.Notification = WTNotification;
  window.wtApp = { activate: true }; // the page may send {activate: pid}
})();
"""

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var retry: Timer?
    var offline = false
    var target = home // where the next load goes (a worktest:// URL can change it)
    var titleObs: NSKeyValueObservation?
    var asked = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.mainMenu = buildMenu()
        UNUserNotificationCenter.current().delegate = self
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default() // localStorage (open parts, theme) survives restarts
        cfg.mediaTypesRequiringUserActionForPlayback = [] // the budget chime
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        cfg.userContentController.addUserScript(
            WKUserScript(source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(self, name: "wt")
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground") // no white flash in dark mode
        if #available(macOS 13.3, *) { web.isInspectable = true }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Work Test"
        window.contentView = web
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 360)
        // The title bar takes the page's own background (app.html --page, Catppuccin Latte/Mocha).
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x1b / 255.0, alpha: 1)
                : NSColor(srgbRed: 0xe6 / 255.0, green: 0xe9 / 255.0, blue: 0xef / 255.0, alpha: 1)
        }
        if !window.setFrameUsingName("WorkTest") { window.center() }
        window.setFrameAutosaveName("WorkTest")
        titleObs = web.observe(\.title, options: [.new]) { [weak self] w, _ in
            guard let self, !self.offline, let t = w.title, !t.isEmpty else { return }
            self.window.title = t
        }
        window.makeKeyAndOrderFront(nil)
        load()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: activation and URLs

    func application(_ a: NSApplication, open urls: [URL]) {
        guard let u = urls.last, u.scheme == "worktest" else { return }
        target = pageURL(u)
        show()
        NSApp.activate(ignoringOtherApps: true)
        if web != nil { load() }
    }

    func applicationDidBecomeActive(_ n: Notification) {
        show()
        NSApp.dockTile.badgeLabel = nil
        web.evaluateJavaScript("window.dispatchEvent(new Event('focus'))", completionHandler: nil) // re-read the sheet
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func show() {
        guard window != nil else { return }
        if NSApp.isHidden { NSApp.unhide(nil) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible || !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
    }

    // Close and ⌘W hide the window. The clocks live in the server, so nothing is lost either way.
    func windowShouldClose(_ s: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }

    // MARK: messages from the page

    // {title, body}: a notification (the shim above). {activate: pid}: raise that app, which is the kitty window
    // holding the sheet's nvim when "Neovim" jumps an nvim that's already open.
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any] else { return }
        if let pid = d["activate"] as? Int { return activate(pid_t(pid)) }
        notify(d["title"] as? String ?? "Work Test", d["body"] as? String ?? "")
    }

    func activate(_ pid: pid_t) {
        guard let other = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: other) // macOS 14+ only lets the active app hand over focus
            other.activate()
        } else {
            other.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func notify(_ title: String, _ body: String) {
        if !NSApp.isActive {
            NSApp.requestUserAttention(.criticalRequest)
            NSApp.dockTile.badgeLabel = "!"
        }
        let center = UNUserNotificationCenter.current()
        let send = {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
        if asked { return send() }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            self?.asked = true
            send()
        }
    }

    // Show the banner even while the app is in front.
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        DispatchQueue.main.async { self.show(); NSApp.activate(ignoringOtherApps: true) }
        done()
    }

    // MARK: loading

    func load() {
        offline = false
        web.load(URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10))
    }

    @objc func reload(_ sender: Any?) {
        retry?.invalidate()
        if !offline, let u = web.url, isHome(u) { target = u }
        load()
    }

    @objc func inspect(_ sender: Any?) {
        // No public API to open the inspector; the context menu's Inspect Element works too.
        web.perform(Selector(("_showWebInspector")))
    }

    @objc func openInNvim(_ sender: Any?) {
        web.evaluateJavaScript("window.wtOpenNvim && window.wtOpenNvim()", completionHandler: nil)
    }

    @objc func openInBrowser(_ sender: Any?) {
        NSWorkspace.shared.open(!offline ? (web.url ?? target) : target)
    }

    func failed(_ e: Error) {
        let ns = e as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // frame load interrupted by a policy change
        if !offline {
            offline = true
            window.title = "Work Test"
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
                // Any HTTP answer means the server is up (/api/state is 404 on a day with no sheet).
                if resp is HTTPURLResponse { self.load() } else { self.scheduleProbe() }
            }
        }.resume()
    }

    func offlinePage(_ why: String) -> String {
        let esc = why.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><meta charset=utf-8><title>Work Test</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 14px/1.5 -apple-system, system-ui; margin: 0; height: 100vh; display: grid; place-items: center;
               background: Canvas; color: CanvasText; }
        div { max-width: 480px; padding: 16px; } p { color: GrayText; } code { font-size: 12px; }
        </style>
        <div><h2>Waiting for the work-test server</h2>
        <p>Nothing is answering on 127.0.0.1:\(port) (\(esc)). This page retries every 2 seconds.</p>
        <p>Restart it: <code>launchctl kickstart -k gui/$(id -u)/org.nix-community.home.work-test</code><br>
        Log: <code>~/Library/Logs/work-test.log</code></p></div>
        """
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError e: Error) { failed(e) }
    func webView(_ w: WKWebView, didFail nav: WKNavigation!, withError e: Error) { failed(e) }
    func webViewWebContentProcessDidTerminate(_ w: WKWebView) { load() }

    // Local pages stay here; everything else (Google Calendar, the Doc, obsidian://) goes to its own app.
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

    // MARK: menu

    // The page's keys are Space, D, Esc and E, so ⌘ shortcuts are free for the usual menu items.
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
        let reload = item("Reload", #selector(reload(_:)), "r")
        reload.target = self
        let browser = item("Open in Browser", #selector(openInBrowser(_:)), "o", [.command, .shift])
        browser.target = self
        let insp = item("Web Inspector", #selector(inspect(_:)), "i", [.command, .option])
        insp.target = self
        let nvim = item("Open in Neovim", #selector(openInNvim(_:)), "e")
        nvim.target = self
        sub("Work Test", [
            item("About Work Test", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Hide Work Test", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator(),
            item("Quit Work Test", #selector(NSApplication.terminate(_:)), "q"),
        ])
        sub("File", [nvim, browser])
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

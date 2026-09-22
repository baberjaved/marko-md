// Marko.app — a lightweight native macOS wrapper around the Marko Markdown viewer.
// Single AppKit window hosting a WKWebView that loads viewer/marko.html from the bundle.
// Opens .md files by double-click, drag-onto-icon, File ▸ Open, or `open -a Marko file.md`,
// and reloads the document when the file changes on disk.
// Build with app/mac/build.sh (Xcode Command Line Tools are enough).

import Cocoa
import WebKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    private var pageReady = false
    private var pendingURLs: [URL] = []
    private(set) var currentURL: URL?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var reloadTimer: Timer?
    private let recentsKey = "marko.recents"
    private let prefsKey = "marko.prefs"

    // MARK: - Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "marko")
        // Mark the page as hosted by the Mac app before any of its scripts run.
        config.userContentController.addUserScript(WKUserScript(source: "document.documentElement.dataset.app='mac';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Seed the viewer's preferences (mode, sidebars, text size, checkbox ticks) from UserDefaults so they survive even if
        // WebKit's storage for file:// pages is cleared.
        if let saved = UserDefaults.standard.string(forKey: prefsKey), !saved.isEmpty {
            config.userContentController.addUserScript(WKUserScript(source: "window.__markoPrefs = \(saved);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsMagnification = true
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .windowBackgroundColor }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Marko"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.setFrameAutosaveName("MarkoMainWindow")
        if window.frame.width < 480 { window.center() }
        applyWindowBackground()
        window.makeKeyAndOrderFront(nil)

        buildMenu()

        guard let page = Bundle.main.url(forResource: "marko", withExtension: "html", subdirectory: "viewer") else {
            fatalError("viewer/marko.html is missing from the app bundle")
        }
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        NSApp.activate(ignoringOtherApps: true)

        // `Marko --set-default` (used by build.sh --install --default): set the association and quit.
        if CommandLine.arguments.contains("--set-default") {
            setAsDefaultMarkdownApp(interactive: false) { _ in NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(url) }
    }

    private func applyWindowBackground() {
        let dark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        window.backgroundColor = dark ? NSColor(srgbRed: 0.122, green: 0.122, blue: 0.129, alpha: 1) : NSColor(srgbRed: 0.976, green: 0.976, blue: 0.984, alpha: 1)
    }

    // MARK: - Opening documents

    func open(_ url: URL) {
        guard pageReady else { pendingURLs.append(url); return }
        let path = url.path
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            let alert = NSAlert()
            alert.messageText = "Couldn't open \(url.lastPathComponent)"
            alert.informativeText = "The file could not be read as text."
            alert.runModal()
            return
        }
        let firstOpen = currentURL != url
        currentURL = url
        send(text: text, name: url.lastPathComponent, keepMode: !firstOpen)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        window.representedURL = url
        addRecent(url)
        if firstOpen { watch(url) }
    }

    private func send(text: String, name: String, keepMode: Bool) {
        // Pass the document through JSON so any content is safe inside the script string.
        guard let json = try? JSONSerialization.data(withJSONObject: [text, name, keepMode], options: []),
              let args = String(data: json, encoding: .utf8) else { return }
        let js = """
        (function (a) {
          if (!window.marko) return;
          var keep = a[2] && window.marko.mode();
          var y = document.getElementById('canvas').scrollTop;
          window.marko.open(a[0], a[1], keep || null);
          if (a[2]) { var c = document.getElementById('canvas'); c.style.scrollBehavior = 'auto'; c.scrollTop = y; c.style.scrollBehavior = ''; }
        })(\(args));
        """
        web.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Live reload (watches the directory so editors that save-by-rename are still caught)

    private func watch(_ url: URL) {
        stopWatching()
        let dir = url.deletingLastPathComponent().path
        watchedFD = Darwin.open(dir, O_EVTONLY)
        guard watchedFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchedFD, eventMask: [.write, .rename, .delete, .attrib, .extend], queue: .main)
        var lastModified = modificationDate(url)
        source.setEventHandler { [weak self] in
            guard let self = self, let current = self.currentURL else { return }
            let now = self.modificationDate(current)
            if now != lastModified {
                lastModified = now
                self.reloadTimer?.invalidate()
                self.reloadTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in self.reloadCurrent() }
            }
        }
        source.setCancelHandler { [fd = watchedFD] in _ = Darwin.close(fd) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedFD = -1
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    @objc func reloadCurrent() {
        guard let url = currentURL, let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else { return }
        send(text: text, name: url.lastPathComponent, keepMode: true)
        web.evaluateJavaScript("(function(){var t=document.getElementById('toast');if(!t)return;t.textContent='Updated from disk';t.classList.add('show');setTimeout(function(){t.classList.remove('show')},1800);})();", completionHandler: nil)
    }

    // MARK: - Recents

    private func recents() -> [String] { UserDefaults.standard.stringArray(forKey: recentsKey) ?? [] }

    private func addRecent(_ url: URL) {
        var list = recents().filter { $0 != url.path }
        list.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: recentsKey)
        rebuildRecentMenu()
    }

    // MARK: - Menu

    private var recentMenu = NSMenu(title: "Open Recent")

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Marko", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Make Default for Markdown Files", action: #selector(makeDefaultMenu(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Marko", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Marko", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Reload", action: #selector(reloadCurrent), keyEquivalent: "r")
        fileMenu.addItem(withTitle: "Reveal in Finder", action: #selector(revealInFinder(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Copy Updated Markdown", action: #selector(copyUpdatedMarkdown(_:)), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(focusSearch(_:)), keyEquivalent: "f")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        for (title, key, tag) in [("Reading", "1", 0), ("Plan", "2", 1), ("Interactive", "3", 2)] {
            let item = viewMenu.addItem(withTitle: title, action: #selector(setMode(_:)), keyEquivalent: key)
            item.tag = tag
        }
        viewMenu.addItem(.separator())
        let outline = viewMenu.addItem(withTitle: "Toggle Outline", action: #selector(toggleOutline(_:)), keyEquivalent: "1")
        outline.keyEquivalentModifierMask = [.command, .option]
        let panel = viewMenu.addItem(withTitle: "Toggle Panel", action: #selector(togglePanel(_:)), keyEquivalent: "2")
        panel.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(zoomReset(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = viewMenu

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Marko Guide", action: #selector(openGuide(_:)), keyEquivalent: "?")
        helpMenu.addItem(withTitle: "Marko on GitHub", action: #selector(openGitHub(_:)), keyEquivalent: "")
        helpItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let list = recents()
        for path in list {
            let item = NSMenuItem(title: (path as NSString).lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = path
            item.toolTip = path
            recentMenu.addItem(item)
        }
        if !list.isEmpty {
            recentMenu.addItem(.separator())
            recentMenu.addItem(withTitle: "Clear Menu", action: #selector(clearRecents(_:)), keyEquivalent: "")
        }
    }

    // MARK: - Actions

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.open(url) }
        }
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        open(URL(fileURLWithPath: path))
    }

    @objc func clearRecents(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: recentsKey)
        rebuildRecentMenu()
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard let url = currentURL else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func copyUpdatedMarkdown(_ sender: Any?) {
        web.evaluateJavaScript("window.marko ? window.marko.updatedMarkdown() : ''") { result, _ in
            guard let text = result as? String, !text.isEmpty else { NSSound.beep(); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    @objc func setMode(_ sender: NSMenuItem) {
        let modes = ["reading", "plan", "interactive"]
        web.evaluateJavaScript("window.marko && window.marko.setMode('\(modes[sender.tag])')", completionHandler: nil)
    }

    @objc func toggleOutline(_ sender: Any?) { web.evaluateJavaScript("window.marko && window.marko.togglePanel('outline')", completionHandler: nil) }
    @objc func togglePanel(_ sender: Any?) { web.evaluateJavaScript("window.marko && window.marko.togglePanel('inspector')", completionHandler: nil) }
    @objc func focusSearch(_ sender: Any?) { web.evaluateJavaScript("window.marko && window.marko.search()", completionHandler: nil) }
    @objc func zoomIn(_ sender: Any?) { web.pageZoom = min(2.0, web.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { web.pageZoom = max(0.6, web.pageZoom - 0.1) }
    @objc func zoomReset(_ sender: Any?) { web.pageZoom = 1.0 }

    @objc func openGuide(_ sender: Any?) {
        if let guide = Bundle.main.url(forResource: "guide", withExtension: "md") { open(guide) }
        else { NSWorkspace.shared.open(URL(string: "https://github.com/baberjaved/marko-md/blob/main/docs/guide.md")!) }
    }
    @objc func openGitHub(_ sender: Any?) { NSWorkspace.shared.open(URL(string: "https://github.com/baberjaved/marko-md")!) }

    // MARK: - WebKit delegates

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        let queued = pendingURLs
        pendingURLs = []
        queued.forEach(open)
        offerDefaultOnFirstLaunch()
    }

    // MARK: - Default app for Markdown

    private var markdownTypes: [UTType] {
        var types: [UTType] = []
        for id in ["net.daringfireball.markdown", "public.markdown"] { if let t = UTType(id) { types.append(t) } }
        for ext in ["md", "markdown", "mdown", "mdx"] { if let t = UTType(filenameExtension: ext) { types.append(t) } }
        var seen = Set<String>()
        return types.filter { seen.insert($0.identifier).inserted }
    }

    private func offerDefaultOnFirstLaunch() {
        let key = "marko.askedDefault"
        guard !UserDefaults.standard.bool(forKey: key), !CommandLine.arguments.contains("--set-default") else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "Make Marko the default app for Markdown files?"
        alert.informativeText = "Double-clicking .md and .markdown files in Finder will open them in Marko. You can change this later from Marko's menu or a file's Get Info panel."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.setAsDefaultMarkdownApp(interactive: true, completion: nil) }
        }
    }

    @objc func makeDefaultMenu(_ sender: Any?) { setAsDefaultMarkdownApp(interactive: true, completion: nil) }

    func setAsDefaultMarkdownApp(interactive: Bool, completion: ((Bool) -> Void)?) {
        let appURL = Bundle.main.bundleURL
        let group = DispatchGroup()
        let lock = NSLock()
        var failures: [String] = []
        for type in markdownTypes {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
                if let error = error { lock.lock(); failures.append("\(type.identifier): \(error.localizedDescription)"); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            let ok = failures.isEmpty
            if interactive, let self = self {
                let alert = NSAlert()
                alert.messageText = ok ? "Marko is now the default app for Markdown files." : "Couldn't set Marko as the default for every Markdown type."
                alert.informativeText = ok ? "Double-click any .md file to open it here." : failures.joined(separator: "\n") + "\n\nYou can also set it from Finder: select a .md file, File ▸ Get Info ▸ Open with ▸ Marko ▸ Change All."
                alert.beginSheetModal(for: self.window, completionHandler: nil)
            }
            completion?(ok)
        }
    }

    // Links to other sites open in the default browser; the viewer itself stays in the app.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, action.navigationType == .linkActivated, !url.isFileURL {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame == nil, let url = action.request.url { NSWorkspace.shared.open(url); decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    // The page's own "Open File…" (an <input type=file>) uses the standard panel.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "title":
            let title = (body["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            window.title = title.isEmpty ? "Marko" : title
            if let url = currentURL { window.representedURL = url }
        case "prefs":
            if let json = body["data"] as? String, json.count < 512_000 { UserDefaults.standard.set(json, forKey: prefsKey) }
        default:
            break
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

import SwiftUI
import ServiceManagement
import Combine

@main
struct LyricBarApp: App {
    @StateObject private var ticker: LyricTicker

    init() {
        let ticker = LyricTicker()
        _ticker = StateObject(wrappedValue: ticker)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ticker.checkAutomationAccess()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            ticker.startMonitoringNowPlaying()
        }
    }

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra {
            Text(ticker.nowPlayingTitle.isEmpty ? "LyricBar" : "\(ticker.nowPlayingArtist) - \(ticker.nowPlayingTitle)")
                .font(.headline)
            Divider()
            Button(ticker.musicAccessOK ? "Music Access ✓" : "Request Music Access") {
                ticker.requestAutomationAccess(app: .music)
            }
            Button(ticker.spotifyAccessOK ? "Spotify Access ✓" : "Request Spotify Access") {
                ticker.requestAutomationAccess(app: .spotify)
            }
            Divider()
            Button(action: { ticker.previousTrack() }) {
                Label("Previous", systemImage: "backward.fill")
            }
            Button(action: { ticker.togglePlayPause() }) {
                Label(ticker.isPlaying ? "Pause" : "Play", systemImage: ticker.isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: { ticker.nextTrack() }) {
                Label("Next", systemImage: "forward.fill")
            }
            Divider()
            Button("Show Full Lyrics") { LyricBarWindows.shared.showLyrics(ticker: ticker) }
            Button("Clear Lyrics Cache") { ticker.clearCache() }
            Divider()
            Toggle(isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        NSLog("LyricBar: launch at login failed: \(error)")
                    }
                }
            )) {
                Text("Launch at Login")
            }
            Divider()
            Button("About LyricBar") { LyricBarWindows.shared.showAbout() }
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            if ticker.nowPlayingTitle.isEmpty || ticker.current == "LyricBar" {
                Text("LyricBar")
            } else {
                Text(ticker.menuBarTitle)
            }
        }
        #endif
    }
}

// MARK: - Window Manager
final class LyricBarWindows: NSObject, NSWindowDelegate {
    static let shared = LyricBarWindows()

    private var lyricsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    func showLyrics(ticker: LyricTicker) {
        if let win = lyricsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let lyricsVC = LyricsViewController(ticker: ticker)
        let win = NSWindow(contentViewController: lyricsVC)
        win.title = "Lyrics"
        win.styleMask = [.titled, .closable, .resizable]
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 320, height: 500))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lyricsWindow = win
    }

    func showAbout() {
        if let win = aboutWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutVC = AboutViewController()
        let win = NSWindow(contentViewController: aboutVC)
        win.title = "About LyricBar"
        win.styleMask = [.titled, .closable]
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.setContentSize(NSSize(width: 260, height: 250))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow = win
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == lyricsWindow {
            lyricsWindow = nil
        }
        if notification.object as? NSWindow == aboutWindow {
            aboutWindow = nil
        }
    }
}

// MARK: - Lyrics View Controller
final class LyricsViewController: NSViewController {
    private let ticker: LyricTicker
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private var observer: AnyCancellable?

    init(ticker: LyricTicker) {
        self.ticker = ticker
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.width, .height]
        view.addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.font = NSFont.systemFont(ofSize: 13)
        scrollView.documentView = textView

        renderLyrics()

        observer = ticker.$current.sink { [weak self] _ in
            self?.renderLyrics()
        }
    }

    private func renderLyrics() {
        let lines = ticker.lyricLines
        guard !lines.isEmpty else {
            textView.string = "No lyrics loaded"
            return
        }

        let currentLine = ticker.current
        let attrStr = NSMutableAttributedString()

        for (i, line) in lines.enumerated() {
            let isCurrent = line.text == currentLine
            let attrs: [NSAttributedString.Key: Any] = [
                .font: isCurrent ? NSFont.boldSystemFont(ofSize: 14) : NSFont.systemFont(ofSize: 13),
                .foregroundColor: isCurrent ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
            attrStr.append(NSAttributedString(string: line.text, attributes: attrs))
            if i < lines.count - 1 {
                attrStr.append(NSAttributedString(string: "\n"))
            }
        }

        textView.textStorage?.setAttributedString(attrStr)

        // Scroll to current line
        if let idx = lines.firstIndex(where: { $0.text == currentLine }) {
            let lineHeight: CGFloat = 20
            let y = CGFloat(idx) * lineHeight - scrollView.contentView.bounds.height / 2
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
        }
    }
}

// MARK: - About View Controller
final class AboutViewController: NSViewController {
    override func loadView() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 240))

        let icon = NSImageView(image: NSImage(named: "AppLogo") ?? NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 16
        icon.layer?.masksToBounds = true
        icon.frame = NSRect(x: 90, y: 152, width: 80, height: 80)
        contentView.addSubview(icon)

        let title = NSTextField(labelWithString: "LyricBar")
        title.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 118, width: 260, height: 24)
        contentView.addSubview(title)

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let version = NSTextField(labelWithString: "Version \(appVersion)")
        version.font = NSFont.systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        version.frame = NSRect(x: 0, y: 102, width: 260, height: 16)
        contentView.addSubview(version)

        let desc = NSTextField(labelWithString: "Synced lyrics in your menu bar.\nWorks with Apple Music & Spotify.")
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.alignment = .center
        desc.frame = NSRect(x: 20, y: 44, width: 220, height: 50)
        contentView.addSubview(desc)

        view = contentView
    }
}

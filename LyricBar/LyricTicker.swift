import Foundation
import Combine
import AppKit
import CryptoKit
import UniformTypeIdentifiers

// MARK: - LRC Models & Parser
struct LRCLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum LRCParser {
    private static let regex = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]"#, options: [])

    static func parse(_ string: String) -> [LRCLine] {
        let lines = string.components(separatedBy: .newlines)

        var results: [LRCLine] = []

        for raw in lines {
            let nsLine = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsLine.length))

            // Remove timestamps to get the lyric text
            let text = regex.stringByReplacingMatches(in: raw, options: [], range: NSRange(location: 0, length: nsLine.length), withTemplate: "").trimmingCharacters(in: .whitespaces)

            for m in matches {
                guard m.numberOfRanges >= 3 else { continue }
                let mm = Double(nsLine.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(nsLine.substring(with: m.range(at: 2))) ?? 0

                var frac: Double = 0
                if m.numberOfRanges >= 4, m.range(at: 3).location != NSNotFound {
                    let fractionStr = nsLine.substring(with: m.range(at: 3))
                    if let fraction = Double(fractionStr) {
                        if fractionStr.count == 3 {
                            frac = fraction / 1000.0
                        } else {
                            frac = fraction / 100.0
                        }
                    }
                }

                let total = mm * 60 + ss + frac
                if !text.isEmpty {
                    results.append(LRCLine(time: total, text: text))
                }
            }
        }

        return results.sorted { $0.time < $1.time }
    }
}

// MARK: - LRCLIB Fetcher
struct LRCLibResult: Decodable {
    let trackName: String?
    let artistName: String?
    let syncedLyrics: String?
}

enum LyricsSourceError: Error { case notFound }

final class LyricsSource {
    func fetchSyncedLyrics(track: String, artist: String) async throws -> String {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        var queryItems: [URLQueryItem] = [
            .init(name: "track_name", value: track)
        ]
        if !artist.isEmpty {
            queryItems.append(.init(name: "artist_name", value: artist))
        }
        comps.queryItems = queryItems
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let results = try JSONDecoder().decode([LRCLibResult].self, from: data)
        if let lrc = results.first(where: { ($0.syncedLyrics ?? "").isEmpty == false })?.syncedLyrics {
            return lrc
        }
        throw LyricsSourceError.notFound
    }
}

// MARK: - Now Playing via AppleScript
struct NowPlayingInfo {
    let title: String
    let artist: String
    var position: TimeInterval
    var duration: TimeInterval = 0
    var playbackRate: Double = 0
    var isPlaying: Bool { playbackRate > 0 }
}

nonisolated private func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let out = script.executeAndReturnError(&error)
    if let error {
        if let code = error[NSAppleScript.errorNumber] as? Int, code == -1743 {
            // Not authorized — silent, handled by caller cooldown
        } else {
            NSLog("LyricBar: AppleScript error: \(error)")
        }
        return nil
    }
    return out.stringValue
}

nonisolated func nowPlayingFromAppleMusic() -> NowPlayingInfo? {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil else {
        return nil
    }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first != nil else {
        return nil
    }
    let script = """
    with timeout of 2 seconds
        if application "Music" is running then
            tell application "Music"
                if player state is playing and exists current track then
                    set t to name of current track
                    set a to artist of current track
                    set p to player position
                    return t & "||" & a & "||" & (p as string)
                end if
            end tell
        end if
    end timeout
    """
    guard let result = runAppleScript(script) else { return nil }
    let parts = result.components(separatedBy: "||")
    guard parts.count == 3 else { return nil }
    let posStr = parts[2].replacingOccurrences(of: ",", with: ".")
    guard let pos = Double(posStr) else { return nil }
    return NowPlayingInfo(title: parts[0], artist: parts[1], position: pos, playbackRate: 1)
}

nonisolated func nowPlayingFromSpotify() -> NowPlayingInfo? {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil else {
        return nil
    }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
        return nil
    }
    let script = """
    with timeout of 2 seconds
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    set t to name of current track
                    set a to artist of current track
                    set p to player position
                    return t & "||" & a & "||" & (p as string)
                end if
            end tell
        end if
    end timeout
    """
    guard let result = runAppleScript(script) else { return nil }
    let parts = result.components(separatedBy: "||")
    guard parts.count == 3 else { return nil }
    let posStr = parts[2].replacingOccurrences(of: ",", with: ".")
    guard let pos = Double(posStr) else { return nil }
    return NowPlayingInfo(title: parts[0], artist: parts[1], position: pos, playbackRate: 1)
}

// DISABLED: browser YouTube Music support (AppleScript connection unreliable)
nonisolated func nowPlayingFromBrowser() -> NowPlayingInfo? {
    return nil
}

// MARK: - Playback Controls
nonisolated func controlPlayback(app: AutomationTarget, action: String) {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first != nil else { return }
    let script = """
    with timeout of 2 seconds
        tell application "\(app.appName)"
            \(action)
        end tell
    end timeout
    """
    var error: NSDictionary?
    guard let appleScript = NSAppleScript(source: script) else { return }
    appleScript.executeAndReturnError(&error)
    if let error {
        NSLog("LyricBar: playback control error: \(error)")
    }
}

nonisolated func playPauseMusic() {
    controlPlayback(app: .music, action: "playpause")
}

nonisolated func nextTrackMusic() {
    controlPlayback(app: .music, action: "next track")
}

nonisolated func previousTrackMusic() {
    controlPlayback(app: .music, action: "previous track")
}

nonisolated func playPauseSpotify() {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else { return }
    let script = """
    with timeout of 2 seconds
        tell application "Spotify"
            if player state is playing then
                pause
            else
                play
            end if
        end tell
    end timeout
    """
    var error: NSDictionary?
    guard let appleScript = NSAppleScript(source: script) else { return }
    appleScript.executeAndReturnError(&error)
    if let error {
        NSLog("LyricBar: playback control error: \(error)")
    }
}

nonisolated func nextTrackSpotify() {
    controlPlayback(app: .spotify, action: "next track")
}

nonisolated func previousTrackSpotify() {
    controlPlayback(app: .spotify, action: "previous track")
}

enum AutomationTarget {
    case music
    case spotify

    nonisolated var bundleIdentifier: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    nonisolated var appName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }
}

@discardableResult
nonisolated func performAutomationAccessRequest(app: AutomationTarget) -> Bool {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) != nil else {
        NSLog("Automation request: \(app.appName) not found on this system")
        return false
    }

    let script = """
    with timeout of 2 seconds
        tell application "\(app.appName)"
            return name
        end tell
    end timeout
    """

    var error: NSDictionary?
    guard let appleScript = NSAppleScript(source: script) else { return false }
    appleScript.executeAndReturnError(&error)
    if let error {
        NSLog("Automation request error: \(error)")
        return false
    }
    return true
}

// MARK: - LyricTicker
final class LyricTicker: ObservableObject {

    // Simple caches
    private var memoryCache: [String: String] = [:] // key: cacheKey(artist,title), value: LRC
    private lazy var cacheDir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LyricBarCache", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    // Published UI state
    @Published var current: String = "LyricBar"       // current lyric line
    @Published var isFetching: Bool = false          // whether we are fetching lyrics
    @Published var nowPlayingArtist: String = ""     // artist from source
    @Published var nowPlayingTitle: String = ""      // title from source
    @Published var musicAccessOK: Bool = false
    @Published var spotifyAccessOK: Bool = false

    // Computed title for MenuBarExtra
    var menuBarTitle: String {
        if isFetching {
            let t = [nowPlayingArtist, nowPlayingTitle].filter { !$0.isEmpty }.joined(separator: " - ")
            return t.isEmpty ? "Fetching…" : t
        }
        return current.isEmpty ? "—" : current
    }

    private var syncLines: [LRCLine] = []
    private var syncStartDate: Date?
    private var rawLRC: String = ""

    var lyricLines: [LRCLine] { syncLines }

    private let source = LyricsSource()
    private var monitorTimer: Timer?
    private var currentSongKey: String = ""
    private var spotifyAuthCooldown: Date = .distantPast
    @Published var isPlaying: Bool = false
    private var lastActiveSource: AutomationTarget?
    private var idleTimer: Timer?

    // MARK: Access check
    func checkAutomationAccess() {
        requestAutomationAccess(app: .music)
        requestAutomationAccess(app: .spotify)
    }

    // MARK: Now Playing Monitoring
    private let activePollInterval: TimeInterval = 1.0
    private let idlePollInterval: TimeInterval = 5.0

    private func setPollingTimer(_ interval: TimeInterval) {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollNowPlaying()
        }
        if let monitorTimer { RunLoop.main.add(monitorTimer, forMode: .common) }
    }

    func startMonitoringNowPlaying() {
        stopMonitoring()
        setPollingTimer(idlePollInterval)
        pollNowPlaying()
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func pollNowPlaying() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let amInfo = nowPlayingFromAppleMusic()
            if amInfo != nil { DispatchQueue.main.async { self.musicAccessOK = true; self.lastActiveSource = .music } }
            let spotifyInfo: NowPlayingInfo?
            if Date().timeIntervalSince(self.spotifyAuthCooldown) >= 60 {
                spotifyInfo = nowPlayingFromSpotify()
                if spotifyInfo != nil { DispatchQueue.main.async { self.spotifyAccessOK = true; if amInfo == nil { self.lastActiveSource = .spotify } } }
                if spotifyInfo == nil && self.spotifyAuthCooldown == .distantPast {
                    self.spotifyAuthCooldown = Date()
                }
            } else {
                spotifyInfo = nil
            }
            guard let info = amInfo ?? spotifyInfo else {
                DispatchQueue.main.async {
                    if self.isPlaying { self.isPlaying = false }
                    if self.idleTimer == nil {
                        self.idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                            guard let self else { return }
                            self.current = "LyricBar"
                            self.nowPlayingArtist = ""
                            self.nowPlayingTitle = ""
                            self.currentSongKey = ""
                            self.syncLines.removeAll()
                            self.idleTimer = nil
                            self.rawLRC = ""
                            self.setPollingTimer(self.idlePollInterval)
                        }
                    }
                }
                return
            }
            DispatchQueue.main.async {
                self.setPollingTimer(self.activePollInterval)
                self.idleTimer?.invalidate()
                self.idleTimer = nil
                let wasPlaying = self.isPlaying
                if wasPlaying != info.isPlaying { self.isPlaying = info.isPlaying }
                let songKey = "\(info.title)||\(info.artist)"
                if songKey != self.currentSongKey {
                    self.currentSongKey = songKey
                    Task { await self.prepareAndFetch(for: info) }
                } else if !self.syncLines.isEmpty {
                    if info.isPlaying || !wasPlaying {
                        self.updateCurrentLine(elapsed: info.position)
                    }
                }
            }
        }
    }

    private func prepareAndFetch(for info: NowPlayingInfo) async {
        await MainActor.run {
            self.beginFetching(artist: info.artist, title: info.title)
        }

        do {
            // Try cache first
            let key = cacheKey(artist: info.artist, title: info.title)
            let lrc: String
            if let cached = readCache(for: key) {
                lrc = cached
            } else {
                let fetched = try await source.fetchSyncedLyrics(track: info.title, artist: info.artist)
                lrc = fetched
                writeCache(fetched, for: key)
            }

            let lines = LRCParser.parse(lrc)
            await MainActor.run {
                self.rawLRC = lrc
                self.syncLines = lines
                self.isFetching = false
                self.current = lines.first?.text ?? "—"
                self.syncStartDate = Date().addingTimeInterval(-info.position)
            }
        } catch {
            NSLog("LyricBar: fetch error: \(error)")
            await MainActor.run {
                self.rawLRC = ""
                self.syncLines = []
                self.isFetching = false
                self.current = [info.artist, info.title].filter { !$0.isEmpty }.joined(separator: " - ")
                self.syncStartDate = nil
            }
        }
    }

    // MARK: Fetching state helpers
    func beginFetching(artist: String, title: String) {
        syncLines.removeAll()
        syncStartDate = nil
        nowPlayingArtist = artist
        nowPlayingTitle = title
        isFetching = true
        current = ""
    }

    func requestAutomationAccess(app: AutomationTarget) {
        Task.detached { [weak self] in
            let ok = performAutomationAccessRequest(app: app)
            await MainActor.run {
                switch app {
                case .music: self?.musicAccessOK = ok
                case .spotify: self?.spotifyAccessOK = ok
                }
            }
        }
    }

    // MARK: Sync update
    private func updateCurrentLine(elapsed: TimeInterval) {
        guard !syncLines.isEmpty else { return }
        var idx = 0
        while idx + 1 < syncLines.count && elapsed >= syncLines[idx + 1].time {
            idx += 1
        }
        let newCurrent = syncLines[idx].text
        if current != newCurrent { current = newCurrent }
    }

    // MARK: - Playback Controls
    func togglePlayPause() {
        guard let source = lastActiveSource else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            switch source {
            case .music: playPauseMusic()
            case .spotify: playPauseSpotify()
            }
        }
    }

    func nextTrack() {
        guard let source = lastActiveSource else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            switch source {
            case .music: nextTrackMusic()
            case .spotify: nextTrackSpotify()
            }
        }
    }

    func previousTrack() {
        guard let source = lastActiveSource else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            switch source {
            case .music: previousTrackMusic()
            case .spotify: previousTrackSpotify()
            }
        }
    }

    // MARK: - Export LRC
    func exportLRC() {
        guard !rawLRC.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(nowPlayingArtist) - \(nowPlayingTitle).lrc"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? self.rawLRC.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Copy Lyrics
    func copyLyricsToClipboard() {
        let lines = syncLines
        guard !lines.isEmpty else { return }
        let text = lines.map { $0.text }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Cache helpers
    func clearCache() {
        memoryCache.removeAll()
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }
    }

    private func cacheKey(artist: String, title: String) -> String {
        let raw = (artist + "||" + title).lowercased()
        if let data = raw.data(using: .utf8) {
            let digest = SHA256.hash(data: data)
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        }
        return raw.replacingOccurrences(of: "/", with: "_")
    }

    private func readCache(for key: String) -> String? {
        if let m = memoryCache[key] { return m }
        let url = cacheDir.appendingPathComponent(key + ".lrc")
        if let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) {
            memoryCache[key] = s
            return s
        }
        return nil
    }

    private func writeCache(_ value: String, for key: String) {
        memoryCache[key] = value
        let url = cacheDir.appendingPathComponent(key + ".lrc")
        try? value.data(using: .utf8)?.write(to: url)
    }
}

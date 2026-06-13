# LyricBar

<p align="center">
  <img src="LyricBar Rounded.png" width="128" alt="LyricBar" style="border-radius: 24px">
</p>

A lightweight macOS menu bar app that displays **synchronized lyrics** for the currently playing song from Apple Music or Spotify.

## Features

- **Real-time lyric sync** — displays the current lyric line in your menu bar
- **Apple Music & Spotify** — auto-detects playing song from either app
- **Synced scrolling** — full lyrics window with auto-scroll to the current line
- **LRCLIB integration** — fetches timestamped `.lrc` lyrics automatically
- **Offline cache** — caches fetched lyrics locally for instant recall
- **Menu bar only** — no dock icon, no clutter
- **Launch at Login** — optional toggle in menu
- **Dynamic access status** — shows checkmark when app is authorized

## Requirements

- macOS 26 (Sequoia) or later
- Apple Music and/or Spotify desktop app installed
- Automation permission granted (prompted on first launch)

## Installation

**From DMG (recommended):** Download `LyricBar.*.dmg` from [Releases](https://github.com/rigelra15/LyricBar/releases/latest), open it, drag the app to `/Applications`.

Since LyricBar isn't code-signed, macOS will flag it on first launch. The quickest workaround:
```bash
xattr -cr /Applications/LyricBar.app
```
Alternatively, right-click the app in Finder, pick **Open**, then hit **Open Anyway**.

**From source:** Clone the repo, open `LyricBar.xcodeproj` in Xcode, set your team, ⌘R.

## Usage

Run LyricBar from `/Applications`. Approve the automation prompts for Music/Spotify. Start playing a song — lyrics appear in the menu bar automatically.

**Menu Bar Items:**

| Item | Description |
|------|-------------|
| Now Playing | Artist - Title (shown when music is playing) |
| Music/Spotify Access | Request or verify automation permission |
| Show Full Lyrics | Opens a scrollable lyrics window |
| Clear Lyrics Cache | Clears cached LRC files |
| Launch at Login | Toggle auto-start with macOS |
| About LyricBar | App info and version |

## How It Works

1. **Detection** — AppleScript polls Apple Music / Spotify for current track info (title, artist, playback position)
2. **Fetch** — Queries [LRCLIB](https://lrclib.net) API for synced lyrics
3. **Parse** — Parses `.lrc` timestamp format
4. **Sync** — Matches playback position to the correct lyric line
5. **Display** — Shows current line in menu bar; full lyrics view scrolls in sync

## Project Structure

```
LyricBar/
├── LyricBar/
│   ├── LyricBarApp.swift      # App entry, menu bar UI, lyrics/about windows
│   ├── LyricTicker.swift       # Core logic: detection, fetching, caching, sync
│   ├── ContentView.swift       # Unused (menu bar only app)
│   └── Assets.xcassets/        # App icon and logo
├── LyricBar.xcodeproj/         # Xcode project
└── .gitignore
```

## Contributing

Open an issue or PR — contributions welcome.

## Acknowledgments

- [LRCLIB](https://lrclib.net) — open-source lyrics API
- Apple Music & Spotify for AppleScript support

## License

[MIT](LICENSE) — free to use, modify, and distribute.

## Author

Made by [@rigelra](https://github.com/rigelra)

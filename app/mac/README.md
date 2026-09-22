# Marko.app — native Mac viewer

A ~1 MB AppKit app that hosts the Marko viewer in a WKWebView. No Electron, no runtime, no network: the three
viewer libraries are vendored into the bundle at build time.

- Double-click any `.md` (choose Marko once via *Open With ▸ Always*), drag files onto the Dock icon, or `open -a Marko file.md`.
- Live reload: the document refreshes whenever the file changes on disk — including saves by Claude Code.
- `⌘1` `⌘2` `⌘3` switch Reading / Plan / Interactive · `⌘O` open · `⌘R` reload · `⌘F` search · `⌘⌥1` / `⌘⌥2` toggle outline / panel · Open Recent · Reveal in Finder · Copy Updated Markdown.
- The `marko` CLI and the Claude Code hooks use the app automatically once it is in `/Applications` (`marko open --browser` forces the browser; `"app": false` in `.claude/marko.json` disables it).

## Default app for `.md` files

Marko asks once, on first launch, whether to become the default app for Markdown files. Later: **Marko ▸ Make Default for Markdown Files**, or install with it already set:

```
app/mac/build.sh --install --default
```

To undo, pick another app in Finder (select a `.md` ▸ Get Info ▸ Open with ▸ Change All).

## Build

Requires Xcode Command Line Tools (`xcode-select --install`) and Node. No Xcode project.

```
app/mac/build.sh --install     # builds app/mac/build/Marko.app and copies it to /Applications
app/mac/build.sh --dmg         # also creates app/mac/build/Marko-<version>.dmg
```

The build is universal (Apple silicon + Intel), ad-hoc signed, and takes a few seconds.

## Distributing to other Macs

An ad-hoc signed app runs on the Mac that built it. On another Mac, Gatekeeper will say the developer can't be
verified; the user can right-click ▸ Open once, or run `xattr -d com.apple.quarantine /Applications/Marko.app`.

For a download that opens without warnings, sign with a Developer ID and notarize:

```
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" app/mac/build.sh --dmg
xcrun notarytool submit app/mac/build/Marko-0.2.0.dmg --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple app/mac/build/Marko-0.2.0.dmg
```

(`notarytool store-credentials AC_PASSWORD` once, with an App Store Connect API key or app-specific password.)
Attach the DMG to a GitHub release; a Homebrew cask (`brew install --cask marko`) is a small formula on top of that.

## Files

- `main.swift` — the whole app (window, menus, file open/recent, directory watcher, WebKit bridge).
- `Info.plist` — bundle metadata and the Markdown document type registration.
- `build.sh` — assembles the bundle, vendors the viewer libraries, makes the icon, compiles, signs.
- `icon.png` — 1024 px source for the `.icns`.

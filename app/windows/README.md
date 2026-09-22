# Marko for Windows

A small WinForms host (.NET 8) around the Marko viewer, rendered by **WebView2** — the Edge runtime that ships with Windows 10/11. The framework-dependent build is about 2 MB; nothing is bundled twice.

- Double-click `.md` files (after choosing Marko as default), drag files onto the window, `Marko.exe file.md`, File ▸ Open, Open Recent.
- Live reload: the document refreshes whenever the file changes on disk — including saves by Claude Code.
- `Ctrl+1` `Ctrl+2` `Ctrl+3` switch Reading / Plan / Interactive · `Ctrl+O` open · `F5` reload · `Ctrl+F` search · `Ctrl+Alt+1` / `Ctrl+Alt+2` toggle outline / panel · `Ctrl+±` zoom · File ▸ Copy Updated Markdown · Show in Explorer.
- Preferences (mode, sidebars, text size, ticks) persist in `%APPDATA%\Marko\prefs.json`; window size and position are remembered.
- The `marko` CLI and the Claude Code hooks use the app automatically once it is installed in `%LOCALAPPDATA%\Marko` (`marko open --browser` forces the browser).

## Build

Requires the [.NET 8 SDK](https://dot.net) and Node. In PowerShell:

```
.\app\windows\build.ps1 -Install            # build + install to %LOCALAPPDATA%\Marko + Start Menu + register .md
.\app\windows\build.ps1 -Install -Default   # ...and open the Default Apps page to make Marko the default
.\app\windows\build.ps1 -Zip                # portable zip for other PCs
.\app\windows\build.ps1 -SelfContained -Zip # ~70 MB build that needs no .NET runtime installed
```

If PowerShell refuses to run scripts: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once.

## Default app for `.md` files

Windows 10/11 don't let programs make themselves the default silently. Marko registers itself (per user, no admin) and opens **Settings ▸ Apps ▸ Default apps ▸ Marko**, where one click sets `.md`, `.markdown`, `.mdown` and `.mdx`. It offers this on first launch; later use **File ▸ Make Marko the Default for Markdown Files**, or `Marko.exe --set-default`. `Marko.exe --unregister` removes the registration.

## Distributing

- **Portable zip** (`-Zip`): unzip anywhere and run `Marko.exe`. SmartScreen may warn on first run of an unsigned exe ("More info ▸ Run anyway").
- **Signed**: sign `Marko.exe` with a code-signing certificate (`signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a Marko.exe`) to avoid the SmartScreen warning.
- **winget**: a manifest pointing at the GitHub release zip makes it `winget install Marko`.

## Files

- `Program.cs` — the whole app (window, menus, open/recent, file watcher, WebView2 bridge, file association).
- `Marko.csproj`, `app.manifest` — project and DPI/OS manifest.
- `build.ps1` — vendors the viewer libraries, publishes a single-file exe, installs, zips.
- `marko.ico` — app icon.

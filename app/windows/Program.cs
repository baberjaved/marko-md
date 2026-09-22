// Marko for Windows — a lightweight host for the Marko Markdown viewer.
// WinForms window + WebView2 (the Edge runtime already on Windows 10/11), loading viewer\marko.html next to the exe.
// Opens .md files by double-click, drag-and-drop, File ▸ Open or `Marko.exe file.md`, and reloads when the file changes.
// Build with app\windows\build.ps1 (needs the .NET 8 SDK).

using System.Diagnostics;
using System.Media;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;

namespace Marko;

static class Program
{
    public static readonly string DataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Marko");
    public static readonly string ExePath = Environment.ProcessPath ?? Application.ExecutablePath;

    [STAThread]
    static void Main(string[] args)
    {
        Directory.CreateDirectory(DataDir);
        if (args.Contains("--register")) { FileAssociation.Register(); return; }
        if (args.Contains("--set-default")) { FileAssociation.Register(); FileAssociation.OpenDefaultAppsSettings(); return; }
        if (args.Contains("--unregister")) { FileAssociation.Unregister(); return; }

        ApplicationConfiguration.Initialize();
        var file = args.FirstOrDefault(a => !a.StartsWith("--") && File.Exists(a));
        Application.Run(new MainForm(file));
    }
}

sealed class MainForm : Form
{
    private readonly WebView2 _web = new() { Dock = DockStyle.Fill };
    private readonly MenuStrip _menu = new();
    private readonly ToolStripMenuItem _recentMenu = new("Open &Recent");
    private readonly System.Windows.Forms.Timer _reloadTimer = new() { Interval = 150 };
    private FileSystemWatcher? _watcher;
    private string? _current;
    private bool _pageReady;
    private string? _pending;
    private static readonly string ViewerDir = Path.Combine(AppContext.BaseDirectory, "viewer");
    private static readonly string PrefsFile = Path.Combine(Program.DataDir, "prefs.json");
    private static readonly string SettingsFile = Path.Combine(Program.DataDir, "settings.json");
    private static readonly string RecentFile = Path.Combine(Program.DataDir, "recent.json");

    public MainForm(string? file)
    {
        _pending = file;
        Text = "Marko";
        Icon = Icon.ExtractAssociatedIcon(Program.ExePath);
        StartPosition = FormStartPosition.WindowsDefaultLocation;
        MinimumSize = new Size(480, 360);
        RestoreWindowBounds();
        BuildMenu();
        Controls.Add(_web);
        Controls.Add(_menu);
        MainMenuStrip = _menu;
        _reloadTimer.Tick += (_, _) => { _reloadTimer.Stop(); ReloadCurrent(); };
        Load += async (_, _) => await InitWebViewAsync();
        FormClosing += (_, _) => SaveWindowBounds();
    }

    // ---------- WebView2 ----------

    private async Task InitWebViewAsync()
    {
        try
        {
            var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Marko", "WebView2"));
            await _web.EnsureCoreWebView2Async(env);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "Marko needs the Microsoft Edge WebView2 Runtime, which is part of Windows 10/11. If it is missing, install it from https://developer.microsoft.com/microsoft-edge/webview2/\n\n" + ex.Message, "Marko", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
            return;
        }
        var core = _web.CoreWebView2;
        core.Settings.AreDevToolsEnabled = true;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false; // menus own Ctrl+O, F5, etc.
        core.SetVirtualHostNameToFolderMapping("marko.app", ViewerDir, CoreWebView2HostResourceAccessKind.Allow);

        // Tell the page it's hosted natively and seed saved preferences before any of its scripts run.
        var seed = "document.documentElement.dataset.app='windows';";
        if (File.Exists(PrefsFile)) { var json = File.ReadAllText(PrefsFile).Trim(); if (json.StartsWith("{")) seed += "window.__markoPrefs=" + json + ";"; }
        await core.AddScriptToExecuteOnDocumentCreatedAsync(seed);

        core.WebMessageReceived += OnWebMessage;
        core.NavigationCompleted += (_, _) => { _pageReady = true; if (_pending != null) { var f = _pending; _pending = null; OpenFile(f); } OfferDefaultOnFirstLaunch(); };
        core.NewWindowRequested += (_, e) => { e.Handled = true; OpenExternal(e.Uri); };
        core.NavigationStarting += (_, e) => { if (!e.Uri.StartsWith("https://marko.app/", StringComparison.OrdinalIgnoreCase)) { e.Cancel = true; OpenExternal(e.Uri); } };
        core.Navigate("https://marko.app/marko.html");
    }

    private static void OpenExternal(string uri)
    {
        if (uri.StartsWith("http://") || uri.StartsWith("https://")) { try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); } catch { /* ignore */ } }
    }

    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var doc = JsonDocument.Parse(e.WebMessageAsJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Object || !doc.RootElement.TryGetProperty("cmd", out var cmd)) return;
            switch (cmd.GetString())
            {
                case "title":
                    var t = doc.RootElement.TryGetProperty("title", out var tt) ? tt.GetString()?.Trim() : null;
                    Text = string.IsNullOrEmpty(t) ? "Marko" : t + " — Marko";
                    break;
                case "prefs":
                    if (doc.RootElement.TryGetProperty("data", out var d) && d.GetString() is { Length: < 512_000 } json) File.WriteAllText(PrefsFile, json);
                    break;
                case "key":
                    HandleKey(doc.RootElement.GetProperty("key").GetString() ?? "", doc.RootElement.TryGetProperty("ctrl", out var c) && c.GetBoolean(), doc.RootElement.TryGetProperty("alt", out var a) && a.GetBoolean());
                    break;
            }
        }
        catch { /* malformed message: ignore */ }
    }

    private void HandleKey(string key, bool ctrl, bool alt)
    {
        switch (key)
        {
            case "F5": ReloadCurrent(); break;
            case "F1": OpenGuide(); break;
            case "o" or "O" when ctrl: OpenDialog(); break;
            case "f" or "F" when ctrl: Js("window.marko&&window.marko.search()"); break;
            case "1" when ctrl && alt: Js("window.marko&&window.marko.togglePanel('outline')"); break;
            case "2" when ctrl && alt: Js("window.marko&&window.marko.togglePanel('inspector')"); break;
            case "1" when ctrl: Js("window.marko&&window.marko.setMode('reading')"); break;
            case "2" when ctrl: Js("window.marko&&window.marko.setMode('plan')"); break;
            case "3" when ctrl: Js("window.marko&&window.marko.setMode('interactive')"); break;
            case "+" or "=" when ctrl: _web.ZoomFactor = Math.Min(2.0, _web.ZoomFactor + 0.1); break;
            case "-" when ctrl: _web.ZoomFactor = Math.Max(0.6, _web.ZoomFactor - 0.1); break;
            case "0" when ctrl: _web.ZoomFactor = 1.0; break;
        }
    }

    private void OpenGuide() { var g = Path.Combine(ViewerDir, "guide.md"); if (File.Exists(g)) OpenFile(g); else OpenExternal("https://github.com/baberjaved/marko-md/blob/main/docs/guide.md"); }

    private async void Js(string script) { if (_pageReady) { try { await _web.CoreWebView2.ExecuteScriptAsync(script); } catch { /* page gone */ } } }

    // ---------- Documents ----------

    public void OpenFile(string path)
    {
        if (!_pageReady) { _pending = path; return; }
        path = Path.GetFullPath(path);
        string text;
        try { text = File.ReadAllText(path); }
        catch (Exception ex) { MessageBox.Show(this, $"Couldn't open {Path.GetFileName(path)}\n{ex.Message}", "Marko", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        var first = !string.Equals(_current, path, StringComparison.OrdinalIgnoreCase);
        _current = path;
        Send(text, Path.GetFileName(path), keepMode: !first);
        AddRecent(path);
        if (first) Watch(path);
    }

    private void Send(string text, string name, bool keepMode)
    {
        var args = JsonSerializer.Serialize(new object[] { text, name, keepMode });
        Js($@"(function(a){{ if(!window.marko) return; var keep=a[2]&&window.marko.mode(); var c=document.getElementById('canvas'); var y=c.scrollTop;
               window.marko.open(a[0],a[1],keep||null); if(a[2]){{ c.style.scrollBehavior='auto'; c.scrollTop=y; c.style.scrollBehavior=''; }} }})({args});");
    }

    private void ReloadCurrent()
    {
        if (_current == null || !File.Exists(_current)) return;
        string text;
        try { text = File.ReadAllText(_current); } catch { return; }
        Send(text, Path.GetFileName(_current), keepMode: true);
        Js("(function(){var t=document.getElementById('toast');if(!t)return;t.textContent='Updated from disk';t.classList.add('show');setTimeout(function(){t.classList.remove('show')},1800);})();");
    }

    private void Watch(string path)
    {
        _watcher?.Dispose();
        var dir = Path.GetDirectoryName(path)!; var name = Path.GetFileName(path);
        _watcher = new FileSystemWatcher(dir) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName, IncludeSubdirectories = false, EnableRaisingEvents = true };
        void Bump(string? changed) { if (changed != null && !string.Equals(changed, name, StringComparison.OrdinalIgnoreCase)) return; BeginInvoke(() => { _reloadTimer.Stop(); _reloadTimer.Start(); }); }
        _watcher.Changed += (_, e) => Bump(e.Name);
        _watcher.Created += (_, e) => Bump(e.Name);
        _watcher.Renamed += (_, e) => Bump(e.Name);
    }

    // ---------- Menu ----------

    private void BuildMenu()
    {
        var file = new ToolStripMenuItem("&File");
        file.DropDownItems.Add(new ToolStripMenuItem("&Open…", null, (_, _) => OpenDialog()) { ShortcutKeys = Keys.Control | Keys.O });
        file.DropDownItems.Add(_recentMenu);
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add(new ToolStripMenuItem("&Reload", null, (_, _) => ReloadCurrent()) { ShortcutKeys = Keys.F5 });
        file.DropDownItems.Add(new ToolStripMenuItem("Show in &Explorer", null, (_, _) => { if (_current != null) Process.Start("explorer.exe", $"/select,\"{_current}\""); }));
        file.DropDownItems.Add(new ToolStripMenuItem("Copy Updated &Markdown", null, async (_, _) => await CopyUpdatedMarkdown()));
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add(new ToolStripMenuItem("Make Marko the &Default for Markdown Files", null, (_, _) => { FileAssociation.Register(); FileAssociation.OpenDefaultAppsSettings(); }));
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add(new ToolStripMenuItem("E&xit", null, (_, _) => Close()) { ShortcutKeys = Keys.Alt | Keys.F4 });

        var view = new ToolStripMenuItem("&View");
        view.DropDownItems.Add(new ToolStripMenuItem("&Reading", null, (_, _) => Js("window.marko&&window.marko.setMode('reading')")) { ShortcutKeys = Keys.Control | Keys.D1 });
        view.DropDownItems.Add(new ToolStripMenuItem("&Plan", null, (_, _) => Js("window.marko&&window.marko.setMode('plan')")) { ShortcutKeys = Keys.Control | Keys.D2 });
        view.DropDownItems.Add(new ToolStripMenuItem("&Interactive", null, (_, _) => Js("window.marko&&window.marko.setMode('interactive')")) { ShortcutKeys = Keys.Control | Keys.D3 });
        view.DropDownItems.Add(new ToolStripSeparator());
        view.DropDownItems.Add(new ToolStripMenuItem("Toggle &Outline", null, (_, _) => Js("window.marko&&window.marko.togglePanel('outline')")) { ShortcutKeys = Keys.Control | Keys.Alt | Keys.D1 });
        view.DropDownItems.Add(new ToolStripMenuItem("Toggle P&anel", null, (_, _) => Js("window.marko&&window.marko.togglePanel('inspector')")) { ShortcutKeys = Keys.Control | Keys.Alt | Keys.D2 });
        view.DropDownItems.Add(new ToolStripMenuItem("&Find", null, (_, _) => Js("window.marko&&window.marko.search()")) { ShortcutKeys = Keys.Control | Keys.F });
        view.DropDownItems.Add(new ToolStripSeparator());
        view.DropDownItems.Add(new ToolStripMenuItem("Zoom &In", null, (_, _) => _web.ZoomFactor = Math.Min(2.0, _web.ZoomFactor + 0.1)) { ShortcutKeys = Keys.Control | Keys.Oemplus });
        view.DropDownItems.Add(new ToolStripMenuItem("Zoom &Out", null, (_, _) => _web.ZoomFactor = Math.Max(0.6, _web.ZoomFactor - 0.1)) { ShortcutKeys = Keys.Control | Keys.OemMinus });
        view.DropDownItems.Add(new ToolStripMenuItem("Actual &Size", null, (_, _) => _web.ZoomFactor = 1.0) { ShortcutKeys = Keys.Control | Keys.D0 });

        var help = new ToolStripMenuItem("&Help");
        help.DropDownItems.Add(new ToolStripMenuItem("Marko &Guide", null, (_, _) => OpenGuide()) { ShortcutKeys = Keys.F1 });
        help.DropDownItems.Add(new ToolStripMenuItem("Marko on &GitHub", null, (_, _) => OpenExternal("https://github.com/baberjaved/marko-md")));
        help.DropDownItems.Add(new ToolStripSeparator());
        help.DropDownItems.Add(new ToolStripMenuItem("&About Marko", null, (_, _) => MessageBox.Show(this, $"Marko {typeof(Program).Assembly.GetName().Version?.ToString(3)}\nA Markdown viewer for Claude output.\n© 2026 Baber Javed · MIT License", "About Marko")));

        _menu.Items.AddRange(new ToolStripItem[] { file, view, help });
        RebuildRecentMenu();
    }

    private void OpenDialog()
    {
        using var dlg = new OpenFileDialog { Filter = "Markdown (*.md;*.markdown;*.mdown;*.mdx)|*.md;*.markdown;*.mdown;*.mdx|Text (*.txt)|*.txt|All files (*.*)|*.*", Title = "Open Markdown" };
        if (dlg.ShowDialog(this) == DialogResult.OK) OpenFile(dlg.FileName);
    }

    private async Task CopyUpdatedMarkdown()
    {
        if (!_pageReady) return;
        var result = await _web.CoreWebView2.ExecuteScriptAsync("window.marko?window.marko.updatedMarkdown():''");
        var text = JsonSerializer.Deserialize<string>(result) ?? "";
        if (text.Length == 0) { SystemSounds.Beep.Play(); return; }
        Clipboard.SetText(text);
    }

    // ---------- Recents & window state ----------

    private List<string> Recents() { try { return JsonSerializer.Deserialize<List<string>>(File.ReadAllText(RecentFile)) ?? new(); } catch { return new(); } }

    private void AddRecent(string path)
    {
        var list = Recents().Where(p => !string.Equals(p, path, StringComparison.OrdinalIgnoreCase)).ToList();
        list.Insert(0, path);
        try { File.WriteAllText(RecentFile, JsonSerializer.Serialize(list.Take(12))); } catch { /* ignore */ }
        RebuildRecentMenu();
    }

    private void RebuildRecentMenu()
    {
        _recentMenu.DropDownItems.Clear();
        var list = Recents();
        foreach (var p in list) _recentMenu.DropDownItems.Add(new ToolStripMenuItem(Path.GetFileName(p), null, (_, _) => OpenFile(p)) { ToolTipText = p });
        if (list.Count > 0) { _recentMenu.DropDownItems.Add(new ToolStripSeparator()); _recentMenu.DropDownItems.Add(new ToolStripMenuItem("Clear Menu", null, (_, _) => { try { File.Delete(RecentFile); } catch { } RebuildRecentMenu(); })); }
        _recentMenu.Enabled = list.Count > 0;
    }

    private sealed class Settings { public bool AskedDefault { get; set; } public int X { get; set; } public int Y { get; set; } public int W { get; set; } = 1180; public int H { get; set; } = 780; public bool Max { get; set; } }
    private Settings _settings = new();

    private void RestoreWindowBounds()
    {
        try { if (File.Exists(SettingsFile)) _settings = JsonSerializer.Deserialize<Settings>(File.ReadAllText(SettingsFile)) ?? new(); } catch { _settings = new(); }
        var bounds = new Rectangle(_settings.X, _settings.Y, _settings.W, _settings.H);
        if (_settings.W > 0 && Screen.AllScreens.Any(s => s.WorkingArea.IntersectsWith(bounds))) { StartPosition = FormStartPosition.Manual; Bounds = bounds; }
        else Size = new Size(1180, 780);
        if (_settings.Max) WindowState = FormWindowState.Maximized;
    }

    private void SaveWindowBounds()
    {
        var r = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
        _settings.X = r.X; _settings.Y = r.Y; _settings.W = r.Width; _settings.H = r.Height; _settings.Max = WindowState == FormWindowState.Maximized;
        try { File.WriteAllText(SettingsFile, JsonSerializer.Serialize(_settings)); } catch { /* ignore */ }
    }

    private void OfferDefaultOnFirstLaunch()
    {
        if (_settings.AskedDefault) return;
        _settings.AskedDefault = true;
        try { File.WriteAllText(SettingsFile, JsonSerializer.Serialize(_settings)); } catch { /* ignore */ }
        var r = MessageBox.Show(this, "Make Marko the default app for Markdown files?\n\nMarko will register itself for .md files and open Windows' Default Apps page so you can confirm.", "Marko", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (r == DialogResult.Yes) { FileAssociation.Register(); FileAssociation.OpenDefaultAppsSettings(); }
    }
}

// Per-user registration (HKCU only — no admin rights needed). Windows itself decides the default; we register as a
// candidate and open the Default Apps page, which is the sanctioned way since Windows 10.
static class FileAssociation
{
    private const string ProgId = "Marko.Markdown";
    private static readonly string[] Extensions = { ".md", ".markdown", ".mdown", ".mdx" };

    public static void Register()
    {
        var exe = Program.ExePath;
        using (var k = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{ProgId}"))
        {
            k.SetValue("", "Markdown Document");
            k.SetValue("FriendlyTypeName", "Markdown Document");
            using (var icon = k.CreateSubKey("DefaultIcon")) icon.SetValue("", $"\"{exe}\",0");
            using (var cmd = k.CreateSubKey(@"shell\open\command")) cmd.SetValue("", $"\"{exe}\" \"%1\"");
        }
        foreach (var ext in Extensions)
            using (var k = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{ext}\OpenWithProgids")) k.SetValue(ProgId, "", RegistryValueKind.String);
        using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Classes\Applications\Marko.exe"))
        {
            k.SetValue("FriendlyAppName", "Marko");
            using (var cmd = k.CreateSubKey(@"shell\open\command")) cmd.SetValue("", $"\"{exe}\" \"%1\"");
            using (var types = k.CreateSubKey("SupportedTypes")) foreach (var ext in Extensions) types.SetValue(ext, "");
        }
        using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Marko\Capabilities"))
        {
            k.SetValue("ApplicationName", "Marko");
            k.SetValue("ApplicationDescription", "Markdown viewer for Claude output");
            using (var fa = k.CreateSubKey("FileAssociations")) foreach (var ext in Extensions) fa.SetValue(ext, ProgId);
        }
        using (var k = Registry.CurrentUser.CreateSubKey(@"Software\RegisteredApplications")) k.SetValue("Marko", @"Software\Marko\Capabilities");
        SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero); // SHCNE_ASSOCCHANGED
    }

    public static void Unregister()
    {
        try { Registry.CurrentUser.DeleteSubKeyTree($@"Software\Classes\{ProgId}", false); } catch { }
        foreach (var ext in Extensions) { try { using var k = Registry.CurrentUser.OpenSubKey($@"Software\Classes\{ext}\OpenWithProgids", true); k?.DeleteValue(ProgId, false); } catch { } }
        try { Registry.CurrentUser.DeleteSubKeyTree(@"Software\Classes\Applications\Marko.exe", false); } catch { }
        try { Registry.CurrentUser.DeleteSubKeyTree(@"Software\Marko", false); } catch { }
        try { using var k = Registry.CurrentUser.OpenSubKey(@"Software\RegisteredApplications", true); k?.DeleteValue("Marko", false); } catch { }
        SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero);
    }

    public static void OpenDefaultAppsSettings()
    {
        // Windows 11 deep-links straight to the app's page; Windows 10 opens the general Default Apps page.
        try { Process.Start(new ProcessStartInfo("ms-settings:defaultapps?registeredAppUser=Marko") { UseShellExecute = true }); }
        catch { try { Process.Start(new ProcessStartInfo("ms-settings:defaultapps") { UseShellExecute = true }); } catch { } }
    }

    [System.Runtime.InteropServices.DllImport("shell32.dll")]
    private static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}

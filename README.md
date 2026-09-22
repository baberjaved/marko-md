# Marko

A Markdown viewer for the documents Claude writes — plans, reports, specs, runbooks, summaries — with three modes chosen for how you'll use the file:

- **Reading** — long-form typography, outline, reading time. For reports and specs.
- **Plan** — phases, round checkboxes, progress, open questions and risks pulled out. For implementation plans and checklists. Tick tasks and copy the Markdown back with the ticks written in.
- **Interactive** — collapsible sections, search, filters, sortable tables. For runbooks and long summaries.

**[Installation & usage guide →](docs/guide.md)**

One HTML file, no accounts, no telemetry, nothing leaves your machine. Renders in your system fonts (San Francisco / New York / SF Mono on a Mac), light and dark.

## Install

Pick whichever fits. They all share the same viewer.

### A. Claude Code plugin (recommended)

Inside Claude Code:

```
/plugin marketplace add baberjaved/marko-md
/plugin install marko@marko-md
```

You get:

- `/marko:view <file.md> [--mode plan|reading|interactive]` — opens the file in your browser.
- A `marko` command on Claude's PATH (`marko open`, `marko serve`, `marko recent`).
- Hooks: whenever Claude writes a Markdown file that matches your watch list (plans, docs, specs, reports by default), Marko refreshes the live view if one is running, or tells you the file is ready to review. At the end of a turn it lists the documents written.

To try it without installing: `git clone https://github.com/baberjaved/marko-md && claude --plugin-dir ./marko-md`.

### B. npm (any terminal, with or without Claude Code)

```
npm install -g marko-md        # then: marko open plan.md
npx marko-md open plan.md      # no install
```

Needs Node 18+ (already there if you use Claude Code). Installs two identical commands, `marko` and `marko-md` — use the second if the Marko.js framework already owns `marko` on your machine.

### C. Standalone file

Download [`viewer/marko.html`](viewer/marko.html), open it in a browser, drag any `.md` onto it or paste Markdown. Bookmark it. That's the whole install.

### D. Claude app

- Pin the published Marko page in your Claude sidebar and drop files onto it, or
- Add the skill in `claude-app/marko/` (Settings → Capabilities → Skills → upload the folder). Claude will then publish plans and reports it writes as Marko pages automatically, in the right mode.

### E. Mac app

A native, ~1 MB `Marko.app` for double-clicking `.md` files (with live reload when the file changes). Build it on your Mac with the Command Line Tools:

```
app/mac/build.sh --install
```

Details, DMG and notarization in [`app/mac/README.md`](app/mac/README.md). Once installed, `marko open` and the Claude Code hooks use the app instead of a browser tab.

## Use

```
marko open plan.md                     # opens in the browser; mode picked from the file
marko open report.md --mode reading    # force a mode
marko serve                            # live: files Claude writes open here and refresh on change
marko serve docs/spec.md --port 8080   # live view of one file
marko recent                           # Markdown Claude wrote recently (recorded by the hook)
```

`marko serve` is the nicest way to work: leave it running in a second terminal, and every plan Claude writes appears in the tab and updates as Claude edits it. Ticking tasks in Plan mode and pressing **Copy Updated Markdown** gives you the file with `[x]` written back — paste it over the original (or hand it to Claude).

Keyboard: `1` `2` `3` switch modes · `j` `k` move between sections · `/` search · `o` open a file · `Esc` exit focus.

## Configure

Project: `.claude/marko.json`. User-wide: `~/.marko/config.json`. Project values win.

```json
{
  "watch": ["plans/**", "docs/**", "**/*plan*.md", "**/*spec*.md", "**/*report*.md"],
  "ignore": ["node_modules/**", ".git/**", "**/CLAUDE.md"],
  "autoOpen": "server",
  "port": 7331,
  "modeByGlob": { "plans/**": "plan", "docs/**": "reading", "runbooks/**": "interactive" }
}
```

- `watch` — which written files Marko cares about (glob; `**` spans directories, a pattern without `/` matches anywhere).
- `autoOpen` — `"server"` (default): only refresh a running `marko serve`; `true`: open a browser tab on every matching write; `false`: never open, just mention it.
- `modeByGlob` — default mode by path. Front matter `default_mode:` in the file overrides this; `--mode` overrides both.

## How the pieces fit

```
Claude Code writes plans/auth.md
        │ PostToolUse hook (Write|Edit)
        ▼
  marko hook post-tool-use ──► marko serve running? ──► tab refreshes (SSE)
        │                              │ no
        │                              ▼
        │                     autoOpen true? ──► marko open (browser tab)
        ▼                              │ no
  records to ~/.marko/recent.json      ▼
                               "ready to review with /marko:view"
```

- `marko open` writes a self-contained copy of the viewer with the document embedded to `~/.marko/cache/` and opens it — works offline, on any OS.
- `marko serve` binds to `127.0.0.1` only, serves the viewer at `/`, Markdown files at `/f/<path>`, and change events at `/events`.
- The viewer itself is `viewer/marko.html`. It embeds a document through the `<script type="text/markdown" id="doc">` island; anything can generate a page that way.

## Privacy

Nothing is uploaded anywhere. The viewer loads three libraries (marked, highlight.js, mermaid) from cdnjs when online and degrades to plain code blocks / diagram source when offline. `marko serve` listens on localhost only.

## Develop

```
npm run build     # src/viewer.template.html + src/samples → viewer/marko.html, dist/marko-demo.html
npm test          # CLI, hooks, server and viewer checks
```

## Uninstall

`/plugin uninstall marko@marko-md` and/or `npm uninstall -g marko-md`. Cached pages live in `~/.marko/` — delete the folder.

## License

MIT

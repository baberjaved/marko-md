---
title: Marko — Installation & Usage Guide
generated_by: Claude
date: 2026-09-22
status: v0.2.0
default_mode: interactive
---

# Marko — Installation & Usage Guide

Marko is a viewer for the Markdown that Claude writes: plans, reports, specs, runbooks, summaries. It shows any `.md` file in one of three modes — **Reading**, **Plan** or **Interactive** — and plugs into Claude Code and the Claude app so documents open the moment they are written.

> **Tip:** You are reading this guide inside Marko. Press `1`, `2` and `3` to see the same file in each mode, or use the segmented control at the top right.

## 1. Before you start

| You need | Why |
|---|---|
| Node.js 18 or newer | The `marko` command and the live server are a single dependency-free Node script. If you run Claude Code, you already have it. |
| A modern browser | Safari, Chrome, Edge or Firefox from the last two years. |
| Claude Code (optional) | For the `/marko:view` skill and the hooks that open documents automatically. |

Check Node with `node --version`.

## 2. Install

Choose one path. They all share the same viewer, and you can combine them.

### 2.1 Claude Code plugin — recommended

Run these inside a Claude Code session:

```
/plugin marketplace add baberjaved/marko-md
/plugin install marko@marko-md
```

Restart Claude Code (or start a new session). You now have:

- `/marko:view <file.md>` — opens a file in your browser.
- `marko` on Claude's PATH, so Claude can run `marko open` and `marko serve` itself.
- Hooks that react when Claude writes Markdown (see §5).

To try the plugin from a local checkout without installing:

```
git clone https://github.com/baberjaved/marko-md
claude --plugin-dir ./marko-md
```

### 2.2 npm — any terminal

```
npm install -g marko-md
marko --version
```

No install at all:

```
npx marko-md open plan.md
```

The package registers two commands, `marko` and `marko-md`, which do the same thing. If another tool on your machine already owns the name `marko` (the Marko.js web framework ships a CLI), use `marko-md`.

### 2.3 Standalone file — nothing to install

1. Download `viewer/marko.html` from the repository (or use the demo build, `dist/marko-demo.html`, which includes sample documents).
2. Open it in your browser and bookmark it.
3. Drag any `.md` file onto the page, or click **Open → Paste Markdown…**.

The file works offline. It fetches three libraries (marked, highlight.js, mermaid) from cdnjs when it can; without them code shows plain and diagrams show their source.

### 2.4 Claude app

- **Pin it.** Open the published Marko page, pin it in the sidebar, and drop files onto it whenever you like.
- **Let Claude use it.** Upload the `claude-app/marko` folder as a skill (Settings → Capabilities → Skills). From then on, when Claude writes a plan or report as Markdown it publishes it as a Marko page, already in the right mode.

## 3. Verify the install

```
marko --version            # prints 0.2.0
marko open README.md       # opens README in your browser
```

If a browser doesn't open (for example over SSH), the command still prints the path or URL — open it yourself, or add `--no-browser` to skip the attempt.

## 4. Using the viewer

### 4.1 Modes

| Mode | Best for | What changes |
|---|---|---|
| **Reading** | Reports, specs, long documents | Serif body text at a comfortable width, quiet page, outline with scroll tracking, text size and width controls. Nothing to click inside the text. |
| **Plan** | Implementation plans, roadmaps, checklists | Sections become numbered phases with progress bars; tasks get round checkboxes; `**Status:**` lines and ✅ ⏳ 🚧 ❌ markers become status labels; the panel shows overall progress, phases, open questions, risks and dependencies. Code is folded. |
| **Interactive** | Runbooks, long summaries, anything you work through | Collapsible sections, search with highlighting, content filters, sortable tables, a "…" menu on every heading. |

Switch with the control at the top right or the keys `1` `2` `3`. Marko picks a starting mode from the file: front matter `default_mode:`, then the file name (`plan`, `roadmap`, `checklist` → Plan), then the content (many tasks → Plan; long prose → Reading; otherwise Interactive). Your last choice per document is remembered.

### 4.2 Opening files

- **Drag and drop** a `.md` anywhere on the page.
- **Open → Open File…** (or press `o`).
- **Open → Paste Markdown…**, or just paste with `⌘V` / `Ctrl+V` while nothing is focused.
- From the terminal: `marko open file.md` (§6).

### 4.3 The three panes

- **Outline** (left) — every heading; the current one is highlighted as you scroll. In Plan mode each phase shows a small progress line. Toggle with the button at the far left.
- **Document** (centre) — the file, in the current mode. A thin blue line under the toolbar shows how far you have read.
- **Panel** (right) — what the mode needs: text controls and document facts (Reading), progress and extracted questions and risks (Plan), filters and section actions (Interactive). Hidden by default in Reading. Toggle with the button at the far right; the choice is remembered per mode.

### 4.4 Tasks and writing them back

In Plan and Interactive mode, click a checkbox to tick a task. Progress updates immediately. Ticks are kept in your browser, not in the file — so when you want them in the file, open the panel and choose **Copy Updated Markdown**: you get the original text with the `[x]` marks written in. Paste it over the file, or hand it to Claude. **Reset Checkboxes to File** discards your ticks.

### 4.5 Search and filters

Type in the search field (or press `/`). Matches are highlighted and sections without a match fold away; the count appears in the field. In Interactive mode the panel's switches narrow the page to sections that contain tasks, code, tables, callouts or diagrams.

### 4.6 The section menu

In Interactive mode, hover a heading and click **…**:

- **Focus on this section** — hides everything else. *Show All* brings it back (or press `Esc`).
- **Ask Claude about it** — copies a ready-made prompt containing the section's Markdown; paste it into Claude.
- **Copy as Markdown** — copies just that section.

Click a heading (or its chevron) to collapse it; **Expand All**, **Collapse All** and **Collapse Completed** are in the panel.

### 4.7 Keyboard

| Key | Action |
|---|---|
| `1` `2` `3` | Reading / Plan / Interactive |
| `j` / `k` | Next / previous section |
| `/` | Search |
| `o` | Open a file |
| `Esc` | Close menus, leave focus, clear a field |

## 5. Using it from Claude Code

### 5.1 The `/marko:view` skill

```
/marko:view plans/auth-migration.md
/marko:view docs/spec.md --mode reading
/marko:view
```

With no path it opens the most recent Markdown file Claude wrote. Claude also reaches for this skill on its own when you ask to "open", "view" or "review" a Markdown file, and offers it after writing a plan or report.

### 5.2 What the hooks do

Two hooks run quietly in the background:

- **After every file write** (`PostToolUse` on Write/Edit): if the file is Markdown and matches your watch list — plans, docs, specs, reports and summaries by default — Marko records it and either refreshes a running live view or tells Claude the document is ready for you to review. Non-Markdown files are ignored straight away.
- **At the end of each turn** (`Stop`): if watched Markdown was written during the turn, one line lists the files.

Nothing opens a browser tab on its own unless you ask for it (`"autoOpen": true` in §7).

### 5.3 The recommended workflow: a live tab

Open a second terminal in your project and run:

```
marko serve
```

Leave it running. From now on, every plan or report Claude writes appears in that browser tab and updates as Claude edits it — the subtitle shows **● Live**. Tick tasks as you review, copy the updated Markdown back when you are done. Stop it with `Ctrl+C`.

To watch one file only: `marko serve docs/spec.md`.

### 5.4 Reviewing a plan before approving it

Claude Code's plan mode shows the plan in the terminal. To review it in Marko, ask Claude to save the plan to a file first, for example `.claude/plans/<name>.md`; the hook then opens it in Plan mode in your live tab, where phases, tasks, risks and open questions are laid out. Approve in the terminal as usual.

## 6. Command reference

```
marko open <file> [--mode reading|plan|interactive] [--no-browser] [--static]
marko serve [file] [--port 7331] [--no-browser]
marko recent [-n 10]
marko path
marko --version
```

| Command | What it does |
|---|---|
| `marko open <file>` | Writes a self-contained page with the file embedded to `~/.marko/cache/` and opens it. If `marko serve` is running, opens the file there instead so it stays live. `--static` forces the cached copy. `marko file.md` is a shortcut. |
| `marko serve [file]` | Live server on `127.0.0.1:7331` (next free port if taken). Serves the viewer at `/`, files at `/f/<path>`, change events at `/events`. Opens the browser unless `--no-browser`. |
| `marko recent` | Markdown files Claude wrote recently, newest first (recorded by the hook). |
| `marko path` | Location of the viewer HTML, if you want to copy or embed it. |
| `marko hook …` | Used by the Claude Code hooks; not meant to be run by hand. |

Environment variables: `MARKO_HOME` (data folder, default `~/.marko`), `MARKO_VIEWER` (alternate viewer file).

## 7. Configuration

Project settings live in `.claude/marko.json`; user-wide defaults in `~/.marko/config.json`. Project values win. Everything is optional.

```json
{
  "watch": ["plans/**", "docs/**", "**/*plan*.md", "**/*spec*.md", "**/*report*.md"],
  "ignore": ["node_modules/**", ".git/**", "**/CLAUDE.md"],
  "autoOpen": "server",
  "port": 7331,
  "modeByGlob": {
    "plans/**": "plan",
    "docs/**": "reading",
    "runbooks/**": "interactive"
  }
}
```

| Key | Default | Meaning |
|---|---|---|
| `watch` | plans, docs, `*plan*`, `*roadmap*`, `*checklist*`, `*spec*`, `*report*`, `*summary*` | Which written files Marko reacts to. `**` spans folders; a pattern without `/` matches a file name anywhere. An empty list means every Markdown file. |
| `ignore` | `node_modules`, `.git`, `CLAUDE.md`, `CHANGELOG.md`, `LICENSE.md` | Never react to these. |
| `autoOpen` | `"server"` | `"server"`: only refresh a running `marko serve`. `true`: open a browser tab on every matching write. `false`: never open; just mention it. |
| `port` | `7331` | Port for `marko serve`. |
| `modeByGlob` | plans → plan, docs/reports → reading | Starting mode by path. A file's own `default_mode:` front matter overrides this; `--mode` overrides both. |

## 8. Writing Markdown that Marko reads well

Marko understands ordinary Markdown. A few conventions make Plan mode shine, and Claude follows them when asked:

- Front matter with `title`, `date`, `status`, `generated_by` and `default_mode`.
- One `#` title, `##` for phases, `###` for steps.
- Tasks as `- [ ]` / `- [x]`. Status markers at the start of an item — `✅` `⏳` `🚧` `❌` — or a `**Status:** In progress` line under a heading.
- `**Owner:**`, `**Estimate:**`, `**Depends on:**` lines become facts at the top of a phase.
- Sections named **Risks**, **Dependencies** or **Open questions** are pulled into the panel.
- `> **Note:**`, `> **Warning:**`, `> **Tip:**` (or GitHub's `> [!NOTE]`) become callouts. ```` ```mermaid ```` blocks become diagrams.

## 9. Troubleshooting

| Symptom | What to do |
|---|---|
| `marko: command not found` | npm's global bin folder isn't on your PATH — run `npm prefix -g` and add `<that>/bin` (on Windows, `<that>` itself) to your PATH. Inside Claude Code the plugin puts `marko` on the PATH by itself. |
| `marko` runs some other program | The Marko.js framework also installs a `marko` command. Use `marko-md` instead; it is the same tool. |
| Browser didn't open | Over SSH or in a container there may be no browser. The command prints the URL or path — open it locally, or run `marko serve --no-browser` and forward the port. |
| Port 7331 in use | Marko tries the next five ports and prints the one it used, or set `"port"` in the config / `--port`. |
| Hooks don't seem to run | Check `/plugin` shows Marko enabled and restart the session. Hooks call `node`, so Node must be on the PATH Claude Code uses. Confirm the file matches `watch` and not `ignore`. |
| Diagrams show as text, code isn't coloured | The page couldn't reach cdnjs (offline or blocked). Everything else works; diagrams render again when online. |
| Ticks disappeared | Ticks are stored per browser and per file content. Editing the file (by Claude or you) creates a new version and starts clean — the file's own `[x]` marks are always honoured. Use **Copy Updated Markdown** before editing. |
| Live tab shows "Waiting for Markdown" | That's `marko serve` with no file yet. Write a file that matches `watch` from Claude, run `marko open` in another terminal, or drop a file in. |
| Windows | Everything works from PowerShell and cmd. The data folder is `%USERPROFILE%\.marko`. |

## 10. Updating and uninstalling

- **Plugin:** `/plugin update marko@marko-md`, then restart. Remove with `/plugin uninstall marko@marko-md`.
- **npm:** `npm update -g marko-md`; remove with `npm uninstall -g marko-md`.
- **Data:** cached pages, recent-file history and config live in `~/.marko`. Delete the folder to start fresh.

## 11. Privacy

Nothing is uploaded. Documents stay on your machine; `marko serve` listens on localhost only; the viewer stores your mode, text-size and checkbox choices in your own browser. The only network requests are the three library downloads from cdnjs, and the viewer works without them.

---

🤖 Generated with Claude Code · Marko v0.2.0

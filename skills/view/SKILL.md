---
name: view
description: Open a Markdown file in Marko, a viewer with Reading, Plan and Interactive modes. Use when the user asks to view, open, preview or review a .md file, and after you finish writing a plan, spec, report, runbook or summary as Markdown that the user should look at.
allowed-tools: Bash(marko *) Bash(node *) Read
---

Open a Markdown file in the Marko viewer.

Arguments: `$ARGUMENTS` — a path, optionally followed by `--mode plan|reading|interactive`.

Steps:
1. If no path was given, run `marko recent -n 5` and use the newest file (ask if none).
2. Run `marko open "<path>" [--mode <mode>]`. If a live server is running (`marko serve`), the file opens there and refreshes on every change; otherwise a self-contained page is written to `~/.marko/cache/` and opened in the default browser. The command prints where it opened.
3. Reply with one line: which file opened and in which mode. Do not paste the file's contents.

Choosing a mode when the user doesn't: plans, roadmaps and checklists → `plan`; reports, specs and long documents → `reading`; runbooks and summaries the user will work through → `interactive`. Omit `--mode` to let Marko decide from the file's front matter, name and content.

When you write a plan, spec or report as a `.md` file, finish by offering to open it with this skill (or open it directly when the project's `.claude/marko.json` sets `"autoOpen": true`).

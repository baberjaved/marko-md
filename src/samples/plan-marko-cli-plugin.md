---
title: Implementation Plan — Marko Claude Code plugin
generated_by: Claude Code
date: 2026-09-21
status: In progress
default_mode: plan
---

# Implementation plan: Marko Claude Code plugin

**Owner:** Baber
**Target:** v0.2 — usable end-to-end from a Claude Code session
**Estimate:** 4 working days
**Status:** In progress

This plan turns the Marko prototype into a Claude Code plugin: a `marko` executable, a `/marko` skill, hooks that open written Markdown automatically, and a live-reload server. Phases are ordered by dependency; phase 3 cannot start until the executable exists.

> **Warning:** Hooks run on every matching tool call. The PostToolUse script must return in under 50 ms when the file does not match a watched glob, or it will slow every Write.

## Phase 1 — Package the viewer

**Status:** Done

- [x] Move `viewer.html` into `plugin/assets/` and strip the sample documents
- [x] Add `.claude-plugin/plugin.json` with name, version, description, author
- [x] Confirm the viewer renders from `file://` with no network (fallbacks for hljs and mermaid)
- [x] Write `README.md` with install instructions (`claude --plugin-dir ./marko`)

## Phase 2 — `marko` executable

**Status:** In progress
**Owner:** Baber

### 2.1 `marko open`

- [x] Read the file, inject it into the viewer's data island, write to `~/.cache/marko/<sha1>.html`
- [x] Open with the platform opener (`open` / `xdg-open` / `start`)
- [ ] ⏳ Honour `--mode` and front-matter `default_mode`
- [ ] Return the path on stdout so the skill can quote it

### 2.2 `marko serve`

- [ ] 🚧 Minimal HTTP server on `127.0.0.1:7331` (Node, no dependencies)
- [ ] Serve `/` (viewer), `/f/<path>` (file), `/events` (SSE reload stream)
- [ ] Watch files from `.claude/marko.json` → `watch` globs with `fs.watch`
- [ ] ❌ Blocked: decide whether the server is a daemon or dies with the session (see Open questions)

### 2.3 `marko --tui`

- [ ] Render headings, lists, tables and code with ANSI styling for SSH sessions
- [ ] Page with `less -R` when output exceeds the terminal height

## Phase 3 — Skill and hooks

**Status:** Todo
**Depends on:** Phase 2

- [ ] `skills/marko/SKILL.md` — `/marko <path> [--mode]`, defaults to the most recent `.md`
- [ ] `hooks/hooks.json` — PostToolUse (`Write|Edit|MultiEdit`) and Stop
- [ ] `marko hook post-tool-use` — read stdin JSON, match `tool_input.file_path` against globs, notify server or emit `systemMessage`
- [ ] `marko hook stop` — list Markdown written this turn with links
- [ ] Plan-mode hand-off: skill asks Claude to write plans to `.claude/plans/<slug>.md`

## Phase 4 — Verification

**Status:** Todo

1. Fresh clone, `claude --plugin-dir ./marko`, write a plan → browser opens in Plan mode within 1 s
2. Edit the plan from Claude → open tab reloads without losing ticked tasks
3. Tick three tasks in Marko → **Copy updated Markdown** → paste over the file → `git diff` shows only the three `[x]` changes
4. Kill the network → viewer still renders code and shows Mermaid source instead of a diagram
5. SSH session with no browser → `marko --tui` prints the plan readably

## Risks

- **Hook latency.** A slow hook makes every file write feel slow. Mitigation: fast path that exits before parsing anything when the extension is not `.md`.
- **Port collisions.** 7331 may be taken. Mitigation: try the configured port, then the next five, and print which one was used.
- **Plan-mode behaviour changes.** The hand-off relies on Claude writing the plan to a file on request; if Claude Code adds native plan files, switch to those.

## Dependencies

- Node ≥ 18 on the user's machine (already required by Claude Code)
- `marked`, `highlight.js`, `mermaid` pinned versions available from cdnjs (or vendored for offline use)

## Open questions

- Should `marko serve` outlive the Claude Code session, or stop with it?
- Auto-open on every Markdown write, or only when the file matches `watch` globs?
- Do we want a `--no-browser` flag that only prints the URL for remote sessions?

---

🤖 Generated with Claude Code

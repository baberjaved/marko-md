---
name: marko
description: Publish Markdown deliverables (plans, reports, specs, runbooks, summaries) as a Marko viewer artifact with Reading, Plan and Interactive modes, so the user reviews them in a structured page instead of a flat chat reply.
---

# Marko — Markdown viewer artifact

Use this skill whenever the deliverable is a Markdown document the user will read, review or track: an implementation plan, research report, spec, runbook, checklist or session summary. It turns the document into a Marko page — outline, progress, search, three modes — published as an artifact the user can pin and share.

## How to publish

1. Write the Markdown as usual. Start it with front matter:
   ```
   ---
   title: <document title>
   generated_by: Claude
   date: <YYYY-MM-DD>
   status: <Draft / In progress / Final>
   default_mode: <plan | reading | interactive>
   ---
   ```
   `plan` for plans, roadmaps and checklists; `reading` for reports, specs and long documents; `interactive` for runbooks and summaries.
2. Read the viewer template `viewer/marko.html` in this skill's folder.
3. Insert the document into the empty data island near the end of the file — replace
   `<script type="text/markdown" id="doc" data-name="" data-mode=""></script>`
   with the same tag carrying `data-name="<file name>.md"` and `data-mode="<mode>"`, and the full Markdown as its text content. If the Markdown contains the literal text `</script`, write it as `<\/script`.
4. Publish the result as an artifact (HTML). Title it with the document's title. When revising a document you already published, republish to the same artifact so the link stays valid.
5. Reply with one line: what the document is and which mode it opened in. Do not repeat the document in the reply.

## Notes

- The viewer needs no network for the document itself; it loads three libraries (marked, highlight.js, mermaid) from cdnjs and degrades gracefully without them.
- Task checkboxes the user ticks in Plan/Interactive mode stay in their browser; "Copy Updated Markdown" in the panel gives them the file with the ticks written back, which they can paste to you.
- The user can also open any `.md` by dragging it onto a published Marko page, so one pinned Marko is enough for ad-hoc viewing.

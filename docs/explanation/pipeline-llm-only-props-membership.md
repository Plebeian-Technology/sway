---
mode: explanation
summary: "Why PIPELINE_LLM_ONLY_PROPS lives in its own module and why each prop it names has to be there."
status: agent-extracted
related: [docs/reference/partial-reload-prop-lists.md, docs/explanation/pipeline-run-subscription-reload-scoping.md]
---
<!-- vale Vale.Spelling = NO -->

# Why `PIPELINE_LLM_ONLY_PROPS` is shaped the way it is

`PIPELINE_LLM_ONLY_PROPS` (`app/frontend/components/admin/creator/pipelineLlmOnlyProps.ts`)
is the prop list a partial reload from the "Pipeline & LLM" tab asks the
server for. See [Partial-reload prop lists by page](../reference/partial-reload-prop-lists.md)
for the full catalog this constant belongs to.

## Why it lives in its own module

Pulling the constant out of the component that uses it lets a test pin the
real list without dragging the whole panel — every child, every UI
dependency — through the bundler first. Loading the component just to read
one array cost 681ms of a 5-second per-test budget, which held fine on an
idle machine but not next to thirteen other `verify` lanes running at once.

## Why it is declared once at module scope

Declaring the array once means it is the same object on every render.
Rebuilding it inline on each render would look like a "new" value to
anything comparing it by reference, and risk reopening the live connection
that reads it.

## Why specific entries are on the list

- **`bill`** must be on this list. Without it, the summary panel keeps
  showing "nothing yet" after the summarize stage finishes, even though the
  server already has the finished text — the live push still arrives, it
  just leaves out the one piece of data that would have carried the update,
  so operators had to reload by hand to see it.
- **`stale_pipeline_run_count`** and **`orphan_pipeline_run_count`** come
  from Rails' shared-props block, which only refreshes them on a partial
  reload if they are named here. Leaving them out means the "Remove N stuck
  runs" / "Delete N orphan runs" chips keep showing stale counts after a run
  finishes.

## Why FetchedBillsPanel is refreshed through this same list

Every bill file downloaded to disk, across all bills — searchable by
number/title, filterable by the "how recent" chips, with a sticky header
while scrolling.

Refreshed by live updates through the PIPELINE_LLM_ONLY_PROPS list.

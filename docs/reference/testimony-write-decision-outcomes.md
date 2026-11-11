---
mode: reference
summary: "Lists the four possible outcomes of FetchHearingsService#testimony_write_decision, their meaning, and why they are mutually exclusive."
status: agent-extracted
related: []
---
# Testimony write-decision outcomes

<!-- vale Vale.Spelling = NO -->

`FetchHearingsService#testimony_write_decision` decides what a hearing-fetch
run is entitled to say about a bill's testimony. It returns exactly one of
four symbols, listed below with their exact meaning. For the history behind
why the logic has four outcomes instead of two, see
`docs/explanation/testimony-write-decision.md`.

## The four outcomes

| Outcome | Meaning |
| --- | --- |
| `:replace` | This run built text; the newly composed text is the truth and overwrites whatever was stored. |
| `:retract` | Nothing was built this run, AND discovery proved that nothing qualifies as testimony — solid enough grounds to delete the previously stored evidence. |
| `:retain_with_notice` | Nothing was built this run, but for a PASSING reason: discovery came back empty, the sweep of the matter's events/attachments was incomplete, or every candidate in hand failed to produce text. Not solid grounds to delete anything — the stored column is kept, and the admin list says so. |
| `:none` | Nothing was built this run, and there is nothing stored to take back either. |

## The ordering contract

`:retract` and `:retain_with_notice` can never both apply at once.
`#nothing_qualified?` requires a positive discovery count; `#discovery_returned_nothing?`
requires a zero discovery count. Because the two conditions are mutually
exclusive by construction, the order the outcomes are checked in expresses
intent rather than resolving a tie between competing answers.

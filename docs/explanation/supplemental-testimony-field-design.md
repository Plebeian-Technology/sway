---
mode: explanation
summary: "Explains three design decisions behind SupplementalTestimonyField: why it is always editable, why Clear only shows when the server has a stored value, and why it has its own Save button."
status: agent-extracted
related: [docs/explanation/supplemental-testimony-write-rule.md, docs/explanation/supplemental-testimony-clear-endpoint-rationale.md]
---

<!-- vale Vale.Spelling = NO -->

# Why the supplemental testimony field is shaped the way it is

`SupplementalTestimonyField` is the supplemental testimony text box on the
bill creator's LLM summary screen. Three separate decisions shaped it.

## It is editable on every branch that draws it

It used to be read-only on the generate branch's `pending` row and editable
everywhere else, which stopped being one rule when a queued row that holds
an earlier summary started reaching the completed view: the same server
state got two answers, decided by whether the last run had left anything
behind. Editable is the one that is true — the queued job reads this column
at perform time, so a save made now IS the text that run uses, and read-only
meant an operator pasting testimony while a run was queued had no way to
keep it.

## It owns its own Clear button

That button shows only when the SERVER has a value stored (`storedValue`),
because clearing is something the server does and there is nothing to clear
otherwise. A button that merely emptied the box on screen would bring back
the old confusion, where an empty field did not mean an empty column in the
database. See [why the clear endpoint exists](supplemental-testimony-clear-endpoint-rationale.md)
for the backend half of this decision, and
[the write rule](supplemental-testimony-write-rule.md) for how a write tells
"cleared" apart from "never touched."

## It owns a Save button too

That is the other half of the same idea. Two other places on this screen
tell an operator to paste testimony here — the unreadable-attachment warning
and the no-testimony notice — and until this button existed the only
requests that carried the typed text were Generate and Regenerate, both of
which spend two paid model calls. So the free endpoint that already accepts
the value was used for exactly half of what it does. Worse, while a
pipeline run is going every paid button is switched off, which meant a
paste made at that moment could not be saved at all, and moving to another
tab threw the text away without a word.

Save appears only when the box differs from what the server holds, so it
reads as "there are unsaved changes" rather than as one more button.

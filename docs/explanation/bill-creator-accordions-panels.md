---
mode: explanation
summary: "Why the Bill Creator's LLM Summary accordion panel is a placeholder pointing at the Pipeline & LLM tab, and why the Bill form is remounted with an explicit key."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why BillCreatorAccordions is built the way it is

## Why the LLM Summary panel is a placeholder

The LLM Summary panel is a placeholder pointing at the Pipeline & LLM
tab — that's where summary review actually happens, not here.

## Why the Bill form is keyed by bill id

Belt-and-braces: forces the Bill form to rebuild. The shell already
remounts everything via a stateless router.visit when switching bills, so
useForm() already resets on its own.

This key guarantees a fresh useForm() even if a future visit keeps the
component alive across a bill change.

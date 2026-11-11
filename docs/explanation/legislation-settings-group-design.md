---
mode: explanation
summary: "Explains why Sway::Settings::Legislation uses bare-name env_prefix and why every one of its eight attributes defaults to nil."
status: agent-extracted
related: [docs/explanation/llm-settings-group-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Design notes for the Legislation settings group

`Sway::Settings::Legislation` (`lib/sway/settings/legislation.rb`) reads
eight names: seven filesystem roots for the legislation pipeline plus one
tesseract data directory, all consumed by `Legislation::Paths` and
`MupdfExtractor`.

## Why env_prefix is empty

The class declares an empty `env_prefix` — bare-name mode — rather than
`"LEGISLATION"`. Seven of the eight names already carry `LEGISLATION_` as
part of their own attribute name, but the eighth, `tessdata_prefix`
(`TESSDATA_PREFIX`), shares nothing with them. A group cannot declare a
shared prefix that only seven of its eight names carry, so it reads each
bare name instead. That is also why `TESSDATA_PREFIX` lives in this group
rather than in `Ops`: its only reader is a pipeline stage, and bare-name mode
makes that no different from living anywhere else — the same rule the `Llm`
settings group uses for splitting `LLM_*` and `LLAMACPP_*` (see
[llm-settings-group-design](llm-settings-group-design.md)).

## Why every attribute defaults to nil

Defaults are the one real decision in this group, and every attribute here
defaults to `nil` — none of them is `required` — which differs from every
other settings group. The root's real default today is a path built at run
time from `Rails.root`, not a fixed string, and each stage's real "default"
is "fall back to the root." Neither is a value this class can hold.
Declaring a literal default here, or marking the attribute required (which
would then raise for every environment that legitimately leaves it unset —
every environment but production, for `legislation_root`), would either
duplicate that rule or break it. `Legislation::Paths` is the one place that
turns a nil attribute into an actual path, exactly as it did before this
class existed.

`tessdata_prefix` carries the same nil default for a different reason: it is
set by the production Docker image itself
(`docker/dockerfiles/production.alpine.dockerfile`), never by Kamal, and
making it required at boot would stop a development machine without
tesseract from starting at all. `MupdfExtractor.preflight!` already fails
loudly, with three distinct messages naming the cause, the moment OCR is
actually attempted — that check is unchanged by this class.

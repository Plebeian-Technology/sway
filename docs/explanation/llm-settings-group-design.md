---
mode: explanation
summary: "Explains the env-prefix, timing, and type-coercion design decisions behind Sway::Settings::Llm."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Design notes for the Llm settings group

`Sway::Settings::Llm` (`lib/sway/settings/llm.rb`) reads nine names across two
unrelated env-var prefixes, `LLM_*` and `LLAMACPP_*`, consumed by five source
files: `Llm::Client` (which provider to use), `Llm::LlamacppAdapter` (the
local model's base address, request deadline, and whether it thinks first),
and the two prompt builders (four caps on how much text leaves the
building). It declares an empty `env_prefix` — bare-name mode — because no
single prefix covers both `LLM_` and `LLAMACPP_` names, the same rule the
legislation settings group uses for `TESSDATA_PREFIX` beside `LEGISLATION_*`.

This group is where later phases add settings: a candidate list, and a
provider-and-model pair. Its shape is deliberate — nine flat attributes
today, ready for more of the same shape.

## The Rails.env.development? class-body timing

Three defaults call `Rails.env.development?` in the class body. That reads
like the kind of line that gets "fixed," but it works because Rails sets the
environment in `config/boot.rb`, long before this file loads (the settings
load ordering). The other half of that: a default computed here is fixed **once**,
when the class loads. Nothing in this codebase changes `RAILS_ENV`
mid-process, and this class would not see it if something did — a test that
needs a different cap sets the setting itself (`with_app_config`), not the
environment.

## llm_llamacpp_thinking widens the switch

The raw `ENV.fetch` this setting replaced compared against the literal text
`"1"` only. Declaring it `:boolean` means every one of `"true"`, `"yes"`,
`"y"`, `"1"`, `"t"` (case-insensitive) switches it on — strictly wider than
before, and the value both `.env.development.example` and `.env.test.example`
carry (`"1"`) still means the same thing.

## Who owns the four caps' zero-or-negative fallback

The four caps' "zero or negative means use the default" behavior is not
declared in this class. `Sway::Settings::Llm` only removes the failure where
unreadable text became a silent zero — its strict `:integer` caster raises
instead. "0 (or negative) means use the default" stays a caller-side
rule: `BillSummaryPromptBuilder.max_source_chars` and its three siblings in
`BillPositionsPromptBuilder` keep it, exactly as
`LlamacppAdapter.request_timeout_seconds` already does for
`llm_request_timeout_seconds`.

## Why the "every reader defaults" spec forces `llm_request_timeout_seconds: nil`

`spec/lib/sway/settings_spec.rb`'s "defaults every one of its nine readers"
example constructs `Sway::Settings::Llm.new(llm_request_timeout_seconds:
nil)` rather than leaving the value ambient. The dip rspec image sets a
real `LLM_REQUEST_TIMEOUT_SECONDS=300` (a slower-machine accommodation, not
this class's concern) — the same ambient-ENV hazard measured against
`TESSDATA_PREFIX` in the legislation settings group (68-04/68-05). An
explicit `nil` override forces the class's own declared default regardless
of what the container's real environment holds.

## Why an empty `LLM_PROVIDER` never reaches `Llm::Client.build`'s unknown-provider branch

An empty `LLM_PROVIDER` — a typo, a `kamal env push` slip — must not reach
the unknown-provider branch, which would raise outside the job's rescue
chain and strand rows in `generating` forever. The declaration's own blank
repair answers this now, not a second fallback inside `.build`.
`spec/services/llm/client_spec.rb`'s `"treats LLM_PROVIDER='' (empty) as
'llamacpp'"` example builds a fresh `Sway::Settings::Llm` rather than going
through the memoized reader, matching the pattern the other groups'
blank-value regression specs already use.

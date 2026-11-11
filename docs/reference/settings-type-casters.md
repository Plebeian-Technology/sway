---
mode: reference
summary: "Documents the exact behavior of the four custom Anyway::Config type casters every Sway::Settings group inherits from Base."
status: agent-extracted
related: [../explanation/settings-type-caster-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Sway::Settings type casters

`Sway::Settings::Base` registers four custom casters on
`Anyway::TypeRegistry.default`, replacing the gem's own `:string`,
`:integer`/`:integer!`, `:float`/`:float!`, and `:boolean` casters for every
settings group. Each strips the raw value first; a value that is blank
after stripping is treated as absent (`nil`).

| Type | Input | Result |
|---|---|---|
| `:string` | Blank after `.strip` | `nil` |
| `:string` | Non-blank | The stripped string |
| `:integer` / `:integer!` | Blank | `nil` |
| `:integer` / `:integer!` | A whole number in base 10 (e.g. `"42"`, `"030"`, `"-7"`) | The `Integer` value, read explicitly in base 10 |
| `:integer` / `:integer!` | Anything not a valid base-10 whole number (e.g. `"lots"`) | Raises `ArgumentError` |
| `:float` / `:float!` | Blank | `nil` |
| `:float` / `:float!` | Matches `/\A[+-]?(\d+(\.\d+)?\|\.\d+)([eE][+-]?\d+)?\z/` (e.g. `"1.5"`, `"-2"`, `"3e10"`) | The `Float` value |
| `:float` / `:float!` | Anything else, including a `"0x..."` hex literal | Raises `ArgumentError` |
| `:boolean` | Blank | `nil` |
| `:boolean` | One of `true`, `yes`, `y`, `1`, `t` (case-insensitive) | `true` |
| `:boolean` | Any other non-blank text | `false` |

`Sway::Settings::Base` also calls `disable_auto_cast!`, so a value stays
text until one of these casters moves it, and repairs `on_load`: any
attribute holding `nil` after casting falls back to its declared default.

See [Why these casters exist](../explanation/settings-type-caster-design.md)
for the reasoning behind the base-10 and hex-rejection rules, and for why
`:boolean` stays lenient on unrecognized text instead of raising.

---
mode: explanation
summary: "Explains why FetchBillsService#coerce_introduction_date handles String, Integer, nil, and everything else differently, instead of collapsing any bad value to nil."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Coercing Legistar's `MatterIntroDate`

`FetchBillsService#coerce_introduction_date` handles Legistar's
`MatterIntroDate` field carefully. The old logic turned any non-`String`
value into `nil`, which made
`LegislationIngestionService#apply_bill_attributes`'s
`bill.introduced_date_time_utc ||= Time.current` fallback kick in — quietly
stamping the bill with "now" if Legistar ever sent a Unix timestamp
`Integer` or a JSON date object.

The current logic instead branches on the value's actual shape:

- **`String`** — parsed with `Time.zone.parse`. That call returns `nil` for
  a string it merely cannot make sense of, but RAISES `ArgumentError` for
  one that is plainly impossible (`"99-99-99"`, `"2025-13-45"`). Both cases
  are caught and routed through `#warn_intro_date`, returning `nil` so a
  problem with the data alone logs a warning and does not abort the entire
  run-level stage or terminate the run for every other bill.
- **`Integer`** — treated as seconds since the Unix epoch, via
  `Time.zone.at`. This is guarded the same way as the `String` branch: an
  epoch far outside what `Time` can hold raises `RangeError`, which nothing
  above this method catches (`#call_discover` rescues only `Faraday` and
  `Legistar` errors) — so one absurd number in the upstream feed would
  otherwise end the run for every remaining bill, inside a method written
  to stop bad data from doing exactly that.
- **`nil`** — passed through quietly. Legistar legitimately leaves this out
  on matters that are only attachments.
- **anything else** — logged through `#warn_intro_date` and coerced to
  `nil`, matching the String and Integer branches. While this allows
  `LegislationIngestionService#apply_bill_attributes` to fall back to
  stamping the current run time (`Time.current`), it ensures an unexpected
  upstream type produces an operator warning without aborting the run-level
  stage and terminating the pipeline for every other bill.

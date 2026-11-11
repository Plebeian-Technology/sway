---
mode: explanation
summary: "Explains where config/cable.yml's polling_interval ceiling comes from and why the spec that checks it only proves the poll has room to keep the promise, not that it does."
status: agent-extracted
related: []
---

# Why `spec/config/cable_spec.rb` bounds `polling_interval` at half a second

`config/cable.yml`'s `polling_interval` controls how long a Solid Cable
broadcast can sit before a listener finds it. The ceiling checked in
`spec/config/cable_spec.rb`'s `"the poll"` block is a promise: the
pipeline screens were specified to converge within one second, a requirement
restated across several rounds of planning. That promise lived only
in planning notes no gate could read, so a config change once missed it
in silence — this spec exists because that happened.

The one-second budget splits into a message waiting up to one
`polling_interval` to be found, plus the partial reload that follows,
which costs another round trip (about 150ms measured on the dev host).
Half the budget (`convergence_budget / 2`) is the poll's share once that
round trip is set aside.

The spec reads a number out of a config file. It does not time a real
broadcast, so it cannot say the promise is KEPT, only that the poll has
room to keep it. Measuring the real thing is tracked separately.

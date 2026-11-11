---
lat:
  mode: explanation
---

# Why the query-count subscriber block keeps its |*, payload| shape

Counting SQL queries inside a block in these request specs is written `|*, payload|`.

Counting SQL queries inside a block in these request specs is written `|*, payload|` — a splat followed by a required parameter — which Steep, the Ruby type checker, cannot parse ("Block definition with trailing required parameters are not supported yet"). This same shape already appears elsewhere in the suite for the same purpose, so it is an accepted baseline rather than a one-off gap.

Naming all five block parameters explicitly dodges the parser error, but then `payload` resolves to the wrong type against the gem's own type signatures — a problem that cannot be fixed from the call site — so the `|*, payload|` form stays despite the Steep gap.

Each measurement is written out inline rather than shared through a lambda helper, specifically to avoid a second copy of the same parser problem: a shared helper would just move the unparseable block to one more place Steep has to skip.

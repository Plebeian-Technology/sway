---
mode: explanation
summary: "Explains why ParseSectionsService::FuzzyRatio hand-rolls a Levenshtein similarity score instead of using a gem, and why the two-row Wagner-Fischer implementation needs no reset between passes."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why FuzzyRatio hand-rolls Levenshtein instead of using a gem

`ParseSectionsService::FuzzyRatio` is a pure-Ruby similarity score for two
strings, based on Levenshtein edit distance (how many single-character
changes turn one string into the other), computed with the Wagner-Fischer
algorithm. It reproduces `rapidfuzz.fuzz.ratio`'s normalized similarity
formula on the 0-100 integer scale, matching how the Python original used
it (two thresholds: 97 when the strings are the same length, 90 otherwise).

## Why it is hand-rolled

No string-similarity gem (`text`, `amatch`, `levenshtein-ffi`) exists in
the Gemfile, and the porting effort was pinned to its four existing gem
additions (`faraday-retry`, `json_schemer`, `ruby-openai`, `diff-lcs`) —
adding a new gem was not acceptable.

## Why the two-row implementation needs no reset between passes

`#levenshtein` keeps only two rows in memory (`prev` and `curr`) rather
than a full m×n matrix. After the row swap at the end of each outer-loop
pass, `curr` still holds the prior row's stale entries at `[1..n]` — that
is fine: `curr[0] = i` reseeds position 0 on the next pass, and the inner
`j`-loop assigns every `curr[j]` for `j` in `1..n` before anything reads
it. No reset of `curr` is required; the algorithm is correct as written.

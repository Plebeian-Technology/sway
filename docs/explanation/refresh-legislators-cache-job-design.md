---
mode: explanation
summary: "Why RefreshLegislatorsCacheJob lets a pull-request failure escape #perform uncaught, and why a locale that declares no refresher is fetched by nothing rather than falling back to Baltimore."
status: agent-extracted
related: [github-pr-service-design]
---

<!-- vale Vale.Spelling = NO -->

# Why `RefreshLegislatorsCacheJob` is shaped the way it is

## Why a pull-request failure bubbles up instead of being rescued

The rescue that isolates one locale's refresh failure from another sits
INSIDE the `find_each` loop, per-locale. `GitHubPrService#open_pr` runs
AFTER that loop, once, with nothing catching it. A branch-name collision
(`Octokit::UnprocessableEntity`, which happens when the job runs twice in
one day) or a GitHub rate limit (`Octokit::TooManyRequests`) therefore has
to escape `#perform` entirely, letting ActiveJob's own retry and backoff
handle it — it must NOT be swallowed in silence the way a single locale's
refresh failure is. Because this failure never enters the per-locale
rescue, it also never takes the per-locale Sentry-reporting path; it
surfaces through ActiveJob's own failure handling instead.

## Why a locale that declares no refresher is fetched by nothing

`RefreshLegislatorsCacheJob` used to choose a locale's refresher by asking
whether it was Congress, a state, or neither — and `#local?` IS "neither",
so all eleven locales that registration creates for readers' own cities
(one per city a user registers from, not just Baltimore) got Baltimore's
council refresher run against them. The job now looks up the refresher
through the locale's own `declared_jurisdiction_rules` instead, and a
locale with no declaration is fetched by nothing at all, rather than
silently defaulting to Baltimore's.

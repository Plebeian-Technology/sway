---
lat:
  mode: explanation
---

# Why the OpenStates House/Senate scrapers' vote_number raises

This scraper used to do nothing at all without saying so: `vote_number` returned `nil`, and `result.dig` looked up symbol keys in JSON whose keys were strings.

Each bug hid the other. Until an OpenStates region outside Maryland is actually hooked up, the scraper raises `NotImplementedError`, so `OpenStatesLegislatorVoteUpdateService` cannot quietly fall back to guessing votes from who sponsored the bill.

`spec/scraper/scraper/open_states/house/legislator_votes_spec.rb` and `spec/scraper/scraper/open_states/senate/legislator_votes_spec.rb` each pin this with `"raises NotImplementedError because the per-state path is unwired"`.

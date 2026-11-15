---
lat:
  require-code-mention: true
---
# Legislator vote fixture tests

Regression checks for [[spec/factories/legislator_votes.rb]] cover legislator identity, defaults, overrides and uniqueness; runtime matching belongs to [[legislation-pipeline#Upstream jurisdiction adapters]]. Scoped types live in [[sig-test/factories/legislator_votes.rbs]] and [[sig-test/jobs/legislator_vote_sweep_job_spec.rbs]].

## Term-owned legislator

A supplied term determines the default legislator, keeping fixture identity paired without an unsupported model association assignment.

## Default vote

A vote built with no overrides is a manual, non-inferred FOR vote, and the factory creates no term for its legislator.

## Traits and explicit vote overrides

Support and inferred traits retain their values, and explicit support, inference, and source overrides take precedence over trait defaults.

## Duplicate bill and legislator

A second row for the same bill and legislator is rejected by the database, preventing concurrent importer and admin inserts from double-counting a roll call.

---
lat:
  require-code-mention: true
---
# Legislator vote fixture tests

Regression checks for [[spec/factories/legislator_votes.rb]] cover term identifiers, identity, reuse and overrides; runtime matching belongs to [[legislation-pipeline#Upstream jurisdiction adapters]]. Scoped types live in [[sig-test/factories/legislator_votes.rbs]] and [[sig-test/jobs/legislator_vote_sweep_job_spec.rbs]].

## Supplied historical term

The supplied term identifier survives initialization and persistence, belongs to the vote's legislator, and covers the historical vote day through [[app/models/term_window.rb#TermWindow|the term window]].

## Term-owned legislator

A supplied term determines the default legislator, keeping fixture identity paired without an unsupported model association assignment.

## Raw term identifier override

An explicit term identifier survives initialization without generating another term, preserving callers that supply database attributes directly.

## Default paired term

A legislator without terms receives the deterministic default from [[spec/factories/legislator_terms.rb]], bound to the same person and locale, while manual source and vote defaults remain intact.

## Existing term reuse

The existing person and default start-year term is reused without increasing the term count, guarding the unique person/start-year constraint.

## Traits and explicit vote overrides

Support and inferred traits retain their values, and explicit support, inference, and source overrides take precedence over trait defaults.

## Duplicate bill and term

A second row for the same bill and term is rejected by the database, preventing concurrent importer and admin inserts from double-counting a roll call; setup supplies the original term identifier to exercise uniqueness.

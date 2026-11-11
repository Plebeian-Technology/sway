---
lat:
  require-code-mention: true
---
# Legislator vote sweep test design

Behavioral checks in [[spec/jobs/legislator_vote_sweep_job_spec.rb]] detect query and enqueue defects without depending on source spelling.

## Executing the prefilter

Running [[app/jobs/legislator_vote_sweep_job.rb#LegislatorVoteSweepJob#perform|the sweep]] exposes an invalid singular association join; matching source text would miss runtime behavior and reject harmless query refactors.

The bill's plural vote association is exercised by the no-error example and the separate multiple-roll-call deduplication example. Together they detect invalid joins and duplicate enqueues while allowing equivalent query implementations.

## Bounded pacing

A reduced wait ceiling lets four bills exercise the enqueue ramp and cap through actual scheduled waits rather than a copied source expression.

This reaches both branches with a small fixture set, so the check observes the pacing limit without creating thousands of bills to reach the production ceiling.

## Exact enqueue arguments

Negative enqueue assertions match the sweep's single bill identifier; a trailing matcher would describe a two-argument call that the sweep never makes.

The single-slot matcher cannot stand for arbitrary remaining arguments. Adding it after the bill identifier would make a negative assertion pass even when the supposedly filtered bill was enqueued.

---
lat:
  mode: explanation
---

# Live-LLM HTTP policy: why both WebMock and VCR are set

`LiveLlmGate.apply_http_policy!` (`spec/support/live_llm_gate.rb`) is the suite's single rule for what outgoing HTTP is allowed during a test run.

It is worked out once here rather than written next to each library that enforces part of it.

## The rule is a guarantee, not just a toggle

Calling `apply_http_policy!` is safe to call repeatedly and reversible both ways: a spec can flip `RUN_LIVE_LLM_TESTS`, apply the policy again, and hand the suite back exactly as it found it.

## Both halves are required — neither is enough alone

VCR (which records and replays HTTP) is hooked into WebMock with `allow_http_connections_when_no_cassette = false`, so VCR refuses a request with no recording before WebMock's allowlist is even consulted.

A host VCR ignores still has to get past WebMock separately. Setting only WebMock's half is what once left the documented `RUN_LIVE_LLM_TESTS=1` path making zero live calls, while the header of `claude_adapter_integration_spec.rb` quoted a per-run dollar cost for nine of them — the flag looked wired up but the requests never left the process.

Real report from the test container:

| WebMock allow | VCR ignore | Result       |
| -------------- | ---------- | ------------ |
| no             | no         | no record    |
| yes            | no         | recorded     |
| no             | yes        | recorded     |

Unlike the LLM host itself, either library suffices on its own — both are set so one rule covers every host without depending on which library happens to intercept first.

## What else the allowlist has to cover

Additional endpoint requirements including token verification hosts, telemetry proxies, and mock adapter destinations.

- **`api.anthropic.com`** is the only host `RUN_LIVE_LLM_TESTS=1` ever opens up
  — named once in `LiveLlmGate::HOST` so the HTTP rules and
  `CachePrefixTokenizer` cannot end up spelling it differently.
- **localhost** is allowed under either setting. Capybara starts a real Puma
  server and sends a localhost `__identify__` request before each system
  spec, which WebMock/VCR's default rules would otherwise reject.
- **The local error collector** is allowed too (via
  `LocalErrorCollectorHosts.allowed`), or a test run's own error reports to
  `rustrak:8080` are refused with nothing printed. This set is
  empty when no collector is configured.

## Timeout

A live call must never take the Anthropic SDK's 600-second default — one stuck request would hold up a whole suite for ten minutes before any fallback ran. `LiveLlmGate::TIMEOUT_SECONDS` caps it at 15.

## Why ANTHROPIC_API_KEY alone is not consent

A development shell commonly exports `ANTHROPIC_API_KEY` from a secret store, so it is often simply present in an ordinary working shell and says nothing about whether the person who typed `rspec` meant to reach Anthropic.

`RUN_LIVE_LLM_TESTS=1` is the half that carries intent, and it has to be checked everywhere a real call could go out — not only in the one spec file that happens to be named "integration."

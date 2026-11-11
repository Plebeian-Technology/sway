---
lat:
  mode: explanation
---

# Why FakeErrorCollector checks the wire, not the object

`FakeErrorCollector` (`spec/support/fake_error_collector.rb`) stands in for the local error collector's receiving end, so a test can check what the app PUTS ON THE WIRE rather than what it builds in memory.

Every rule it enforces was paid for. Each one is a real refusal, measured by hand against the running collector, that no test in the suite could see. The whole Ruby half of error reporting was dead while the suite was green, because the fault lived in a header and nothing read the headers — see `docs/explanation/error-scrubber-empty-fingerprint-bug.md` for one of the bugs this check surfaced.

This is deliberately NOT a copy of the collector. It only knows the handful of ways this app has actually managed to send something unusable, not every way the real protocol could be violated.

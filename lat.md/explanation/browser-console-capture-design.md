---
lat:
  mode: explanation
---

# Why BrowserConsoleCapture.drain is destructive, and warns selectively

`BrowserConsoleCapture` prints what the browser logged when a `:js` system spec fails, because a Capybara failure names what it could not find, never what broke.

`#drain` reads and clears the browser's console log — destructive by design. Draining after every example, not just failing ones, stops one example's console output from being reported against a LATER example's failure.

The rescue in `#drain` distinguishes two different kinds of silence. A driver with no console at all (`rack_test`) is quiet by returning `[]` early, no warning — that is the expected, correct case for a non-browser driver. A driver that HAS a real browser and still fails to read its console WARNS instead of silently returning `[]`: that silent-failure shape is how this capture reported nothing for its first hour in production use, with no signal that anything had gone wrong. `NoMethodError` is deliberately not rescued here; only the real Selenium failure shapes are guarded, so a genuine bug in the capture code still raises rather than being swallowed alongside the expected failure modes.

## Why the "captures below WARNING" example is the one that matters

`spec/system/browser_console_capture_spec.rb`'s "captures below WARNING" example is the only one that notices if `logging_prefs` goes missing from `spec/support/system_driver.rb`.

An earlier version of the gate planted a `console.error`, which chromedriver returns regardless of the logging preference level, so that version guarded nothing — it could not fail even with the preference removed.
